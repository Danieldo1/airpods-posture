#if SWIFT_PACKAGE
import AirPostureCore
#endif
import Combine
import Foundation

struct LivePostureSnapshot: Equatable {
    var pitchDeltaDegrees: Double = 0
    var rollDeltaDegrees: Double = 0
    var yawDeltaDegrees: Double = 0
    var dominantAxis: DominantAxis = .tilt
    var band: PostureBand = .waitingForHeadphones
    var slouchProgress: Double = 0
    var isCalibrated: Bool = false
    var caption: String = "Waiting for AirPods"
    var isLookingAway: Bool = false
}

@MainActor
final class LivePostureReadings: ObservableObject {
    @Published private(set) var snapshot = LivePostureSnapshot()

    func replace(_ snapshot: LivePostureSnapshot) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
    }
}
