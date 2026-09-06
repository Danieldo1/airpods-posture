import Foundation
#if canImport(AirPostureCore)
import AirPostureCore
#endif

private var failures = 0
@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
        failures += 1
    }
}

@MainActor
private func near(_ actual: Double, _ expected: Double, _ name: String, tolerance: Double = 0.000_001) {
    expect(actual.isFinite && abs(actual - expected) <= tolerance,
           "\(name): expected \(expected), got \(actual)")
}

private func total(_ output: BustAnimationOutput) -> BustVector3 {
    BustVector3(
        x: output.chestEulerRadians.x + output.neckEulerRadians.x + output.headEulerRadians.x,
        y: output.chestEulerRadians.y + output.neckEulerRadians.y + output.headEulerRadians.y,
        z: output.chestEulerRadians.z + output.neckEulerRadians.z + output.headEulerRadians.z
    )
}

private func settle(_ input: BustTrackingPose, config: BustAnimationConfig = .init(), fps: Int = 30,
                    seconds: Double = 4) -> BustAnimationOutput {
    var processor = BustAnimationProcessor(config: config)
    for _ in 0..<Int(seconds * Double(fps)) {
        _ = processor.step(input: input, deltaTime: 1 / Double(fps))
    }
    return processor.output
}

// Reversing any one raw axis or accidentally adding the chest rotation twice
// changes the rendered direction/angle and must fail these fixed fixtures.
@MainActor
private func testDirectionsAndRigDistribution() {
    var processor = BustAnimationProcessor()
    let out = processor.step(input: .init(pitch: -10, roll: 10, yaw: 10, expression: .leaning),
                             deltaTime: 1 / 30, reduceMotion: true)
    let angles = total(out)
    near(angles.x, 0.226_892_802_759, "chin down is positive X", tolerance: 0.000_001)
    near(angles.y, -0.261_799_387_799, "positive yaw mirrors toward screen left", tolerance: 0.000_001)
    near(angles.z, 0.261_799_387_799, "positive roll mirrors toward screen left", tolerance: 0.000_001)
    near(out.headEulerRadians.x / angles.x, 0.7, "head receives 70 percent")
    near((out.chestEulerRadians.x + out.neckEulerRadians.x) / angles.x, 0.3,
         "neck receives 30 percent including chest compensation")
    expect(out.neckOffset.z > 0, "chin down moves neck forward")
    expect(out.leftShoulderOffset.y > out.rightShoulderOffset.y,
           "screen-left/anatomical-right shoulder drops with positive roll")
    expect(out.leftShoulderOffset.z > 0 && out.rightShoulderOffset.z > 0,
           "slouch brings both shoulders forward")
    let reverse = processor.step(input: .init(pitch: 10, roll: -10, yaw: -10, expression: .upright),
                                 deltaTime: 1 / 30, reduceMotion: true)
    expect(total(reverse).x < 0 && total(reverse).y > 0 && total(reverse).z < 0,
           "opposite measurements reverse all axes")
    near(reverse.neckOffset.z, 0, "chin up never invents a slouch")
}

// Amplification must remain bounded for valid extreme sensor samples, while
// independently adjustable axes must still affect the visible attitude.
@MainActor
private func testAmplificationAndClamps() {
    var processor = BustAnimationProcessor()
    let out = processor.step(input: .init(pitch: -1e100, roll: 1e100, yaw: 1e100, expression: .slouching),
                             deltaTime: 1 / 30, reduceMotion: true)
    near(total(out).x, 0.610_865_238_198, "pitch capped at 35 degrees")
    near(total(out).y, -0.785_398_163_397, "mirrored yaw capped at 45 degrees")
    near(total(out).z, 0.523_598_775_598, "mirrored roll capped at 30 degrees")
    expect(out.neckOffset.z <= 0.07 && out.neckOffset.z > 0, "neck offset bounded at model scale")
    processor.config.yawMultiplier = 2
    let customized = processor.step(input: .init(yaw: 10, expression: .upright), deltaTime: 0,
                                    reduceMotion: true)
    near(total(customized).y, -0.349_065_850_399, "live multiplier reaches mirrored output")
}

