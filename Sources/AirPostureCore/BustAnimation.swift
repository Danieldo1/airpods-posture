import Foundation

public enum BustExpression: String, Sendable {
    case upright, leaning, slouching, inactive
}

/// Calibrated AirPods angles in degrees. Expression comes from the app's
/// existing posture band; this visual layer never classifies posture itself.
public struct BustTrackingPose: Equatable, Sendable {
    public var pitch: Double
    public var roll: Double
    public var yaw: Double
    public var expression: BustExpression

    public init(pitch: Double = 0, roll: Double = 0, yaw: Double = 0,
                expression: BustExpression = .inactive) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.expression = expression
    }
}

/// Live visual tuning only; no field changes tracking, scoring, or posture bands.
/// Times are seconds, limits/dead zones are degrees, and offsets use a 2-unit bust.
/// Invalid live settings fall back to finite defaults and are bounded on use.
public struct BustAnimationConfig: Equatable, Sendable {
    public var yawMultiplier: Double = 1.5
    public var pitchMultiplier: Double = 1.3
    public var rollMultiplier: Double = 1.5
    public var maxYawDegrees: Double = 45
    public var maxPitchDownDegrees: Double = 35
    public var maxPitchUpDegrees: Double = 24
    public var maxRollDegrees: Double = 30
    public var chestInfluence: Double = 0.18
    public var shoulderInfluence: Double = 0.5
    public var neckShare: Double = 0.3
    public var neckForwardOffset: Double = 0.07
    public var shoulderOffset: Double = 0.025
    public var deadZoneDegrees: Double = 0.28
    public var hysteresisDegrees: Double = 0.12
    public var responseSeconds: Double = 0.11
    public var settlingSeconds: Double = 0.28
    public var idleIntensity: Double = 1
    /// Scales incidental arm sway and one-shot band reactions. Zero preserves
    /// static posture/expression cues while disabling those extra gestures.
    public var gestureIntensity: Double = 1

    public init() {}
}

/// Cached local rig adjustments relative to each joint's rest transform.
/// Canonical axes are +Y up / +Z face / +X screen-right. Left and right are
/// anatomical: the avatar's left is screen-right. Offsets assume a bust that
/// is 2 model units tall. `breathing` is a dimensionless scale adjustment.
public struct BustAnimationOutput: Equatable, Sendable {
    public let processedPose: BustTrackingPose
    public let headEulerRadians: BustVector3
    public let neckEulerRadians: BustVector3
    public let chestEulerRadians: BustVector3
    public let neckOffset: BustVector3
    public let leftShoulderEulerRadians: BustVector3
    public let rightShoulderEulerRadians: BustVector3
    public let leftShoulderOffset: BustVector3
    public let rightShoulderOffset: BustVector3
    public let leftElbowEulerRadians: BustVector3
    public let rightElbowEulerRadians: BustVector3
    public let leftWristEulerRadians: BustVector3
    public let rightWristEulerRadians: BustVector3
    public let breathing: Double
    public let eyeOpenness: Double
    public let leftBrowAngleRadians: Double
    public let rightBrowAngleRadians: Double
    /// Mean of the two eyebrow heights, retained for compact debug readouts.
    public let browHeight: Double
    public let leftBrowHeight: Double
    public let rightBrowHeight: Double
    public let smileWeight: Double
    public let frownWeight: Double

    public static let neutral = BustAnimationOutput(
        processedPose: .init(), headEulerRadians: .zero, neckEulerRadians: .zero,
        chestEulerRadians: .zero, neckOffset: .zero, leftShoulderEulerRadians: .zero,
        rightShoulderEulerRadians: .zero, leftShoulderOffset: .zero, rightShoulderOffset: .zero,
        leftElbowEulerRadians: .zero, rightElbowEulerRadians: .zero,
        leftWristEulerRadians: .zero, rightWristEulerRadians: .zero,
        breathing: 0, eyeOpenness: 1, leftBrowAngleRadians: 0, rightBrowAngleRadians: 0,
        browHeight: 0, leftBrowHeight: 0, rightBrowHeight: 0, smileWeight: 0, frownWeight: 0
    )
}

