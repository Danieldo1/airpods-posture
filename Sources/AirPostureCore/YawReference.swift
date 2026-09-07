import Foundation

/// Owns the zero point for head turn.
///
/// Tilt and lean are measured against a baseline the user saved deliberately.
/// Yaw has no such baseline: the headphones choose an arbitrary yaw origin every
/// time they establish a reference frame, so the zero has to be taken from the
/// sensor itself. That makes the zero's lifetime the whole problem, which is why
/// every rule about when it survives, when it moves, and when it must be
/// discarded lives here instead of being spread across the tracking call sites.
public struct YawReference: Equatable, Sendable {
    /// Nil until a sample establishes the zero for the current reference frame.
    public private(set) var zeroDegrees: Double?

    private var zeroAgeSeconds: Double = 0

    private let minTimeConstantSeconds: Double
    private let maxTimeConstantSeconds: Double
    private let maxStepSeconds: Double

    /// - Parameters:
    ///   - minTimeConstantSeconds: How fluid a freshly captured zero is. The
    ///     sensor's yaw is still converging for the first few seconds after it
    ///     establishes a frame, so a new zero has to be treated as provisional.
    ///   - maxTimeConstantSeconds: How stiff a matured zero becomes, which sets
    ///     how much of a sustained real turn survives.
    ///   - maxStepSeconds: Ceiling on one sample's contribution, so a sample
    ///     arriving after a long gap cannot yank the zero across in one go.
    public init(
        minTimeConstantSeconds: Double = 2,
        maxTimeConstantSeconds: Double = 120,
        maxStepSeconds: Double = 0.5
    ) {
        self.minTimeConstantSeconds = minTimeConstantSeconds
        self.maxTimeConstantSeconds = maxTimeConstantSeconds
        self.maxStepSeconds = maxStepSeconds
    }

    /// Turn angle for `yawDegrees`, establishing the zero if the frame is new.
    ///
    /// The sensor's yaw wanders even when the head is still, so the zero is
    /// eased toward the head's resting heading as samples arrive. The pull
    /// weakens as the zero ages: fresh zeros are captured mid-convergence and
    /// need to move, settled ones should hold still so real turns still read.
    ///
    /// - Parameter recenterWithinDegrees: Resting band. Turns beyond it are
    ///   treated as deliberate look-aways and freeze the zero. Pass 0 to hold
    ///   the zero completely still.
    public mutating func turnDegrees(
        forYaw yawDegrees: Double,
        elapsedSeconds: Double = 0,
        recenterWithinDegrees: Double = 0
    ) -> Double {
        guard let zero = zeroDegrees else {
            zeroDegrees = yawDegrees
            zeroAgeSeconds = 0
            return 0
        }

        let turn = PostureGaugeMapping.wrappedDegreesDelta(current: yawDegrees, baseline: zero)
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return turn }

        let step = min(elapsedSeconds, maxStepSeconds)
        zeroAgeSeconds += step
        guard recenterWithinDegrees > 0, abs(turn) < recenterWithinDegrees else { return turn }

        let timeConstant = min(maxTimeConstantSeconds, max(minTimeConstantSeconds, zeroAgeSeconds))
        let pull = 1 - exp(-step / timeConstant)
        let moved = PostureGaugeMapping.wrappedDegreesDelta(current: zero + pull * turn, baseline: 0)
        zeroDegrees = moved
        return PostureGaugeMapping.wrappedDegreesDelta(current: yawDegrees, baseline: moved)
    }

    /// Discards the zero because the sensor's reference frame changed: sleep/wake,
    /// a headphone reconnect, or restarted motion updates. A gap in samples is not
    /// such a change, and must not come through here.
    public mutating func invalidate() {
        zeroDegrees = nil
        zeroAgeSeconds = 0
    }

    /// Moves the zero to the current heading because the user asked for it.
    public mutating func rezero(toYaw yawDegrees: Double) {
        zeroDegrees = yawDegrees
        zeroAgeSeconds = 0
    }
}