// A frame-count alpha or unconstrained pause delta produces different poses.
@MainActor
private func testFrameRateAndPauseHandling() {
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    let pose = BustTrackingPose(pitch: -18, roll: 8, yaw: 20, expression: .leaning)
    let thirty = settle(pose, config: config, fps: 30, seconds: 0.4)
    let sixty = settle(pose, config: config, fps: 60, seconds: 0.4)
    near(thirty.processedPose.pitch, sixty.processedPose.pitch, "30 vs 60 fps pitch", tolerance: 0.35)
    near(thirty.processedPose.yaw, sixty.processedPose.yaw, "30 vs 60 fps yaw", tolerance: 0.35)
    expect(thirty.processedPose.pitch < -13 && thirty.processedPose.pitch > -18,
           "large movement responds promptly without snapping")
    var paused = BustAnimationProcessor(config: config)
    var bounded = BustAnimationProcessor(config: config)
    let long = paused.step(input: pose, deltaTime: 600)
    let short = bounded.step(input: pose, deltaTime: 0.1)
    near(long.processedPose.pitch, short.processedPose.pitch, "pause delta capped to 100ms")
    let before = paused.output
    expect(paused.step(input: .init(pitch: 20, expression: .upright), deltaTime: 0) == before,
           "zero delta preserves the cached frame")
    expect(paused.step(input: pose, deltaTime: .nan) == before, "nonfinite delta preserves the cached frame")
}

// A filter that advances its response or dead-zone state once per render frame
// can agree for a single held target yet diverge during turns and reversals.
// Both renderers consume the SAME timestamped 30 Hz sensor samples: the 60 Hz
// renderer sees each sample twice, never an interpolated extra sensor reading.
@MainActor
private func testMovingSamplesAcrossRenderRates() {
    let keyframes: [(time: Double, pose: BustTrackingPose)] = [
        (0, .init(expression: .upright)),
        (1, .init(expression: .upright)),
        (3, .init(pitch: -20, roll: 12, yaw: 24, expression: .leaning)),
        (5, .init(pitch: 10, roll: -12, yaw: -24, expression: .leaning)),
        (6, .init(pitch: -15, roll: 4, yaw: 12, expression: .slouching)),
        (9, .init(pitch: -15, roll: 4, yaw: 12, expression: .slouching)),
        (11, .init(expression: .upright)),
        (14, .init(expression: .upright))
    ]
    let sensorPeriod = 1.0 / 30
    let samples = (0..<420).map { index -> (time: Double, pose: BustTrackingPose) in
        let time = Double(index) * sensorPeriod
        var segment = 0
        while segment + 1 < keyframes.count - 1 && time >= keyframes[segment + 1].time {
            segment += 1
        }
        let start = keyframes[segment]
        let end = keyframes[segment + 1]
        let fraction = (time - start.time) / (end.time - start.time)
        return (time, .init(
            pitch: start.pose.pitch + (end.pose.pitch - start.pose.pitch) * fraction,
            roll: start.pose.roll + (end.pose.roll - start.pose.roll) * fraction,
            yaw: start.pose.yaw + (end.pose.yaw - start.pose.yaw) * fraction,
            expression: end.pose.expression
        ))
    }
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    var thirty = BustAnimationProcessor(config: config)
    var sixty = BustAnimationProcessor(config: config)
    let radiansToDegrees = 180 / Double.pi
    for sample in samples {
        let lowerRate = thirty.step(input: sample.pose, deltaTime: sensorPeriod)
        _ = sixty.step(input: sample.pose, deltaTime: sensorPeriod / 2)
        let higherRate = sixty.step(input: sample.pose, deltaTime: sensorPeriod / 2)
        let time = sample.time + sensorPeriod
        near(lowerRate.processedPose.pitch, higherRate.processedPose.pitch,
             "moving pitch at common timestamp \(time)", tolerance: 0.5)
        near(lowerRate.processedPose.roll, higherRate.processedPose.roll,
             "moving roll at common timestamp \(time)", tolerance: 0.5)
        near(lowerRate.processedPose.yaw, higherRate.processedPose.yaw,
             "moving yaw at common timestamp \(time)", tolerance: 0.5)
        let lowerAngles = total(lowerRate)
        let higherAngles = total(higherRate)
        near(lowerAngles.x * radiansToDegrees, higherAngles.x * radiansToDegrees,
             "moving rendered pitch at \(time)", tolerance: 0.5)
        near(lowerAngles.y * radiansToDegrees, higherAngles.y * radiansToDegrees,
             "moving rendered yaw at \(time)", tolerance: 0.5)
        near(lowerAngles.z * radiansToDegrees, higherAngles.z * radiansToDegrees,
             "moving rendered roll at \(time)", tolerance: 0.5)

        // During the first constant-speed ramp, no more than 0.30s of lag plus
        // the 0.4-degree held dead zone is allowed. These independent limits
        // reflect the default 0.28s settling response plus one sensor interval.
        if sample.time >= 2 && sample.time <= 3 {
            for pose in [lowerRate.processedPose, higherRate.processedPose] {
                near(pose.pitch, sample.pose.pitch, "moving pitch response at \(time)", tolerance: 3.4)
                near(pose.roll, sample.pose.roll, "moving roll response at \(time)", tolerance: 2.2)
                near(pose.yaw, sample.pose.yaw, "moving yaw response at \(time)", tolerance: 4.0)
            }
        }
        // After the final fast reversal, allow five settling time constants
        // (1.4s); the remaining half-degree allowance includes held dead zone.
        if sample.time >= 7.4 && sample.time < 9 {
            for pose in [lowerRate.processedPose, higherRate.processedPose] {
                near(pose.pitch, -15, "moving pitch settles after reversal", tolerance: 0.5)
                near(pose.roll, 4, "moving roll settles after reversal", tolerance: 0.5)
                near(pose.yaw, 12, "moving yaw settles after reversal", tolerance: 0.5)
            }
        }
        if sample.time >= 13 {
            for pose in [lowerRate.processedPose, higherRate.processedPose] {
                near(pose.pitch, 0, "returning pitch does not drift", tolerance: 0.05)
                near(pose.roll, 0, "returning roll does not drift", tolerance: 0.05)
                near(pose.yaw, 0, "returning yaw does not drift", tolerance: 0.05)
            }
        }
    }
}

