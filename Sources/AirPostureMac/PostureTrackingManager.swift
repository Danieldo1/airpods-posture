#if SWIFT_PACKAGE
import AirPostureCore
#endif
import AppKit
import Combine
import CoreMotion
import Foundation

enum ConnectionStatus: String, Equatable {
    case connected
    case searching
    case disconnected

    var title: String {
        switch self {
        case .connected: "Connected"
        case .searching: "Searching"
        case .disconnected: "Disconnected"
        }
    }
}

enum PostureBand: Equatable {
    case uncalibrated
    case waitingForHeadphones
    case upright
    case leaning
    case slouching
    case paused
}

enum DominantAxis: Equatable {
    case tilt
    case lean

    var title: String {
        switch self {
        case .tilt: "Tilt"
        case .lean: "Lean"
        }
    }
}

@MainActor
final class PostureTrackingManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected {
        didSet {
            if connectionStatus != .connected {
                motionFreshAfterUptime = monotonic()
                publishAnalytics(state: .inactive)
            }
        }
    }
    let analyticsObservations = PassthroughSubject<AnalyticsObservation, Never>()
    let liveReadings = LivePostureReadings()
    @Published var isTrackingEnabled: Bool {
        didSet {
            defaults.set(isTrackingEnabled, forKey: SettingsKey.isTrackingEnabled)
            if isTrackingEnabled {
                startMotionUpdates()
            } else {
                stopMotionUpdates(resetLiveState: true)
            }
            syncConsolePublications()
        }
    }

    @Published var sensitivityDegrees: Double {
        didSet { defaults.set(sensitivityDegrees, forKey: SettingsKey.sensitivityDegrees) }
    }

    @Published var gracePeriodSeconds: Double {
        didSet { defaults.set(gracePeriodSeconds, forKey: SettingsKey.gracePeriodSeconds) }
    }

    @Published var activePreset: PosturePreset {
        didSet {
            guard oldValue != activePreset else { return }
            defaults.set(activePreset.rawValue, forKey: SettingsKey.activePosturePreset)
            applyActivePresetBaselines(resetSlouch: true)
        }
    }

    private(set) var currentPitchDegrees: Double = 0
    private(set) var currentRollDegrees: Double = 0
    private(set) var currentYawDegrees: Double = 0
    @Published private(set) var baselinePitchDegrees: Double?
    @Published private(set) var baselineRollDegrees: Double?
    private(set) var pitchDeltaDegrees: Double = 0
    private(set) var rollDeltaDegrees: Double = 0
    private(set) var yawDeltaDegrees: Double = 0
    private(set) var deviationDegrees: Double = 0
    private(set) var dominantAxis: DominantAxis = .tilt
    private(set) var isPastThreshold = false
    private(set) var isLookingAway = false
    private(set) var isSlouching = false
    private(set) var slouchElapsedSeconds: Double = 0
    private(set) var slouchProgress: Double = 0
    @Published private(set) var postureBand: PostureBand = .waitingForHeadphones
    @Published private(set) var didJustCalibrate = false
    @Published private(set) var authorizationDenied = false
    @Published private(set) var lastErrorMessage: String?

    private weak var settings: AirPostureSettings?

    var isCalibrated: Bool {
        baselinePitchDegrees != nil && baselineRollDegrees != nil
    }

    var hasAnyCalibration: Bool {
        deskPitchDegrees != nil || sofaPitchDegrees != nil
    }

    var isAnalyticsEligible: Bool {
        isTrackingEnabled && connectionStatus == .connected && isCalibrated
    }

    var tiltThresholdDegrees: Double {
        sensitivityDegrees
    }

    var leanThresholdDegrees: Double {
        max(Motion.minLeanThreshold, sensitivityDegrees * Motion.leanToTiltRatio)
    }

    var normalizedDeviation: Double {
        let threshold = tiltThresholdDegrees
        guard deviationDegrees.isFinite, threshold.isFinite, threshold > 0 else { return 0 }
        return max(deviationDegrees / threshold, 0)
    }

    private func resolvedPostureBand() -> PostureBand {
        if !isTrackingEnabled { return .paused }
        if connectionStatus != .connected { return .waitingForHeadphones }
        if !isCalibrated { return .uncalibrated }
        if isSlouching { return .slouching }
        if isPastThreshold { return .leaning }
        return .upright
    }

    private func syncConsolePublications() {
        let nextBand = resolvedPostureBand()
        if postureBand != nextBand {
            postureBand = nextBand
        }
        let gaugeCalibrated = isCalibrated && connectionStatus == .connected
        liveReadings.replace(
            LivePostureSnapshot(
                pitchDeltaDegrees: pitchDeltaDegrees,
                rollDeltaDegrees: rollDeltaDegrees,
                yawDeltaDegrees: yawDeltaDegrees,
                dominantAxis: dominantAxis,
                band: nextBand,
                slouchProgress: slouchProgressClamped,
                isCalibrated: gaugeCalibrated,
                caption: coachingCaption,
                isLookingAway: isLookingAway
            )
        )
    }

    var coachingCaption: String {
        switch postureBand {
        case .uncalibrated:
            "Set a neutral posture to begin"
        case .waitingForHeadphones:
            "Waiting for AirPods"
        case .paused:
            "Tracking paused"
        case .upright:
            isLookingAway ? "Looking aside" : "Upright"
        case .leaning:
            dominantAxis == .tilt ? "Tilting forward" : "Leaning aside"
        case .slouching:
            dominantAxis == .tilt ? "Lift your chin" : "Recenter"
        }
    }

    var canCalibrate: Bool {
        isTrackingEnabled && connectionStatus == .connected
    }

    var slouchProgressClamped: Double {
        min(max(slouchProgress, 0), 1)
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let monotonic: () -> TimeInterval
    private let motionManager: CMHeadphoneMotionManager?
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.macposture.airposture.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private var smoothedPitchDegrees: Double?
    private var smoothedRollDegrees: Double?
    private var smoothedYawDegrees: Double?
    private var sessionYawDegrees: Double?
    private var slouchStartedAt: Date?
    private var hasReceivedMotionSample = false
    private var isSystemSleeping = false
    private var motionFreshAfterUptime: TimeInterval = 0
    private var needsMotionSettle = true
    private var motionSettleUntilUptime: TimeInterval = 0
    private var sleepObservers: [NSObjectProtocol] = []
    private var lastSuccessfulMotionTime: Date?
    private var healthCheckTimer: Timer?
    private var calibrateResetTask: Task<Void, Never>?
    private var deskPitchDegrees: Double? = nil
    private var deskRollDegrees: Double? = nil
    private var sofaPitchDegrees: Double? = nil
    private var sofaRollDegrees: Double? = nil

    private enum SettingsKey {
        static let isTrackingEnabled = "isTrackingEnabled"
        static let sensitivityDegrees = "sensitivityDegrees"
        static let gracePeriodSeconds = "gracePeriodSeconds"
        static let baselinePitchDegrees = "baselinePitchDegrees"
        static let baselineRollDegrees = "baselineRollDegrees"
        static let sofaBaselinePitchDegrees = "sofaBaselinePitchDegrees"
        static let sofaBaselineRollDegrees = "sofaBaselineRollDegrees"
        static let activePosturePreset = "activePosturePreset"
    }

    private enum Motion {
        static let smoothingAlpha = 0.4
        static let defaultSensitivity = 10.0
        static let defaultGracePeriod = 5.0
        static let minSensitivity = 5.0
        static let maxSensitivity = 30.0
        static let minGracePeriod = 1.0
        static let maxGracePeriod = 15.0
        static let leanToTiltRatio = 0.5
        static let minLeanThreshold = 4.0
        static let healthCheckInterval: TimeInterval = 2
        static let reconnectSilence: TimeInterval = 5
        static let disconnectSilence: TimeInterval = 10
        static let connectSettleSeconds: TimeInterval = 0.45
    }

    override convenience init() {
        self.init(
            defaults: .standard,
            now: Date.init,
            monotonic: { ProcessInfo.processInfo.systemUptime },
            motionManager: CMHeadphoneMotionManager()
        )
    }

    init(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        monotonic: @escaping () -> TimeInterval,
        motionManager: CMHeadphoneMotionManager?
    ) {
        self.defaults = defaults
        self.now = now
        self.monotonic = monotonic
        self.motionManager = motionManager
        defaults.register(defaults: [
            SettingsKey.isTrackingEnabled: true,
            SettingsKey.sensitivityDegrees: Motion.defaultSensitivity,
            SettingsKey.gracePeriodSeconds: Motion.defaultGracePeriod
        ])

        isTrackingEnabled = defaults.object(forKey: SettingsKey.isTrackingEnabled) as? Bool ?? true
        sensitivityDegrees = Self.clamped(
            defaults.double(forKey: SettingsKey.sensitivityDegrees),
            min: Motion.minSensitivity,
            max: Motion.maxSensitivity,
            fallback: Motion.defaultSensitivity
        )
        gracePeriodSeconds = Self.clamped(
            defaults.double(forKey: SettingsKey.gracePeriodSeconds),
            min: Motion.minGracePeriod,
            max: Motion.maxGracePeriod,
            fallback: Motion.defaultGracePeriod
        )

        if defaults.object(forKey: SettingsKey.baselinePitchDegrees) != nil {
            deskPitchDegrees = defaults.double(forKey: SettingsKey.baselinePitchDegrees)
        }
        if defaults.object(forKey: SettingsKey.baselineRollDegrees) != nil {
            deskRollDegrees = defaults.double(forKey: SettingsKey.baselineRollDegrees)
        }
        if defaults.object(forKey: SettingsKey.sofaBaselinePitchDegrees) != nil {
            sofaPitchDegrees = defaults.double(forKey: SettingsKey.sofaBaselinePitchDegrees)
        }
        if defaults.object(forKey: SettingsKey.sofaBaselineRollDegrees) != nil {
            sofaRollDegrees = defaults.double(forKey: SettingsKey.sofaBaselineRollDegrees)
        }
        let preset = PosturePreset(rawValue: defaults.string(forKey: SettingsKey.activePosturePreset) ?? "") ?? .desk
        activePreset = preset
        baselinePitchDegrees = preset == .desk ? deskPitchDegrees : sofaPitchDegrees
        baselineRollDegrees = preset == .desk ? deskRollDegrees : sofaRollDegrees

        super.init()
        defer { syncConsolePublications() }
        guard let motionManager else { return }
        configureSleepObservers()
        motionManager.delegate = self
        refreshAuthorizationStatus()
        motionManager.startConnectionStatusUpdates()

        if isTrackingEnabled {
            startMotionUpdates()
        } else {
            setConnectionStatus(motionManager.isDeviceMotionAvailable ? .searching : .disconnected)
        }
    }

    deinit {
        for token in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    private func configureSleepObservers() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isSystemSleeping = notification.name == NSWorkspace.willSleepNotification
                    self.motionFreshAfterUptime = self.monotonic()
                    self.hasReceivedMotionSample = false
                    self.lastSuccessfulMotionTime = nil
                    self.armMotionSettle()
                    self.setConnectionStatus(self.isTrackingEnabled ? .searching : .disconnected)
                    self.resetSlouchState()
                    self.publishAnalytics(state: .inactive)
                    self.syncConsolePublications()
                }
            }
            sleepObservers.append(token)
        }
    }

    private func publishAnalytics(state: AnalyticsState) {
        analyticsObservations.send(AnalyticsObservation(state: state, date: now(), monotonic: monotonic()))
    }

    private func publishScoringObservation() {
        let state: AnalyticsState = !isAnalyticsEligible ? .inactive : isSlouching ? .slouch : isPastThreshold ? .countdown : .upright
        publishAnalytics(state: state)
    }

    func configure(settings: AirPostureSettings) {
        self.settings = settings
    }

    func calibrate() {
        guard canCalibrate else { return }
        defer { syncConsolePublications() }
        persistBaseline(pitch: currentPitchDegrees, roll: currentRollDegrees)
        resetLiveDeviation()
        rezeroSessionYaw()
        resetSlouchState()
        motionFreshAfterUptime = monotonic()
        publishAnalytics(state: .inactive)
        didJustCalibrate = true

        calibrateResetTask?.cancel()
        calibrateResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.didJustCalibrate = false
        }
    }

    func refreshAuthorizationStatus() {
        setAuthorizationDenied(CMHeadphoneMotionManager.authorizationStatus() == .denied)
    }

    private func setConnectionStatus(_ status: ConnectionStatus) {
        if connectionStatus != status { connectionStatus = status }
    }

    private func setLastErrorMessage(_ message: String?) {
        if lastErrorMessage != message { lastErrorMessage = message }
    }

    private func setAuthorizationDenied(_ denied: Bool) {
        if authorizationDenied != denied { authorizationDenied = denied }
    }

    private func startMotionUpdates() {
        defer { syncConsolePublications() }
        guard let motionManager else { return }
        refreshAuthorizationStatus()
        setLastErrorMessage(nil)
        startHealthCheck()

        guard motionManager.isDeviceMotionAvailable else {
            setConnectionStatus(.disconnected)
            setLastErrorMessage("Headphone motion is not available on this Mac.")
            return
        }

        if authorizationDenied {
            setConnectionStatus(.disconnected)
            return
        }

        if !hasReceivedMotionSample {
            setConnectionStatus(.searching)
        }

        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            Task { @MainActor in
                self?.handleMotion(motion, error: error)
            }
        }
    }

    private func stopMotionUpdates(resetLiveState: Bool) {
        defer { syncConsolePublications() }
        publishAnalytics(state: .inactive)
        motionManager?.stopDeviceMotionUpdates()
        stopHealthCheck()
        hasReceivedMotionSample = false
        lastSuccessfulMotionTime = nil
        clearSessionYaw()
        if resetLiveState {
            resetSlouchState()
            setConnectionStatus(.disconnected)
        }
    }

    private func handleMotion(_ motion: CMDeviceMotion?, error: Error?) {
        defer { syncConsolePublications() }
        guard isTrackingEnabled, !isSystemSleeping else { return }
        if let error {
            setLastErrorMessage(error.localizedDescription)
            hasReceivedMotionSample = false
            setConnectionStatus(.searching)
            clearSessionYaw()
            resetSlouchState()
            return
        }

        guard let motion else {
            // Suspended evidence also ends sustained scoring; fresh motion
            // must complete grace before analytics can record a new episode.
            resetSlouchState()
            publishAnalytics(state: .inactive)
            return
        }
        guard motion.timestamp > motionFreshAfterUptime else { return }

        let pitch = motion.attitude.pitch
        let roll = motion.attitude.roll
        let yaw = motion.attitude.yaw
        guard Self.isValidAttitude(pitch: pitch, roll: roll, yaw: yaw) else {
            resetSlouchState()
            publishAnalytics(state: .inactive)
            return
        }
        if motionManager != nil, discardUnsettledMotion() {
            return
        }
        // Observers see a complete result, including unchanged zones after wake/reconnect.
        defer { publishScoringObservation() }

        setLastErrorMessage(nil)
        setAuthorizationDenied(false)
        hasReceivedMotionSample = true
        lastSuccessfulMotionTime = now()
        setConnectionStatus(.connected)

        let rawPitch = pitch * 180.0 / .pi
        let rawRoll = roll * 180.0 / .pi
        let rawYaw = yaw * 180.0 / .pi
        currentPitchDegrees = smooth(rawPitch, previous: &smoothedPitchDegrees)
        currentRollDegrees = smooth(rawRoll, previous: &smoothedRollDegrees)
        currentYawDegrees = smooth(rawYaw, previous: &smoothedYawDegrees)

        if sessionYawDegrees == nil {
            sessionYawDegrees = currentYawDegrees
        }

        migrateLegacyPitchOnlyBaselineIfNeeded()

        let yawDelta = PostureGaugeMapping.wrappedDegreesDelta(
            current: currentYawDegrees,
            baseline: sessionYawDegrees ?? currentYawDegrees
        )
        yawDeltaDegrees = yawDelta

        guard let baselinePitch = baselinePitchDegrees, let baselineRoll = baselineRollDegrees else {
            pitchDeltaDegrees = 0
            rollDeltaDegrees = 0
            deviationDegrees = 0
            dominantAxis = .tilt
            isLookingAway = false
            resetSlouchState()
            return
        }

        // Tilt = pitch vs baseline. Forward-head / chin-down is a negative shift.
        // Lean = roll vs baseline. Either side is a lateral off-center.
        let tiltDelta = currentPitchDegrees - baselinePitch
        let leanDelta = currentRollDegrees - baselineRoll
        pitchDeltaDegrees = tiltDelta
        rollDeltaDegrees = leanDelta

        let downwardTilt = max(-tiltDelta, 0)
        let lateralLean = abs(leanDelta)
        dominantAxis = lateralLean > downwardTilt ? .lean : .tilt

        let tiltNorm = downwardTilt / max(tiltThresholdDegrees, 0.001)
        let leanNorm = lateralLean / max(leanThresholdDegrees, 0.001)
        let combined = hypot(tiltNorm, leanNorm)
        deviationDegrees = combined * tiltThresholdDegrees

        let gateEnabled = settings?.lookAwayGateEnabled ?? true
        let gateThreshold = settings?.lookAwayThresholdDegrees ?? 35
        let gated = PostureGaugeMapping.isLookingAway(
            yawDelta: yawDelta,
            threshold: gateThreshold,
            enabled: gateEnabled
        )
        isLookingAway = gated

        let ellipsePast = combined >= 1
        evaluatePosture(isPastThreshold: ellipsePast && !gated)
    }

    private func evaluatePosture(isPastThreshold pastThreshold: Bool) {
        isPastThreshold = pastThreshold

        guard pastThreshold else {
            let recoveredFromSlouch = isSlouching
            resetSlouchState()
            if recoveredFromSlouch {
                AlertService.shared.playSitUpChimeIfAllowed()
            }
            return
        }

        let startedAt = slouchStartedAt ?? now()
        if slouchStartedAt == nil {
            slouchStartedAt = startedAt
        }

        let elapsed = now().timeIntervalSince(startedAt)
        slouchElapsedSeconds = elapsed
        slouchProgress = gracePeriodSeconds > 0 ? elapsed / gracePeriodSeconds : 1

        let sustained = elapsed >= gracePeriodSeconds
        isSlouching = sustained

        if sustained {
            AlertService.shared.nudgeIfAllowed(
                slouchElapsedSeconds: elapsed,
                gracePeriodSeconds: gracePeriodSeconds
            )
        }
    }

    private func resetSlouchState() {
        slouchStartedAt = nil
        slouchElapsedSeconds = 0
        slouchProgress = 0
        isPastThreshold = false
        isSlouching = false
    }

    private func rezeroSessionYaw() {
        sessionYawDegrees = currentYawDegrees
        yawDeltaDegrees = 0
        isLookingAway = false
    }

    private func clearSessionYaw() {
        sessionYawDegrees = nil
        smoothedYawDegrees = nil
        yawDeltaDegrees = 0
        isLookingAway = false
        armMotionSettle()
    }

    private func armMotionSettle() {
        // Headphone Euler angles jump after connect, sleep, or disconnect.
        // Drop that window so a saved Neutral is not scored as a huge lean.
        needsMotionSettle = true
        motionSettleUntilUptime = 0
        smoothedPitchDegrees = nil
        smoothedRollDegrees = nil
    }

    private func discardUnsettledMotion() -> Bool {
        if needsMotionSettle {
            needsMotionSettle = false
            motionSettleUntilUptime = monotonic() + Motion.connectSettleSeconds
            return true
        }
        if monotonic() < motionSettleUntilUptime {
            return true
        }
        return false
    }

    private func persistBaseline(pitch: Double, roll: Double) {
        baselinePitchDegrees = pitch
        baselineRollDegrees = roll
        switch activePreset {
        case .desk:
            deskPitchDegrees = pitch
            deskRollDegrees = roll
            defaults.set(pitch, forKey: SettingsKey.baselinePitchDegrees)
            defaults.set(roll, forKey: SettingsKey.baselineRollDegrees)
        case .sofa:
            sofaPitchDegrees = pitch
            sofaRollDegrees = roll
            defaults.set(pitch, forKey: SettingsKey.sofaBaselinePitchDegrees)
            defaults.set(roll, forKey: SettingsKey.sofaBaselineRollDegrees)
        }
    }

    private func applyActivePresetBaselines(resetSlouch: Bool) {
        defer { syncConsolePublications() }
        switch activePreset {
        case .desk:
            baselinePitchDegrees = deskPitchDegrees
            baselineRollDegrees = deskRollDegrees
        case .sofa:
            baselinePitchDegrees = sofaPitchDegrees
            baselineRollDegrees = sofaRollDegrees
        }
        resetLiveDeviation()
        if resetSlouch {
            resetSlouchState()
        }
        motionFreshAfterUptime = monotonic()
        publishAnalytics(state: .inactive)
    }

    private func resetLiveDeviation() {
        pitchDeltaDegrees = 0
        rollDeltaDegrees = 0
        deviationDegrees = 0
        dominantAxis = .tilt
        isLookingAway = false
    }

    private func migrateLegacyPitchOnlyBaselineIfNeeded() {
        guard baselinePitchDegrees != nil, baselineRollDegrees == nil else { return }
        persistBaseline(pitch: baselinePitchDegrees ?? currentPitchDegrees, roll: currentRollDegrees)
    }

    private func handleHeadphonesConnected() {
        defer { syncConsolePublications() }
        if isTrackingEnabled && !hasReceivedMotionSample {
            setConnectionStatus(.searching)
            clearSessionYaw()
            startMotionUpdates()
        }
    }

    private func handleHeadphonesDisconnected() {
        defer { syncConsolePublications() }
        hasReceivedMotionSample = false
        lastSuccessfulMotionTime = nil
        setConnectionStatus(.disconnected)
        clearSessionYaw()
        resetSlouchState()
    }

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: Motion.healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealthCheck()
            }
        }
    }

    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func performHealthCheck() {
        defer { syncConsolePublications() }
        guard isTrackingEnabled, let lastSuccessfulMotionTime else { return }
        let silence = now().timeIntervalSince(lastSuccessfulMotionTime)

        if silence >= Motion.disconnectSilence {
            hasReceivedMotionSample = false
            setConnectionStatus(.disconnected)
            clearSessionYaw()
            resetSlouchState()
        } else if silence >= Motion.reconnectSilence {
            hasReceivedMotionSample = false
            setConnectionStatus(.searching)
            clearSessionYaw()
            resetSlouchState()
        }
    }

    private func smooth(_ sample: Double, previous: inout Double?) -> Double {
        guard let last = previous else {
            previous = sample
            return sample
        }
        let next = Motion.smoothingAlpha * sample + (1 - Motion.smoothingAlpha) * last
        previous = next
        return next
    }

    private static func isValidAttitude(pitch: Double, roll: Double, yaw: Double) -> Bool {
        let axes = [pitch, roll, yaw]
        guard axes.allSatisfy({ $0.isFinite }) else { return false }
        let validRange = (-Double.pi)...Double.pi
        return axes.allSatisfy { validRange.contains($0) }
    }

    private static func clamped(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        if value == 0 { return fallback }
        return Swift.min(Swift.max(value, min), max)
    }
}

extension PostureTrackingManager: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.handleHeadphonesConnected()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.handleHeadphonesDisconnected()
        }
    }
}
