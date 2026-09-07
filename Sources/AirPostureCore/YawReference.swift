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

    /// The previous sample's heading, so a drift correction can be measured
    /// over the interval that actually elapsed between two samples.
    private var lastYawDegrees: Double?

    /// Motionless time accumulated while the turn sat past the look-away angle.
    private var heldStillPastThresholdSeconds: Double = 0

    private let maxDriftDegreesPerSecond: Double
    private let unlatchAfterSeconds: Double

    /// Ceiling on the interval one sample may claim, so a sample arriving after
    /// a stall cannot absorb a whole jump in a single step.
    private static let maxDriftIntervalSeconds = 0.1

    /// - Parameters:
    ///   - maxDriftDegreesPerSecond: Knob — the fastest yaw movement the zero
    ///     will swallow as drift. A resting gyro-corrected heading wanders far
    ///     slower than this, and the ceiling is what makes a real turn that was
    ///     wrongly flagged still leak through as a turn instead of vanishing.
    ///   - unlatchAfterSeconds: Knob — how long a turn past the look-away angle
    ///     may be held without any head rotation before it is read as a stale
    ///     zero rather than a glance.
    public init(
        maxDriftDegreesPerSecond: Double = 2,
        unlatchAfterSeconds: Double = 180
    ) {
        self.maxDriftDegreesPerSecond = maxDriftDegreesPerSecond
        self.unlatchAfterSeconds = unlatchAfterSeconds
    }

    /// Turn angle for `yawDegrees`, establishing the zero if the frame is new.
    ///
    /// The zero is fixed, and the two things that move it both move it away from
    /// the head rather than toward it. Yaw that changes while the head is not
    /// rotating cannot be a turn, so it is sensor drift and is absorbed into the
    /// zero, holding the reported turn where it was. And a turn that sits past
    /// the look-away angle while the head never moves is not a glance: a stale
    /// zero is the only thing that reads large with the head straight, so after
    /// `unlatchAfterSeconds` this heading becomes forward.
    ///
    /// - Parameters:
    ///   - elapsedSeconds: Interval since the previous sample, on the sensor's
    ///     own clock. Pass 0 for the first sample after a gap: that interval was
    ///     never observed, so it can neither absorb drift nor age a look-away.
    ///   - isHeadStill: Whether the gyro's rotation rate says the head is not
    ///     turning. A real turn always carries angular velocity, so this is what
    ///     separates drift from movement.
    ///   - lookAwayThresholdDegrees: The gate's turn-away angle. Pass 0 to leave
    ///     a large turn latched indefinitely.
    public mutating func turnDegrees(
        forYaw yawDegrees: Double,
        elapsedSeconds: Double = 0,
        isHeadStill: Bool = false,
        lookAwayThresholdDegrees: Double = 0
    ) -> Double {
        guard var zero = zeroDegrees else {
            rezero(toYaw: yawDegrees)
            return 0
        }

        let previousYaw = lastYawDegrees ?? yawDegrees
        lastYawDegrees = yawDegrees
        let hasInterval = elapsedSeconds.isFinite && elapsedSeconds > 0

        if hasInterval, isHeadStill {
            let drift = PostureGaugeMapping.wrappedDegreesDelta(current: yawDegrees, baseline: previousYaw)
            let limit = maxDriftDegreesPerSecond * min(elapsedSeconds, Self.maxDriftIntervalSeconds)
            let absorbed = max(-limit, min(limit, drift))
            zero = PostureGaugeMapping.wrappedDegreesDelta(current: zero + absorbed, baseline: 0)
            zeroDegrees = zero
        }

        let turn = PostureGaugeMapping.wrappedDegreesDelta(current: yawDegrees, baseline: zero)

        guard lookAwayThresholdDegrees > 0, abs(turn) >= lookAwayThresholdDegrees else {
            heldStillPastThresholdSeconds = 0
            return turn
        }
        // Only motionless time ages a look-away, so walking around with the head
        // turned cannot redefine forward mid-stride.
        guard hasInterval, isHeadStill else { return turn }
        heldStillPastThresholdSeconds += elapsedSeconds
        guard heldStillPastThresholdSeconds >= unlatchAfterSeconds else { return turn }
        rezero(toYaw: yawDegrees)
        return 0
    }

    /// Discards the zero because the sensor's reference frame changed: sleep/wake,
    /// a headphone reconnect, or restarted motion updates. A gap in samples is not
    /// such a change, and must not come through here.
    public mutating func invalidate() {
        zeroDegrees = nil
        lastYawDegrees = nil
        heldStillPastThresholdSeconds = 0
    }

    /// Moves the zero to the current heading because the user asked for it.
    public mutating func rezero(toYaw yawDegrees: Double) {
        zeroDegrees = yawDegrees
        lastYawDegrees = yawDegrees
        heldStillPastThresholdSeconds = 0
    }
}