// Dead zones only around zero would let noisy AirPods samples move a held,
// already nonzero head. A slow deliberate change must eventually escape it.
@MainActor
private func testSettlingAndHeldNoise() {
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    var processor = BustAnimationProcessor(config: config)
    let held = BustTrackingPose(pitch: -18, roll: 8, yaw: 20, expression: .leaning)
    for _ in 0..<240 { _ = processor.step(input: held, deltaTime: 1 / 30) }
    let baseline = processor.output.processedPose
    for i in 0..<180 {
        let amplitude = i < 90 ? 0.1 : 0.18
        let noise = i.isMultiple(of: 2) ? amplitude : -amplitude
        _ = processor.step(input: .init(pitch: -18 + noise, roll: 8 + noise, yaw: 20 + noise,
                                        expression: .leaning), deltaTime: 1 / 30)
        near(processor.output.processedPose.pitch, baseline.pitch, "held pitch rejects jitter", tolerance: 0.001)
        near(processor.output.processedPose.roll, baseline.roll, "held roll rejects jitter", tolerance: 0.001)
        near(processor.output.processedPose.yaw, baseline.yaw, "held yaw rejects jitter", tolerance: 0.001)
    }
    for i in 1...90 {
        _ = processor.step(input: .init(pitch: -18 + Double(i) / 30, roll: 8, yaw: 20,
                                        expression: .leaning), deltaTime: 1 / 30)
    }
    expect(processor.output.processedPose.pitch > -16, "deliberate slow movement escapes held dead zone")
    let final = settle(held, config: config)
    near(final.processedPose.pitch, -18, "held posture settles", tolerance: 0.005)
}