public struct BustAnimationProcessor: Sendable {
    public var config: BustAnimationConfig
    public private(set) var output: BustAnimationOutput = .neutral

    private var pitch = HeldAxis()
    private var roll = HeldAxis()
    private var yaw = HeldAxis()
    private var elapsed: Double = 0
    private var idleAmount: Double = 0
    private var blink = BlinkState()
    private var smile: Double = 0
    private var frown: Double = 0
    private var browAsymmetry: Double = 0
    private var reaction = BandReaction()

    public init(config: BustAnimationConfig = .init()) {
        self.config = config
    }

    @discardableResult
    public mutating func step(input: BustTrackingPose, deltaTime: Double,
                              reduceMotion: Bool = false) -> BustAnimationOutput {
        // Inactive is a lifecycle change, so clear stale poses even while paused.
        guard input.expression != .inactive else {
            pitch = HeldAxis()
            roll = HeldAxis()
            yaw = HeldAxis()
            elapsed = 0
            idleAmount = 0
            blink = BlinkState()
            smile = 0
            frown = 0
            browAsymmetry = 0
            reaction = BandReaction()
            output = .neutral
            return output
        }
        let dt = deltaTime.isFinite ? bounded(deltaTime, 0, 0.1) : 0
        guard dt > 0 || reduceMotion else { return output }

        let deadZone = setting(config.deadZoneDegrees, fallback: 0.28, 0, 3)
        let hysteresis = setting(config.hysteresisDegrees, fallback: 0.12, 0, 2)
        let response = setting(config.responseSeconds, fallback: 0.11, 0.02, 2)
        let settling = max(response, setting(config.settlingSeconds, fallback: 0.28, 0.02, 3))
        pitch.update(input.pitch, dt: dt, deadZone: deadZone, hysteresis: hysteresis,
                     response: response, settling: settling, snap: reduceMotion)
        roll.update(input.roll, dt: dt, deadZone: deadZone, hysteresis: hysteresis,
                    response: response, settling: settling, snap: reduceMotion)
        yaw.update(input.yaw, dt: dt, deadZone: deadZone, hysteresis: hysteresis,
                   response: response, settling: settling, snap: reduceMotion)

        let smileTarget = input.expression == .upright ? 0.4 : 0
        let frownTarget: Double = switch input.expression {
        case .leaning: 0.3
        case .slouching: 0.85
        case .upright, .inactive: 0
        }
        let expressionAlpha = reduceMotion ? 1 : 1 - exp(-dt / 0.2)
        smile += (smileTarget - smile) * expressionAlpha
        frown += (frownTarget - frown) * expressionAlpha
        let asymmetryTarget = input.expression == .leaning ? 0.006 : 0
        browAsymmetry += (asymmetryTarget - browAsymmetry) * expressionAlpha

        let gestureIntensity = setting(config.gestureIntensity, fallback: 1, 0, 2)
        let reactionFrame = reaction.update(expression: input.expression, dt: dt,
                                              disabled: reduceMotion || gestureIntensity == 0)
        let recovery = reactionFrame.recovery * gestureIntensity
        let browReaction = reactionFrame.browRaise * gestureIntensity

        let idleIntensity = setting(config.idleIntensity, fallback: 1, 0, 2)
        var eyeOpenness = 1.0
        if reduceMotion {
            idleAmount = 0
            blink = BlinkState()
        } else {
            elapsed += dt
            let error = max(abs(pitch.target - pitch.value),
                            max(abs(roll.target - roll.value), abs(yaw.target - yaw.value)))
            let stationary = 1 - bounded(error / 3, 0, 1)
            idleAmount += (stationary - idleAmount) * (1 - exp(-dt / 0.7))
            eyeOpenness = blink.update(dt: dt)
        }

        let degrees = Double.pi / 180
        let maxDown = setting(config.maxPitchDownDegrees, fallback: 35, 0, 60) * degrees
        let maxUp = setting(config.maxPitchUpDegrees, fallback: 24, 0, 45) * degrees
        let maxYaw = setting(config.maxYawDegrees, fallback: 45, 0, 70) * degrees
        let maxRoll = setting(config.maxRollDegrees, fallback: 30, 0, 45) * degrees
        // Mirror the hardware's lateral attitude only in the visual layer:
        // positive measured yaw -> -Y and positive roll -> +Z (screen-left).
        // Negative measured pitch still tips the chin down around +X. Keep the
        // original measured signs in processedPose so diagnostics stay truthful.
        let trackedX = bounded(-pitch.value * setting(config.pitchMultiplier, fallback: 1.3, 0, 4) * degrees,
                               -maxUp, maxDown)
        let trackedY = bounded(-yaw.value * setting(config.yawMultiplier, fallback: 1.5, 0, 4) * degrees,
                               -maxYaw, maxYaw)
        let trackedZ = bounded(roll.value * setting(config.rollMultiplier, fallback: 1.5, 0, 4) * degrees,
                               -maxRoll, maxRoll)
        let intensity = reduceMotion ? 0 : idleAmount * idleIntensity
        // These tiny offsets are additive, and the final attitude still obeys
        // the visual limits. Incommensurate frequencies avoid a short idle loop.
        let idleX = intensity * degrees * 0.12 * sin(elapsed * 0.83)
        let idleY = intensity * degrees * (0.23 * sin(elapsed * 0.61) + 0.08 * sin(elapsed * 1.13))
        let idleZ = intensity * degrees * 0.15 * sin(elapsed * 0.73 + 0.4)
        let headIdleX = bounded(trackedX + idleX, -maxUp, maxDown) - trackedX
        let headIdleY = bounded(trackedY + idleY, -maxYaw, maxYaw) - trackedY
        let headIdleZ = bounded(trackedZ + idleZ, -maxRoll, maxRoll) - trackedZ

        let chestShare = setting(config.chestInfluence, fallback: 0.18, 0, 0.4)
        let neckShare = setting(config.neckShare, fallback: 0.3, 0.15, 0.5)
        let chest = BustVector3(x: trackedX * chestShare,
                                y: trackedY * chestShare * 0.25,
                                z: trackedZ * chestShare)
        // Chest is the parent of neck and shoulders; neck is the parent of head.
        // Subtract the chest's contribution from neck so torso inference cannot
        // amplify measured head motion a second time. The cervical chain gets
        // 30% and the head 70% by default. Euler sums are the small-angle design
        // contract; combined large multi-axis rotations are not quaternion-exact.
        let neck = BustVector3(x: trackedX * neckShare - chest.x,
                               y: trackedY * neckShare - chest.y,
                               z: trackedZ * neckShare - chest.z)
        let head = BustVector3(x: trackedX * (1 - neckShare) + headIdleX,
                               y: trackedY * (1 - neckShare) + headIdleY,
                               z: trackedZ * (1 - neckShare) + headIdleZ)

        // AirPods measure no torso or shoulder joints. This is restrained visual
        // inference: negative pitch advances the neck and rounds both shoulders;
        // mirrored roll depresses the leaning-side shoulder and raises its
        // opposite. Arm deltas layer on the asset's relaxed hanging/bent rest.
        let slouch = bounded(-pitch.value / 30, 0, 1)
        let lean = bounded(-roll.value / 20, -1, 1)
        let shoulderStrength = setting(config.shoulderInfluence, fallback: 0.5, 0, 1) * 2
        let shoulderDistance = setting(config.shoulderOffset, fallback: 0.025, 0, 0.06) * shoulderStrength
        let shoulderDrop = (slouch * 0.65 + frown * 0.16) * shoulderDistance
        let shoulderAsymmetry = lean * shoulderDistance * 0.35
        let shoulderX = (slouch * 0.08 + frown * 0.02) * shoulderStrength - recovery * degrees
        let shoulderZ = -lean * 0.07 * shoulderStrength
        let tuck = (slouch * 0.03 + frown * 0.015) * shoulderStrength
        let opening = recovery * degrees * 2
        let leftShoulder = BustVector3(x: shoulderX, y: 0, z: shoulderZ - tuck + opening)
        let rightShoulder = BustVector3(x: shoulderX, y: 0, z: shoulderZ + tuck - opening)
        let elbowFlex = (slouch * 0.06 + frown * 0.035) * shoulderStrength
        // At default settings the upright arm sway is at most half a degree.
        // It fades with tracking activity and remains subordinate to head pose.
        let armIdle = intensity * gestureIntensity * (smile / 0.4) * degrees * 0.5
        let leftArmIdle = armIdle * sin(elapsed * 0.67)
        let rightArmIdle = armIdle * sin(elapsed * 0.67 + 1.2)
        let leftElbow = BustVector3(
            x: -elbowFlex - max(lean, 0) * 0.025 * shoulderStrength - recovery * degrees * 4 + leftArmIdle,
            y: recovery * degrees * 3, z: 0
        )
        let rightElbow = BustVector3(
            x: -elbowFlex - max(-lean, 0) * 0.025 * shoulderStrength - recovery * degrees * 4 + rightArmIdle,
            y: -recovery * degrees * 3, z: 0
        )
        let wristX = (slouch * 0.012 + frown * 0.008) * shoulderStrength
        let browAngle = -frown * 0.20 + smile * 0.02
        let browBase = frown * 0.015 + smile * 0.004 + browReaction
        let leftBrowHeight = browBase + browAsymmetry
        let rightBrowHeight = browBase - browAsymmetry * 0.25
        output = BustAnimationOutput(
            processedPose: .init(pitch: pitch.value, roll: roll.value, yaw: yaw.value,
                                 expression: input.expression),
            headEulerRadians: head, neckEulerRadians: neck, chestEulerRadians: chest,
            neckOffset: .init(x: 0, y: 0,
                              z: slouch * setting(config.neckForwardOffset, fallback: 0.07, 0, 0.1)),
            leftShoulderEulerRadians: leftShoulder, rightShoulderEulerRadians: rightShoulder,
            leftShoulderOffset: .init(x: 0, y: -shoulderDrop - shoulderAsymmetry,
                                      z: slouch * shoulderDistance),
            rightShoulderOffset: .init(x: 0, y: -shoulderDrop + shoulderAsymmetry,
                                       z: slouch * shoulderDistance),
            leftElbowEulerRadians: leftElbow, rightElbowEulerRadians: rightElbow,
            leftWristEulerRadians: .init(x: wristX, y: recovery * 0.025, z: 0),
            rightWristEulerRadians: .init(x: wristX, y: -recovery * 0.025, z: 0),
            breathing: intensity * 0.0035 * sin(elapsed * (2 * Double.pi / 4.3) + 0.12 * sin(elapsed * 0.41)),
            eyeOpenness: eyeOpenness,
            leftBrowAngleRadians: browAngle, rightBrowAngleRadians: -browAngle,
            browHeight: (leftBrowHeight + rightBrowHeight) / 2,
            leftBrowHeight: leftBrowHeight, rightBrowHeight: rightBrowHeight,
            smileWeight: smile, frownWeight: frown
        )
        return output
    }
}

