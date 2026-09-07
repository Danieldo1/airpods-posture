/// Owns the zero point for head turn.
///
/// Tilt and lean are measured against a baseline the user saved deliberately.
/// Yaw has no such baseline: the headphones choose an arbitrary yaw origin every
/// time they establish a reference frame, so the zero has to be taken from the
/// sensor itself. That makes the zero's lifetime the whole problem, which is why
/// every rule about when it survives and when it must be discarded lives here
/// instead of being spread across the tracking call sites.
public struct YawReference: Equatable, Sendable {
    /// Nil until a sample establishes the zero for the current reference frame.
    public private(set) var zeroDegrees: Double?

    public init() {}

    /// Turn angle for `yawDegrees`, establishing the zero if the frame is new.
    public mutating func turnDegrees(forYaw yawDegrees: Double) -> Double {
        guard let zero = zeroDegrees else {
            zeroDegrees = yawDegrees
            return 0
        }
        return PostureGaugeMapping.wrappedDegreesDelta(current: yawDegrees, baseline: zero)
    }

    /// Discards the zero because the sensor's reference frame changed: sleep/wake,
    /// a headphone reconnect, or restarted motion updates. A gap in samples is not
    /// such a change, and must not come through here.
    public mutating func invalidate() {
        zeroDegrees = nil
    }

    /// Moves the zero to the current heading because the user asked for it.
    public mutating func rezero(toYaw yawDegrees: Double) {
        zeroDegrees = yawDegrees
    }
}