// Removing additive composition would pull a nonzero tracked pose to neutral;
// a fixed blink loop would give identical successive onset intervals.
@MainActor
private func testIdleAndIrregularBlinking() {
    var processor = BustAnimationProcessor()
    let held = BustTrackingPose(pitch: -15, roll: 9, yaw: 20, expression: .upright)
    var minimum = Double.infinity
    var maximum = -Double.infinity
    var breathingMin = Double.infinity
    var breathingMax = -Double.infinity
    var blinkStarts: [Double] = []
    var wasClosed = false
    for i in 0..<1200 {
        let out = processor.step(input: held, deltaTime: 1 / 30)
        expect(out.eyeOpenness >= 0.08 && out.eyeOpenness <= 1, "eye scale stays in safe range")
        if i > 120 {
            minimum = min(minimum, total(out).y)
            maximum = max(maximum, total(out).y)
            breathingMin = min(breathingMin, out.breathing)
            breathingMax = max(breathingMax, out.breathing)
            near(out.processedPose.yaw, 20, "idle preserves measured yaw", tolerance: 0.001)
        }
        let closed = out.eyeOpenness < 0.6
        if closed && !wasClosed { blinkStarts.append(Double(i) / 30) }
        wasClosed = closed
    }
    expect(maximum - minimum > 0.001 && maximum - minimum < 0.035,
           "stationary head gets tiny bounded additive drift")
    expect(maximum < -0.49, "idle never overwrites held mirrored 30-degree visual yaw")
    expect(breathingMax - breathingMin > 0.001 && breathingMax - breathingMin < 0.02,
           "breathing is subtle and alive")
    expect(blinkStarts.count >= 5, "irregular blink generator runs")
    if blinkStarts.count >= 4 {
        let first = blinkStarts[1] - blinkStarts[0]
        expect(blinkStarts.dropFirst(2).enumerated().contains {
            abs($0.element - blinkStarts[$0.offset + 1] - first) > 0.2
        }, "blink intervals are not a fixed repeating period")
    }
}

// Accessibility must snap to the measured pose and stop autonomous animation;
// inactive must clear a stale slouch and any queued blink immediately.
@MainActor
private func testReducedMotionInactiveAndExpressions() {
    var processor = BustAnimationProcessor()
    let out = processor.step(input: .init(pitch: -15, yaw: 20, expression: .slouching), deltaTime: 0,
                             reduceMotion: true)
    near(out.processedPose.pitch, -15, "reduce motion snaps immediately")
    near(out.breathing, 0, "reduce motion disables breathing")
    near(out.eyeOpenness, 1, "reduce motion disables blinking")
    near(total(out).y, -0.523_598_775_598, "reduce motion disables head drift")
    expect(out.frownWeight > 0.7 && out.smileWeight == 0, "slouch concern follows supplied band")
    expect(out.leftBrowAngleRadians < 0 && out.rightBrowAngleRadians > 0,
           "concern raises inner brow corners with anatomical side convention")
    let neutral = processor.step(input: .init(pitch: -30, roll: 30, yaw: 30, expression: .inactive), deltaTime: 0)
    near(total(neutral).x, 0, "inactive clears pitch")
    near(total(neutral).y, 0, "inactive clears yaw")
    near(total(neutral).z, 0, "inactive clears roll")
    near(neutral.neckOffset.z, 0, "inactive clears neck offset")
    near(neutral.eyeOpenness, 1, "inactive opens eyes")
    near(neutral.smileWeight + neutral.frownWeight, 0, "inactive expression is neutral")
    let upright = settle(.init(pitch: -20, expression: .upright))
    let leaning = settle(.init(expression: .leaning))
    let slouching = settle(.init(expression: .slouching))
    expect(upright.smileWeight > 0.25 && upright.frownWeight < 0.01,
           "upright smile trusts supplied band even at a negative pitch")
    expect(leaning.frownWeight > 0.1 && leaning.frownWeight < slouching.frownWeight,
           "leaning concern is milder than slouching")
    _ = processor.step(input: .init(expression: .upright), deltaTime: 1 / 30, reduceMotion: true)
    let transition = processor.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    expect(transition.smileWeight > 0 && transition.frownWeight > 0 && transition.frownWeight < 0.7,
           "expression changes blend over time")
}

