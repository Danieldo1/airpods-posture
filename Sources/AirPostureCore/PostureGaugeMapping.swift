public struct BustVector3: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct BustPose: Equatable, Sendable {
    public let neckEulerRadians: BustVector3
    public let headEulerRadians: BustVector3
    public let neckOffset: BustVector3
    public let headOffset: BustVector3

    public init(
        neckEulerRadians: BustVector3,
        headEulerRadians: BustVector3,
        neckOffset: BustVector3,
        headOffset: BustVector3
    ) {
        self.neckEulerRadians = neckEulerRadians
        self.headEulerRadians = headEulerRadians
        self.neckOffset = neckOffset
        self.headOffset = headOffset
    }
}

public enum PostureGaugeMapping {
    public static let maxTilt = 30.0
    public static let maxLean = 20.0

    public static func displayedPose(
        pitch: Double,
        roll: Double,
        isCalibrated: Bool
    ) -> (pitch: Double, roll: Double) {
        guard isCalibrated else {
            return (0, 0)
        }
        return (pitch, roll)
    }

    public static func normalizedPoint(pitch: Double, roll: Double) -> (x: Double, y: Double) {
        (
            clamp(roll / maxLean, min: -1, max: 1),
            clamp(-pitch / maxTilt, min: -1, max: 1)
        )
    }

    public static func washBankDegrees(roll: Double) -> Double {
        normalizedPoint(pitch: 0, roll: roll).x * 18
    }

    public static func pitchVisualDegrees(_ pitch: Double) -> Double {
        clamp(pitch, min: -28, max: 16) * 0.55
    }

    public static func rollVisualDegrees(_ roll: Double) -> Double {
        clamp(roll, min: -24, max: 24) * 0.45
    }

    public static func yawVisualDegrees(_ yaw: Double) -> Double {
        clamp(yaw, min: -40, max: 40) * 0.45
    }

    /// Shortest signed path from `baseline` to `current` on a ±180° circle.
    public static func wrappedDegreesDelta(current: Double, baseline: Double) -> Double {
        var delta = current - baseline
        while delta > 180 {
            delta -= 360
        }
        while delta < -180 {
            delta += 360
        }
        return delta
    }

    public static func isLookingAway(
        yawDelta: Double,
        threshold: Double,
        enabled: Bool
    ) -> Bool {
        guard enabled else { return false }
        return abs(yawDelta) >= threshold
    }

    public static func bustEulerRadians(
        pitch: Double,
        roll: Double,
        yaw: Double = 0
    ) -> (x: Double, y: Double, z: Double) {
        let degreesToRadians = Double.pi / 180
        return (
            -pitchVisualDegrees(pitch) * degreesToRadians,
            // Positive yaw (look right) → negative eulerY so the bust faces pad-right,
            // matching positive roll's lean-right visual convention.
            -yawVisualDegrees(yaw) * degreesToRadians,
            -rollVisualDegrees(roll) * degreesToRadians
        )
    }

    /// Splits the measured headphone attitude across a neck and head pivot.
    /// Negative pitch is the forward/chin-down direction, so it also produces
    /// a small forward-and-down offset that makes slouch visible in silhouette.
    public static func bustPose(
        pitch: Double,
        roll: Double,
        yaw: Double = 0
    ) -> BustPose {
        let total = bustEulerRadians(pitch: pitch, roll: roll, yaw: yaw)
        let neck = BustVector3(
            x: total.x * 0.55,
            y: total.y * 0.25,
            z: total.z * 0.35
        )
        let head = BustVector3(
            x: total.x - neck.x,
            y: total.y - neck.y,
            z: total.z - neck.z
        )
        let slouch = clamp(max(-pitch, 0) / 28, min: 0, max: 1)

        return BustPose(
            neckEulerRadians: neck,
            headEulerRadians: head,
            neckOffset: BustVector3(x: 0, y: -0.02 * slouch, z: 0.04 * slouch),
            headOffset: BustVector3(x: 0, y: -0.07 * slouch, z: 0.14 * slouch)
        )
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