/// A finite band reaction driven by the same animation clock as tracking.
/// Repeated samples never restart it; a two-second refractory window prevents
/// threshold chatter from keeping it alive. Inactive/reduced-motion clears it.
private struct BandReaction: Sendable {
    private var previous: BustExpression = .inactive
    private var recoveryArmed = false
    private var age = -1.0
    private var isRecovery = false
    private var cooldownRemaining = 0.0

    mutating func update(expression: BustExpression, dt: Double,
                         disabled: Bool) -> (browRaise: Double, recovery: Double) {
        if disabled {
            previous = expression
            recoveryArmed = false
            age = -1
            isRecovery = false
            cooldownRemaining = 0
            return (0, 0)
        }
        cooldownRemaining = max(0, cooldownRemaining - dt)
        if expression != previous && previous != .inactive {
            if cooldownRemaining <= 0 {
                age = 0
                isRecovery = expression == .upright && recoveryArmed
                cooldownRemaining = 2
            } else if isRecovery && expression != .upright {
                // Tracking state takes priority over a welcoming gesture if
                // posture worsens again before the reaction has finished.
                age = -1
                isRecovery = false
            }
        }
        if expression == .slouching { recoveryArmed = true }
        if expression == .upright { recoveryArmed = false }
        previous = expression
        guard age >= 0 else { return (0, 0) }
        age += dt
        guard age < 0.72 else {
            age = -1
            return (0, 0)
        }
        let wave = sin(Double.pi * age / 0.72)
        let weight = wave * wave
        return (weight * (isRecovery ? 0.028 : 0.020), isRecovery ? weight : 0)
    }
}