// Corrupt samples/settings must not poison cached transforms indefinitely.
@MainActor
private func testFiniteInputAndConfiguration() {
    var processor = BustAnimationProcessor()
    _ = processor.step(input: .init(pitch: -10, roll: 8, yaw: 20, expression: .leaning),
                       deltaTime: 1 / 30, reduceMotion: true)
    let out = processor.step(input: .init(pitch: .nan, roll: .infinity, yaw: -.infinity, expression: .leaning),
                             deltaTime: 1 / 30)
    expect(total(out).x.isFinite && total(out).y.isFinite && total(out).z.isFinite,
           "nonfinite sample never reaches bones")
    near(out.processedPose.pitch, -10, "invalid sample holds last valid pitch")
    var badConfig = BustAnimationConfig()
    badConfig.yawMultiplier = .infinity
    badConfig.pitchMultiplier = .nan
    badConfig.responseSeconds = 0
    badConfig.settlingSeconds = -1
    badConfig.maxRollDegrees = .nan
    badConfig.idleIntensity = .infinity
    processor.config = badConfig
    let safe = processor.step(input: .init(pitch: -30, roll: 20, yaw: 40, expression: .slouching),
                              deltaTime: 1 / 30)
    expect(total(safe).x.isFinite && total(safe).y.isFinite && total(safe).z.isFinite,
           "invalid live settings have safe finite fallbacks")
}

// Reflection must affect the rendered attitude and its inferred body side,
// while measured diagnostics and chin-down pitch retain their original values.
@MainActor
private func testMirrorPreservesMeasurementsAndReflectsShoulders() {
    var processor = BustAnimationProcessor()
    let positive = processor.step(input: .init(pitch: -12, roll: 8, yaw: 16, expression: .leaning),
                                  deltaTime: 0, reduceMotion: true)
    let negative = processor.step(input: .init(pitch: -12, roll: -8, yaw: -16, expression: .leaning),
                                  deltaTime: 0, reduceMotion: true)
    near(positive.processedPose.pitch, -12, "mirror preserves measured pitch")
    near(positive.processedPose.roll, 8, "mirror preserves measured roll")
    near(positive.processedPose.yaw, 16, "mirror preserves measured yaw")
    near(negative.processedPose.roll, -8, "mirror preserves negative measured roll")
    near(negative.processedPose.yaw, -16, "mirror preserves negative measured yaw")
    near(total(positive).x, 0.272_271_363_311, "mirroring leaves chin-down pitch unchanged")
    near(total(positive).x, total(negative).x, "lateral reflection does not change pitch")
    near(total(positive).y, -total(negative).y, "yaw reflects around center")
    near(total(positive).z, -total(negative).z, "roll reflects around center")
    expect(total(negative).z < 0 && total(negative).y > 0,
           "negative hardware lateral input now moves toward screen right")
    near(positive.leftShoulderOffset.y, negative.rightShoulderOffset.y, "reflection swaps shoulder heights")
    near(positive.rightShoulderOffset.y, negative.leftShoulderOffset.y, "opposite shoulder reflects")
    near(positive.neckOffset.z, negative.neckOffset.z, "reflection preserves forward neck translation")
    near(positive.leftElbowEulerRadians.x, negative.rightElbowEulerRadians.x,
         "reflection swaps inferred elbow flex")
}

// Static arm/face cues remain available with incidental gestures disabled;
// shoulder/elbow association must match the reflected leaning side.
@MainActor
private func testStaticArmsAndAsymmetricBrows() {
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    config.gestureIntensity = 0
    var processor = BustAnimationProcessor(config: config)
    let upright = processor.step(input: .init(expression: .upright), deltaTime: 0, reduceMotion: true)
    let lean = processor.step(input: .init(roll: 12, expression: .leaning), deltaTime: 0, reduceMotion: true)
    let slouch = processor.step(input: .init(pitch: -24, expression: .slouching), deltaTime: 0, reduceMotion: true)
    expect(lean.rightElbowEulerRadians.x < lean.leftElbowEulerRadians.x,
           "mirrored leaning-side elbow flexes a little more")
    expect(slouch.leftElbowEulerRadians.x < upright.leftElbowEulerRadians.x - 0.03 &&
           slouch.rightElbowEulerRadians.x < upright.rightElbowEulerRadians.x - 0.03,
           "slouch gently flexes both elbows from relaxed rest")
    expect(slouch.leftShoulderOffset.y < upright.leftShoulderOffset.y &&
           slouch.rightShoulderOffset.y < upright.rightShoulderOffset.y,
           "static slouch drops both shoulders")
    expect(lean.leftBrowHeight > lean.rightBrowHeight + 0.003,
           "leaning has a small stable inquisitive brow asymmetry")
    near(lean.browHeight, (lean.leftBrowHeight + lean.rightBrowHeight) / 2, "shared brow debug height is the mean")
    expect(slouch.frownWeight > 0.7 && upright.smileWeight > 0.25,
           "gesture intensity zero preserves core expression")
    expect(abs(slouch.leftWristEulerRadians.x) < 0.04 && abs(slouch.rightWristEulerRadians.x) < 0.04,
           "wrists stay restrained relative to relaxed hand rest")
}

