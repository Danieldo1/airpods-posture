import AppKit
import Combine
import CoreMotion
import Foundation

private var failures = 0
private func check(_ value: Bool, _ name: String) {
    if !value {
        failures += 1
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
    }
}

// This file is compiled beside the tracker in one source unit so fixtures can
// enter the private production motion handler without a test-only public API.
private final class FixtureAttitude: CMAttitude {
    let fixturePitch: Double
    init(pitch: Double) { fixturePitch = pitch; super.init() }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var pitch: Double { fixturePitch }
    override var roll: Double { 0 }
    override var yaw: Double { 0 }
}

private final class FixtureMotion: CMDeviceMotion {
    let fixtureAttitude: CMAttitude
    let fixtureTimestamp: TimeInterval
    init(pitch: Double, timestamp: TimeInterval) {
        fixtureAttitude = FixtureAttitude(pitch: pitch)
        fixtureTimestamp = timestamp
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var attitude: CMAttitude { fixtureAttitude }
    override var timestamp: TimeInterval { fixtureTimestamp }
}

private extension PostureTrackingManager {
    func receiveFixture(_ motion: CMDeviceMotion?) { handleMotion(motion, error: nil) }
}

@MainActor
private func checkRejectedMotionRestartsGrace(root: URL, calendar: Calendar) {
    // Removing either rejection-path reset must fail: analytics must never
    // manufacture an episode while the tracker remains in its previous slouch.
    for (label, rejectedPitch) in [("nil", nil), ("NaN", Double.nan), ("infinite", Double.infinity), ("out-of-range", 4.0)] as [(String, Double?)] {
        let suite = "AirPostureTrackerCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "isTrackingEnabled")
        defaults.set(0.0, forKey: "baselinePitchDegrees")
        defaults.set(0.0, forKey: "baselineRollDegrees")
        defaults.set(5.0, forKey: "gracePeriodSeconds")
        var date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        var uptime = 100.0
        let tracker = PostureTrackingManager(defaults: defaults, now: { date }, monotonic: { uptime }, motionManager: nil)
        let settings = AirPostureSettings(defaults: defaults)
        settings.snooze(minutes: 60)
        tracker.configure(settings: settings)
        AlertService.shared.configure(settings: settings) // No playback or banner while exercising actual scoring.
        let lifecycle = NotificationCenter()
        let store = WeeklyAnalyticsStore(
            observations: tracker.analyticsObservations.eraseToAnyPublisher(),
            fileURL: root.appendingPathComponent("tracker-\(label).json"),
            now: { date }, monotonic: { uptime }, calendar: calendar,
            lifecycleCenter: lifecycle, workspaceCenter: NotificationCenter()
        )
        var states: [AnalyticsState] = []
        let subscription = tracker.analyticsObservations.sink { states.append($0.state) }
        defer { subscription.cancel() }
        func elapse(_ seconds: Double) { date.addTimeInterval(seconds); uptime += seconds }
        func valid() { tracker.receiveFixture(FixtureMotion(pitch: -.pi / 6, timestamp: uptime)) }
        func reject() { tracker.receiveFixture(rejectedPitch.map { FixtureMotion(pitch: $0, timestamp: uptime) }) }
        func bucket() -> DayBucket {
            // The store intentionally refreshes its published summary on flush/tick.
            lifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
            return store.weekSummary.dailyDetails.last!.bucket
        }

        valid()
        check(states.last == .countdown && !tracker.isSlouching, "\(label): real tracker begins grace")
        elapse(5); valid()
        check(tracker.isSlouching && bucket().slouchEpisodes == 1, "\(label): real grace transition records one episode while snoozed")
        elapse(1); reject()
        check(states.last == .inactive, "\(label): rejected motion suspends evidence")
        check(!tracker.isSlouching && !tracker.isPastThreshold && tracker.slouchProgress == 0 && tracker.slouchElapsedSeconds == 0, "\(label): rejected motion clears sustained state and grace")
        check(bucket().monitoredSeconds == 6, "\(label): rejection closes six eligible seconds")
        elapse(20); valid()
        check(states.last == .countdown && !tracker.isSlouching && tracker.slouchElapsedSeconds == 0, "\(label): valid return starts fresh grace")
        check(bucket().slouchEpisodes == 1, "\(label): valid return cannot duplicate the prior sustained episode")
        check(bucket().monitoredSeconds == 6, "\(label): rejected interval is never backfilled")
        elapse(4.5); valid()
        check(!tracker.isSlouching && bucket().slouchEpisodes == 1, "\(label): restarted grace must fully elapse")
        elapse(0.5); valid()
        check(tracker.isSlouching && bucket().slouchEpisodes == 2, "\(label): a new sustained transition creates exactly one new episode")
        check(bucket().countdownSeconds == 10 && bucket().slouchSeconds == 1, "\(label): actual tracker classifications preserve countdown and slouch durations")
        elapse(0.5); valid()
        check(bucket().slouchEpisodes == 2, "\(label): unchanged sustained observation is not another episode")
        elapse(0.5); reject()
        elapse(1); reject()
        check(bucket().slouchEpisodes == 2 && bucket().monitoredSeconds == 12, "\(label): repeated rejection neither creates episodes nor backfills")
        tracker.isTrackingEnabled = false
        elapse(20); valid()
        check(states.last == .inactive && bucket().monitoredSeconds == 12, "\(label): disabled tracker still excludes samples")
    }
}

@main
private struct AnalyticsStoreCheck {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("analytics-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        checkRejectedMotionRestartsGrace(root: root, calendar: calendar)
        var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        var uptime = 100.0
        let lifecycle = NotificationCenter()
        let workspace = NotificationCenter()
        let events = PassthroughSubject<AnalyticsObservation, Never>()
        let blocker = root.appendingPathComponent("blocked")
        try Data("blocker".utf8).write(to: blocker)
        let file = blocker.appendingPathComponent("weekly-analytics.json")
        let store = WeeklyAnalyticsStore(
            observations: events.eraseToAnyPublisher(), fileURL: file,
            now: { now }, monotonic: { uptime }, calendar: calendar,
            lifecycleCenter: lifecycle, workspaceCenter: workspace
        )
        func emit(_ state: AnalyticsState) {
            events.send(AnalyticsObservation(state: state, date: now, monotonic: uptime))
        }
        func elapse(_ seconds: Double) { now.addTimeInterval(seconds); uptime += seconds }
        emit(.upright)
        elapse(2.5)
        emit(.countdown)
        elapse(1.5)
        emit(.slouch)
        elapse(3)
        FileHandle.standardError.write(Data("EXPECTED DIAGNOSTIC: the next analytics save fails against a file used as a directory; the harness verifies recovery.\n".utf8))
        lifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        FileHandle.standardError.write(Data("END EXPECTED DIAGNOSTIC\n".utf8))
        check(store.lastStoreError != nil, "write failure is visible")
        check(store.weekSummary.dailyDetails.last!.bucket.monitoredSeconds == 7, "write failure retains elapsed data in memory")
        try FileManager.default.removeItem(at: blocker)
        lifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        check(store.lastStoreError == nil, "successful retry clears storage error")
        let document = try JSONDecoder().decode(AnalyticsDocument.self, from: Data(contentsOf: file))
        check(document.days["2026-09-06"]?.slouchEpisodes == 1, "consistent sustained event counts once")
        check(document.days["2026-09-06"]?.countdownSeconds == 1.5, "native flush preserves classified fractions")
        check(document.days["2026-09-06"]?.slouchSeconds == 3, "termination closes active interval")
        elapse(1)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        elapse(100)
        emit(.upright) // A queued event during sleep must not restart accumulation.
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        elapse(100)
        lifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        check(store.weekSummary.dailyDetails.last!.bucket.monitoredSeconds == 8, "sleep and stale wake state excluded")
        emit(.upright)
        elapse(2)
        lifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        check(store.weekSummary.dailyDetails.last!.bucket.monitoredSeconds == 10, "fresh unchanged-zone event resumes counting")
        check(store.history(days: 30).count == 30, "native history returns requested actual-data range")

        let futureURL = root.appendingPathComponent("future.json")
        let futureData = Data(#"{"schemaVersion":999,"days":{}}"#.utf8)
        try futureData.write(to: futureURL)
        let futureLifecycle = NotificationCenter()
        let future = WeeklyAnalyticsStore(observations: events.eraseToAnyPublisher(), fileURL: futureURL, now: { now }, monotonic: { uptime }, calendar: calendar, lifecycleCenter: futureLifecycle, workspaceCenter: NotificationCenter())
        futureLifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        check(try Data(contentsOf: futureURL) == futureData, "future schema remains byte-identical after flush")
        check(future.lastStoreError != nil, "future schema exposes actionable error")
        let corruptURL = root.appendingPathComponent("corrupt.json")
        let corruptData = Data(#"{"schemaVersion":2,"days":{"2026-09-06":{"monitoredSeconds":1,"offNeutralSeconds":2,"slouchEpisodes":0}}}"#.utf8)
        try corruptData.write(to: corruptURL)
        let corruptLifecycle = NotificationCenter()
        let corrupt = WeeklyAnalyticsStore(observations: events.eraseToAnyPublisher(), fileURL: corruptURL, now: { now }, monotonic: { uptime }, calendar: calendar, lifecycleCenter: corruptLifecycle, workspaceCenter: NotificationCenter())
        check(corrupt.lastStoreError != nil, "corrupt document error is surfaced")
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".corrupt-") }
        check(backups.count == 1, "corrupt file is quarantined")
        check(try Data(contentsOf: backups[0]) == corruptData, "quarantine preserves original bytes")
        corruptLifecycle.post(name: NSApplication.willTerminateNotification, object: nil)
        check(corrupt.lastStoreError == nil, "valid recovery save clears corrupt-file error")
        check(try JSONDecoder().decode(AnalyticsDocument.self, from: Data(contentsOf: corruptURL)).days.isEmpty, "corrupt durations never imported")
        if failures > 0 { exit(1) }
        print("AirPosture analytics store checks passed")
    }
}