private struct HeldAxis: Sendable {
    var value: Double = 0
    var target: Double = 0
    private var lastValid: Double = 0
    private var isFollowing = false

    mutating func update(_ raw: Double, dt: Double, deadZone: Double, hysteresis: Double,
                         response: Double, settling: Double, snap: Bool) {
        // Hold the last valid sample per axis instead of snapping corrupt input
        // to neutral. Bounding physically implausible input also avoids overflow.
        if raw.isFinite { lastValid = bounded(raw, -180, 180) }
        if snap {
            value = lastValid
            target = lastValid
            isFollowing = false
            return
        }
        let distance = abs(lastValid - target)
        let threshold = deadZone + (isFollowing ? 0 : hysteresis)
        if distance > threshold {
            target = lastValid
            isFollowing = true
        } else if distance <= deadZone {
            isFollowing = false
        }
        if abs(lastValid) <= deadZone && abs(target) <= deadZone + hysteresis {
            target = 0
        }
        let error = value - target
        let magnitude = abs(error)
        guard magnitude > 0 else { return }

        // Integrate a continuous adaptive exponential exactly for this target:
        // decay rate grows from 1/settling to 1/response over an 8-degree error.
        // Large moves are responsive; the last few degrees settle more gently.
        // The analytic step avoids frame-rate-dependent alpha or rate sampling.
        let slowRate = 1 / settling
        let fastRate = 1 / response
        let extraRate = fastRate - slowRate
        let transition = 8.0
        var remaining = dt
        var nextMagnitude = magnitude
        if nextMagnitude > transition {
            let fastDuration = min(remaining, log(nextMagnitude / transition) / fastRate)
            nextMagnitude *= exp(-fastRate * fastDuration)
            remaining -= fastDuration
        }
        if remaining > 0 {
            let decay = exp(-slowRate * remaining)
            nextMagnitude = nextMagnitude * decay /
                (1 + (extraRate / slowRate) * (nextMagnitude / transition) * (1 - decay))
        }
        value = target + (error < 0 ? -nextMagnitude : nextMagnitude)
    }
}