// A band transition should play one finite recovery gesture. Restarting it
// for every repeated sample, changing tracked head pose, or omitting decay fails.
@MainActor
private func testRecoveryGestureIsOneShotAndSubordinate() {
    var animatedConfig = BustAnimationConfig()
    animatedConfig.idleIntensity = 0
    var staticConfig = animatedConfig
    staticConfig.gestureIntensity = 0
    var animated = BustAnimationProcessor(config: animatedConfig)
    var animatedSixty = BustAnimationProcessor(config: animatedConfig)
    var baseline = BustAnimationProcessor(config: staticConfig)
    let slouch = BustTrackingPose(pitch: -15, roll: 4, yaw: 8, expression: .slouching)
    for _ in 0..<90 {
        _ = animated.step(input: slouch, deltaTime: 1 / 30)
        _ = animatedSixty.step(input: slouch, deltaTime: 1 / 60)
        _ = animatedSixty.step(input: slouch, deltaTime: 1 / 60)
        _ = baseline.step(input: slouch, deltaTime: 1 / 30)
    }
    let recovered = BustTrackingPose(pitch: -15, roll: 4, yaw: 8, expression: .upright)
    var peakBrowRaise = 0.0
    var peakElbowFlex = 0.0
    var peakLeftOpening = 0.0
    var peakRightOpening = 0.0
    for frame in 0..<120 {
        let out = animated.step(input: recovered, deltaTime: 1 / 30)
        _ = animatedSixty.step(input: recovered, deltaTime: 1 / 60)
        let higherRate = animatedSixty.step(input: recovered, deltaTime: 1 / 60)
        let held = baseline.step(input: recovered, deltaTime: 1 / 30)
        near(out.leftBrowHeight, higherRate.leftBrowHeight, "recovery eyebrow timing agrees at 30/60 Hz")
        near(out.leftElbowEulerRadians.x, higherRate.leftElbowEulerRadians.x,
             "recovery elbow timing agrees at 30/60 Hz")
        let browRaise = out.leftBrowHeight - held.leftBrowHeight
        peakBrowRaise = max(peakBrowRaise, browRaise)
        peakElbowFlex = max(peakElbowFlex, held.leftElbowEulerRadians.x - out.leftElbowEulerRadians.x)
        peakLeftOpening = max(peakLeftOpening, out.leftShoulderEulerRadians.z - held.leftShoulderEulerRadians.z)
        peakRightOpening = min(peakRightOpening, out.rightShoulderEulerRadians.z - held.rightShoulderEulerRadians.z)
        expect(out.processedPose == held.processedPose, "gesture preserves processed tracker values")
        expect(out.headEulerRadians == held.headEulerRadians && out.neckEulerRadians == held.neckEulerRadians &&
               out.chestEulerRadians == held.chestEulerRadians, "gesture does not displace tracked head or torso")
        if frame >= 24 {
            near(browRaise, 0, "recovery brow pulse decays and does not restart")
            expect(out.leftElbowEulerRadians == held.leftElbowEulerRadians &&
                   out.rightElbowEulerRadians == held.rightElbowEulerRadians,
                   "recovery elbows return to held pose without repeated pulses")
            expect(out.leftShoulderEulerRadians == held.leftShoulderEulerRadians &&
                   out.rightShoulderEulerRadians == held.rightShoulderEulerRadians,
                   "recovery shoulders return to held pose")
        }
    }
    expect(peakBrowRaise > 0.02 && peakBrowRaise <= 0.035, "recovery brow raise is visible but bounded")
    expect(peakElbowFlex > 0.05 && peakElbowFlex < 0.09, "recovery elbow gesture stays around four degrees")
    expect(peakLeftOpening > 0.02 && peakRightOpening < -0.02,
           "recovery opens both arms outward in opposite directions")
}

// Upright arm presence is a tiny additive sway, independently suppressible
// without turning off the existing breathing and tracked-head animation.
@MainActor
private func testArmIdleIsSmallAndOptional() {
    var animated = BustAnimationProcessor()
    var staticConfig = BustAnimationConfig()
    staticConfig.gestureIntensity = 0
    var baseline = BustAnimationProcessor(config: staticConfig)
    var peak = 0.0
    for _ in 0..<360 {
        let out = animated.step(input: .init(expression: .upright), deltaTime: 1 / 30)
        let held = baseline.step(input: .init(expression: .upright), deltaTime: 1 / 30)
        peak = max(peak, max(abs(out.leftElbowEulerRadians.x), abs(out.rightElbowEulerRadians.x)))
        near(held.leftElbowEulerRadians.x, 0, "zero gesture intensity removes incidental arm sway")
        near(held.rightElbowEulerRadians.x, 0, "zero gesture intensity removes opposite arm sway")
        expect(out.headEulerRadians == held.headEulerRadians && out.breathing == held.breathing,
               "arm sway setting leaves head idle and breathing independent")
    }
    expect(peak > 0.004 && peak <= 0.008_727, "upright arm idle stays within half a degree")
    let still = animated.step(input: .init(expression: .upright), deltaTime: 0, reduceMotion: true)
    near(still.leftElbowEulerRadians.x, 0, "reduce motion stops left arm idle")
    near(still.rightElbowEulerRadians.x, 0, "reduce motion stops right arm idle")
}

// Near a threshold, alternating upright/leaning samples must not restart the
// brow pulse continuously. A two-second refractory window leaves a quiet gap.
@MainActor
private func testBandChatterCannotKeepGesturesAlive() {
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    var animated = BustAnimationProcessor(config: config)
    var staticConfig = config
    staticConfig.gestureIntensity = 0
    var baseline = BustAnimationProcessor(config: staticConfig)
    _ = animated.step(input: .init(expression: .upright), deltaTime: 1 / 30)
    _ = baseline.step(input: .init(expression: .upright), deltaTime: 1 / 30)
    var peakRaise = 0.0
    for frame in 0..<56 {
        let band: BustExpression = (frame / 3).isMultiple(of: 2) ? .leaning : .upright
        let out = animated.step(input: .init(expression: band), deltaTime: 1 / 30)
        let held = baseline.step(input: .init(expression: band), deltaTime: 1 / 30)
        let raise = out.leftBrowHeight - held.leftBrowHeight
        peakRaise = max(peakRaise, raise)
        if frame >= 24 {
            near(raise, 0, "rapid band chatter cannot sustain eyebrow pulses")
        }
        near(out.leftElbowEulerRadians.y, 0, "ordinary band chatter never splays elbows")
        near(out.rightElbowEulerRadians.y, 0, "ordinary band chatter never splays opposite elbow")
    }
    expect(peakRaise > 0.01 && peakRaise <= 0.021, "first brow reaction completes once during band chatter")

    animated = BustAnimationProcessor(config: config)
    baseline = BustAnimationProcessor(config: staticConfig)
    _ = animated.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    _ = baseline.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    for _ in 0..<8 {
        _ = animated.step(input: .init(expression: .upright), deltaTime: 1 / 30)
        _ = baseline.step(input: .init(expression: .upright), deltaTime: 1 / 30)
    }
    let interrupted = animated.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    let held = baseline.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    expect(interrupted.leftElbowEulerRadians == held.leftElbowEulerRadians &&
           interrupted.rightElbowEulerRadians == held.rightElbowEulerRadians,
           "renewed slouch cancels welcoming arm gesture immediately")
    for frame in 0..<36 {
        let band: BustExpression = frame.isMultiple(of: 2) ? .upright : .slouching
        let out = animated.step(input: .init(expression: band), deltaTime: 1 / 30)
        let reference = baseline.step(input: .init(expression: band), deltaTime: 1 / 30)
        expect(out.leftElbowEulerRadians == reference.leftElbowEulerRadians,
               "recovery chatter cannot retrigger welcoming arms during cooldown")
        near(out.leftBrowHeight, reference.leftBrowHeight,
             "recovery chatter cannot retrigger eyebrow raise during cooldown")
    }
}