private struct BlinkState: Sendable {
    private var untilBlink = 2.8
    private var age = -1.0
    private var duration = 0.17
    private var randomState: UInt64 = 0xA17B_057E_9D31_C426

    mutating func update(dt: Double) -> Double {
        if age < 0 {
            untilBlink -= dt
            guard untilBlink <= 0 else { return 1 }
            age = -untilBlink
            duration = 0.14 + randomUnit() * 0.07
        } else {
            age += dt
        }
        if age >= duration {
            untilBlink = 2.6 + randomUnit() * 3.6 - (age - duration)
            age = -1
            return 1
        }
        let closure = sin(Double.pi * age / duration)
        return bounded(1 - 0.92 * closure * closure, 0.08, 1)
    }

    private mutating func randomUnit() -> Double {
        // Value-state PRNG: irregular blink spacing without per-frame closures,
        // timers, actions, allocations, or access to a shared random generator.
        randomState ^= randomState << 13
        randomState ^= randomState >> 7
        randomState ^= randomState << 17
        return Double(randomState >> 11) / 9_007_199_254_740_992
    }
}

private func bounded(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func setting(_ value: Double, fallback: Double, _ lower: Double, _ upper: Double) -> Double {
    bounded(value.isFinite ? value : fallback, lower, upper)
}

private extension BustVector3 {
    static let zero = BustVector3(x: 0, y: 0, z: 0)
}