// Accessibility and inactive lifecycle changes cancel a pending pulse; replay
// after resuming would create a surprising gesture unrelated to a new band.
@MainActor
private func testGestureResetAndReducedMotion() {
    var config = BustAnimationConfig()
    config.idleIntensity = 0
    var processor = BustAnimationProcessor(config: config)
    _ = processor.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    for _ in 0..<8 { _ = processor.step(input: .init(expression: .upright), deltaTime: 1 / 30) }
    let neutral = processor.step(input: .init(), deltaTime: 0)
    near(neutral.leftElbowEulerRadians.x, 0, "inactive clears elbow gesture")
    near(neutral.rightElbowEulerRadians.y, 0, "inactive clears opposite elbow gesture")
    near(neutral.leftWristEulerRadians.y, 0, "inactive clears wrist gesture")
    near(neutral.leftBrowHeight + neutral.rightBrowHeight, 0, "inactive clears raised eyebrows")
    var staticConfig = config
    staticConfig.gestureIntensity = 0
    var baseline = BustAnimationProcessor(config: staticConfig)
    _ = processor.step(input: .init(expression: .slouching), deltaTime: 0, reduceMotion: true)
    _ = baseline.step(input: .init(expression: .slouching), deltaTime: 0, reduceMotion: true)
    let snapped = processor.step(input: .init(expression: .upright), deltaTime: 0, reduceMotion: true)
    let held = baseline.step(input: .init(expression: .upright), deltaTime: 0, reduceMotion: true)
    expect(snapped == held, "reduce motion snaps static expression and disables gestures")
    for _ in 0..<60 {
        let out = processor.step(input: .init(expression: .upright), deltaTime: 1 / 30)
        let reference = baseline.step(input: .init(expression: .upright), deltaTime: 1 / 30)
        near(out.leftBrowHeight, reference.leftBrowHeight, "no deferred brow pulse after reduced motion")
        expect(out.leftElbowEulerRadians == reference.leftElbowEulerRadians,
               "no deferred arm pulse after reduced motion")
    }
    processor.config.gestureIntensity = .nan
    _ = processor.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
    let safe = processor.step(input: .init(expression: .upright), deltaTime: 1 / 30)
    expect(safe.leftElbowEulerRadians.x.isFinite && safe.leftBrowHeight.isFinite &&
           safe.rightWristEulerRadians.y.isFinite, "invalid gesture setting stays finite")
    for amount in [Double.infinity, -100, 1e100] {
        var extremeConfig = config
        extremeConfig.gestureIntensity = amount
        var extreme = BustAnimationProcessor(config: extremeConfig)
        _ = extreme.step(input: .init(expression: .slouching), deltaTime: 1 / 30)
        for _ in 0..<24 {
            let out = extreme.step(input: .init(expression: .upright), deltaTime: 1 / 30)
            expect(out.leftBrowHeight.isFinite && out.leftBrowHeight < 0.075 &&
                   out.leftElbowEulerRadians.x.isFinite && abs(out.leftElbowEulerRadians.x) < 0.2,
                   "oversized or nonfinite gesture settings stay bounded")
            if amount < 0 {
                near(out.leftElbowEulerRadians.y, 0, "negative gesture intensity clamps to disabled")
            }
        }
    }
}

MainActor.assumeIsolated {
    testDirectionsAndRigDistribution()
    testAmplificationAndClamps()
    testFrameRateAndPauseHandling()
    testMovingSamplesAcrossRenderRates()
    testSettlingAndHeldNoise()
    testIdleAndIrregularBlinking()
    testReducedMotionInactiveAndExpressions()
    testFiniteInputAndConfiguration()
    testMirrorPreservesMeasurementsAndReflectsShoulders()
    testStaticArmsAndAsymmetricBrows()
    testRecoveryGestureIsOneShotAndSubordinate()
    testArmIdleIsSmallAndOptional()
    testBandChatterCannotKeepGesturesAlive()
    testGestureResetAndReducedMotion()

    if failures > 0 {
        FileHandle.standardError.write(Data("\(failures) bust animation check(s) failed\n".utf8))
        exit(1)
    }
    print("AirPosture bust animation checks passed")
}
