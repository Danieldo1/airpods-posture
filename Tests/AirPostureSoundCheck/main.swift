import AppKit
import ObjectiveC.runtime
import AVFoundation
import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() {
        failures += 1
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
    }
}

private enum FixtureError: Error {
    case load
}

@MainActor
private final class FakePrimaryPlayer: PrimarySoundPlaying {
    var volume: Float = 0
    var onFinished: ((Bool) -> Void)?
    var onDecodeError: ((Error?) -> Void)?
    let prepared: Bool
    let started: Bool
    var playCalls = 0
    var stopCalls = 0
    var onStop: (() -> Void)?

    init(prepared: Bool, started: Bool, onStop: (() -> Void)? = nil) {
        self.prepared = prepared
        self.started = started
        self.onStop = onStop
    }

    func prepareToPlay() -> Bool { prepared }
    func play() -> Bool {
        playCalls += 1
        return started
    }
    func stop() {
        stopCalls += 1
        onStop?()
    }
    func finish(successfully: Bool) { onFinished?(successfully) }
    func failDecode() { onDecodeError?(FixtureError.load) }
}

@MainActor
private final class FakeFallbackPlayer: FallbackSoundPlaying {
    var volume: Float = 0
    var onFinished: ((Bool) -> Void)?
    let started: Bool
    var stopCalls = 0

    init(started: Bool) {
        self.started = started
    }

    func play() -> Bool { started }
    func stop() { stopCalls += 1 }
    func finish(successfully: Bool) { onFinished?(successfully) }
}

@MainActor
private final class PlaybackSpy: SoundPlaybackServing {
    struct Request: Equatable {
        let pack: SoundPack
        let volume: Double
        let channel: SoundPlaybackChannel
    }

    var requests: [Request] = []
    var handlers: [(SoundPlaybackEvent) -> Void] = []

    func play(
        pack: SoundPack,
        volume: Double,
        channel: SoundPlaybackChannel,
        onEvent: @escaping (SoundPlaybackEvent) -> Void
    ) {
        requests.append(Request(pack: pack, volume: volume, channel: channel))
        handlers.append(onEvent)
    }
}

private func isolatedDefaults() -> (UserDefaults, String) {
    let name = "AirPostureSoundCheck.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

@MainActor
private func checkRealSelectedAssetsLoad() throws {
    let expected = ["Pop.aiff", "Tink.aiff", "Purr.aiff", "Bottle.aiff", "Morse.aiff"]
    for (pack, filename) in zip(SoundPack.allCases, expected) {
        check(pack.systemSoundURL.lastPathComponent == filename, "\(pack.title) selects its own system file")
        let player = try AVAudioPlayer(contentsOf: pack.systemSoundURL)
        check(player.duration > 0, "\(pack.title) selected asset decodes through AVAudioPlayer")
    }
}

@MainActor
private func checkFalsePreparationFallsBackToSameSound() {
    let primary = FakePrimaryPlayer(prepared: false, started: true)
    let fallback = FakeFallbackPlayer(started: true)
    var selectedURL: URL?
    var fallbackName: String?
    var events: [SoundPlaybackEvent] = []
    let playback = SoundPlayback(
        primaryFactory: { url in selectedURL = url; return primary },
        fallbackFactory: { name in fallbackName = name; return fallback }
    )

    playback.play(pack: .morse, volume: 2, channel: .preview) { events.append($0) }

    check(selectedURL == SoundPack.morse.systemSoundURL, "false preparation still loads selected Morse asset")
    check(fallbackName == "Morse", "false preparation falls back to selected Morse name")
    check(primary.playCalls == 0, "failed preparation does not call primary play")
    check(primary.volume == 1 && fallback.volume == 1, "playback volume clamps at audio boundary")
    check(events.contains(.primaryPrepared(false)), "false preparation is reported")
    check(events.contains(.fallbackStarted(true)), "fallback success is reported")
}

@MainActor
private func checkFalsePlayReportsFailureWhenFallbackFails() {
    let primary = FakePrimaryPlayer(prepared: true, started: false)
    let fallback = FakeFallbackPlayer(started: false)
    var events: [SoundPlaybackEvent] = []
    let playback = SoundPlayback(
        primaryFactory: { _ in primary },
        fallbackFactory: { _ in fallback }
    )

    playback.play(pack: .bottle, volume: 0.45, channel: .warning) { events.append($0) }

    check(events.contains(.primaryStarted(false)), "false primary play return is reported")
    check(events.contains(.fallbackStarted(false)), "false fallback play return is reported")
    check(events.contains { if case .failed = $0 { true } else { false } }, "both false returns produce a terminal failure")
}

@MainActor
private func checkThrowAndAsynchronousFailureFallback() {
    let throwFallback = FakeFallbackPlayer(started: true)
    var throwName: String?
    var throwEvents: [SoundPlaybackEvent] = []
    let throwingPlayback = SoundPlayback(
        primaryFactory: { _ in throw FixtureError.load },
        fallbackFactory: { name in throwName = name; return throwFallback }
    )
    throwingPlayback.play(pack: .purr, volume: 0.45, channel: .preview) { throwEvents.append($0) }
    check(throwName == "Purr", "thrown primary load uses same selected fallback")
    check(throwEvents.contains(.fallbackStarted(true)), "thrown primary load recovers through fallback")

    weak var retainedPrimary: FakePrimaryPlayer?
    weak var retainedFallback: FakeFallbackPlayer?
    var asyncEvents: [SoundPlaybackEvent] = []
    let asyncPlayback = SoundPlayback(
        primaryFactory: { _ in
            let player = FakePrimaryPlayer(prepared: true, started: true)
            retainedPrimary = player
            return player
        },
        fallbackFactory: { _ in
            let player = FakeFallbackPlayer(started: true)
            retainedFallback = player
            return player
        }
    )
    asyncPlayback.play(pack: .tink, volume: 0.45, channel: .preview) { asyncEvents.append($0) }
    check(retainedPrimary != nil, "primary player is retained after start")
    retainedPrimary?.failDecode()
    check(retainedFallback != nil, "asynchronous decode failure retains selected fallback")
    check(asyncEvents.contains(.fallbackStarted(true)), "asynchronous decode failure starts fallback")
    retainedFallback?.finish(successfully: true)
    check(retainedFallback == nil, "fallback is released after completion")

    weak var unsuccessfulPrimary: FakePrimaryPlayer?
    weak var unsuccessfulFallback: FakeFallbackPlayer?
    var unsuccessfulEvents: [SoundPlaybackEvent] = []
    let unsuccessfulPlayback = SoundPlayback(
        primaryFactory: { _ in
            let player = FakePrimaryPlayer(prepared: true, started: true)
            unsuccessfulPrimary = player
            return player
        },
        fallbackFactory: { _ in
            let player = FakeFallbackPlayer(started: true)
            unsuccessfulFallback = player
            return player
        }
    )
    unsuccessfulPlayback.play(pack: .pop, volume: 0.45, channel: .warning) { unsuccessfulEvents.append($0) }
    unsuccessfulPrimary?.finish(successfully: false)
    check(unsuccessfulFallback != nil, "unsuccessful primary completion starts fallback")
    unsuccessfulFallback?.finish(successfully: false)
    check(unsuccessfulEvents.contains { if case .failed = $0 { true } else { false } }, "unsuccessful fallback completion produces terminal failure")
}

@MainActor
private func checkSecondPreviewReplacesFirst() {
    var stopCount = 0
    let playback = SoundPlayback(
        primaryFactory: { _ in FakePrimaryPlayer(prepared: true, started: true, onStop: { stopCount += 1 }) },
        fallbackFactory: { _ in nil }
    )
    playback.play(pack: .pop, volume: 0.3, channel: .preview) { _ in }
    playback.play(pack: .morse, volume: 0.3, channel: .preview) { _ in }
    check(stopCount == 1, "second preview stops the first preview")
}

@MainActor
private func checkPreviewErrorRecoveryAndWarningPolicy() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AirPostureSettings(defaults: defaults)
    settings.soundPack = .morse
    settings.soundVolume = 0.62
    let playback = PlaybackSpy()
    var now = Date()
    var skipBanner = false
    var bannerCount = 0
    let service = AlertService(
        playback: playback,
        now: { now },
        shouldSkipBanner: { skipBanner },
        postNotification: { _ in bannerCount += 1 }
    )
    service.configure(settings: settings)

    settings.snooze(minutes: 5)
    service.previewSound(pack: .bottle, volume: 0.31)
    check(playback.requests == [.init(pack: .bottle, volume: 0.31, channel: .preview)], "preview bypasses snooze and uses selected pack and volume")
    check(bannerCount == 0, "preview never posts a banner")
    service.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
    check(playback.requests.count == 1 && bannerCount == 0, "snooze still suppresses real warning and banner")

    playback.handlers[0](.failed("fixture"))
    check(service.lastPlaybackError == "Couldn’t play Bottle.", "playback failure exposes selected pack inline")
    service.previewSound(pack: .purr, volume: 0.4)
    playback.handlers[1](.primaryStarted(true))
    check(service.lastPlaybackError == nil, "successful playback clears prior inline error")

    settings.clearSnooze()
    service.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
    check(playback.requests.last == .init(pack: .morse, volume: 0.62, channel: .warning), "real warning uses persisted selected pack and volume")
    check(bannerCount == 1, "eligible real warning posts banner")
    service.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
    check(playback.requests.count == 3 && bannerCount == 1, "warning cooldown remains 45 seconds")

    now.addTimeInterval(46)
    settings.soundAfterDoubleGrace = true
    service.nudgeIfAllowed(slouchElapsedSeconds: 9, gracePeriodSeconds: 5)
    check(playback.requests.count == 3, "double-grace policy delays real warning")
    skipBanner = true
    service.nudgeIfAllowed(slouchElapsedSeconds: 10, gracePeriodSeconds: 5)
    check(playback.requests.count == 4, "double-grace boundary plays warning")
    check(bannerCount == 1, "Focus policy still suppresses banner only")

    now.addTimeInterval(46)
    settings.soundPack = .tink
    settings.sitUpChimeEnabled = true
    service.playSitUpChimeIfAllowed()
    check(playback.requests.last == .init(pack: .pop, volume: 0.248, channel: .chime), "recovery chime remains softer and uses alternate sound")
}

// Replace only the audio-output boundary. Named lookup, NSCopying, native
// volume, delegate assignment, and production session ownership stay real.
// Like NSSound, an object already playing cannot start an independent clip.
@MainActor
private func checkNativeSamePackFallbackOwnership() async {
    let playMethod = class_getInstanceMethod(NSSound.self, NSSelectorFromString("play"))!
    let stopMethod = class_getInstanceMethod(NSSound.self, NSSelectorFromString("stop"))!
    var playing: Set<ObjectIdentifier> = []
    var attempted: [NSSound] = []
    var stopped: [NSSound] = []
    let silentPlay: @convention(block) (NSSound) -> Bool = { sound in
        attempted.append(sound)
        return playing.insert(ObjectIdentifier(sound)).inserted
    }
    let silentStop: @convention(block) (NSSound) -> Bool = { sound in
        stopped.append(sound)
        return playing.remove(ObjectIdentifier(sound)) != nil
    }
    let playIMP = imp_implementationWithBlock(silentPlay)
    let stopIMP = imp_implementationWithBlock(silentStop)
    let originalPlay = method_setImplementation(playMethod, playIMP)
    let originalStop = method_setImplementation(stopMethod, stopIMP)
    defer {
        method_setImplementation(playMethod, originalPlay)
        method_setImplementation(stopMethod, originalStop)
        imp_removeBlock(playIMP)
        imp_removeBlock(stopIMP)
    }

    let cached = NSSound(named: "Morse")!
    check(cached === NSSound(named: "Morse"), "native fixture exercises cached selected-name lookup")
    let playback = SoundPlayback(
        primaryFactory: { _ in throw FixtureError.load },
        fallbackFactory: { NSSoundBackend(name: $0) }
    )
    var warningEvents: [SoundPlaybackEvent] = []
    var previewEvents: [SoundPlaybackEvent] = []
    playback.play(pack: .morse, volume: 0.7, channel: .warning) { warningEvents.append($0) }
    playback.play(pack: .morse, volume: 0.2, channel: .preview) { previewEvents.append($0) }
    let warning = attempted[0]
    let preview = attempted[1]
    check(cached.duration > 0 && warning.duration == cached.duration && preview.duration == cached.duration, "both native fallbacks preserve the selected Morse clip duration")
    check(warning !== preview && warning !== cached && preview !== cached, "same-pack fallback sessions own independent native selected sounds")
    check(abs(warning.volume - 0.7) < 0.001 && abs(preview.volume - 0.2) < 0.001, "preview preserves warning native volume")
    check(warning.delegate !== preview.delegate, "same-pack fallback completion delegates stay independent")
    check(warningEvents.contains(.fallbackStarted(true)) && previewEvents.contains(.fallbackStarted(true)), "same-pack fallback channels both start independently")

    playback.play(pack: .morse, volume: 0.4, channel: .preview) { previewEvents.append($0) }
    check(stopped.count == 1 && stopped.first === preview, "replacing preview stops only its native sound")
    check(playing.contains(ObjectIdentifier(warning)), "replacing preview preserves warning playback ownership")
    // Simulate native completion on each owned receiver; no audio is played.
    warning.delegate?.sound?(warning, didFinishPlaying: true)
    let warningDeadline = ContinuousClock.now + .seconds(1)
    while !warningEvents.contains(.finished(true)) && ContinuousClock.now < warningDeadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
    check(warningEvents.filter { $0 == .finished(true) }.count == 1, "warning completion reaches its own active session once")
    check(!previewEvents.contains(.finished(true)), "warning completion does not finish replacement preview")
    let replacement = attempted[2]
    replacement.delegate?.sound?(replacement, didFinishPlaying: true)
    let previewDeadline = ContinuousClock.now + .seconds(1)
    while !previewEvents.contains(.finished(true)) && ContinuousClock.now < previewDeadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
    check(previewEvents.filter { $0 == .finished(true) }.count == 1, "replacement preview completes independently")
}

@MainActor
private func checkBreakReminderPolicy() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AirPostureSettings(defaults: defaults)
    settings.soundPack = .bottle
    settings.soundVolume = 0.4
    let playback = PlaybackSpy()
    var skipBanner = false
    var identifiers: [String] = []
    let service = AlertService(
        playback: playback,
        now: Date.init,
        shouldSkipBanner: { skipBanner },
        postNotification: { identifiers.append($0) }
    )
    service.configure(settings: settings)

    let banner = BreakBanner(title: "Drink some water", body: "Take a sip and look away from the screen for a moment.")

    settings.snooze(minutes: 5)
    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.isEmpty && identifiers.isEmpty, "snooze suppresses break sound and banner")

    settings.clearSnooze()
    skipBanner = true
    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.isEmpty && identifiers.isEmpty, "Focus suppresses break sound and banner")

    skipBanner = false
    service.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
    check(identifiers == ["airposture.slouch"], "slouch still uses slouch identifier")
    let slouchRequests = playback.requests.count

    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.last == .init(pack: .bottle, volume: 0.4, channel: .warning), "break uses selected warning sound")
    check(identifiers == ["airposture.slouch", "airposture.break"], "break uses break identifier")

    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.count == slouchRequests + 2, "break is not throttled by slouch cooldown")
    check(identifiers == ["airposture.slouch", "airposture.break", "airposture.break"], "second break still posts")
}

@MainActor
private func checkBreakDoesNotConsumeSlouchCooldown() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AirPostureSettings(defaults: defaults)
    settings.soundAfterDoubleGrace = true
    let playback = PlaybackSpy()
    var now = Date()
    var identifiers: [String] = []
    let service = AlertService(
        playback: playback,
        now: { now },
        shouldSkipBanner: { false },
        postNotification: { identifiers.append($0) }
    )
    let banner = BreakReminder.banner(kind: .walk, mixIndex: 0)
    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.isEmpty && identifiers.isEmpty, "unconfigured break does nothing")
    service.configure(settings: settings)
    service.remindBreakIfAllowed(banner: banner)
    service.nudgeIfAllowed(slouchElapsedSeconds: 10, gracePeriodSeconds: 5)
    check(identifiers == ["airposture.break", "airposture.slouch"], "break bypasses double grace and does not start slouch cooldown")

    now.addTimeInterval(44)
    service.nudgeIfAllowed(slouchElapsedSeconds: 10, gracePeriodSeconds: 5)
    check(identifiers.count == 2, "slouch remains throttled before 45 seconds")
    service.remindBreakIfAllowed(banner: banner)
    now.addTimeInterval(1)
    service.nudgeIfAllowed(slouchElapsedSeconds: 10, gracePeriodSeconds: 5)
    check(identifiers == ["airposture.break", "airposture.slouch", "airposture.break", "airposture.slouch"], "break does not extend slouch cooldown")
    check(playback.requests.count == 4, "only eligible alerts request sound")
}

@MainActor
private func finishBreakSettingsChange() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
private func checkBreakReminderClockScheduling() async {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AirPostureSettings(defaults: defaults)
    let playback = PlaybackSpy()
    var now = Date()
    var focused = false
    var identifiers: [String] = []
    let service = AlertService(
        playback: playback,
        now: { now },
        shouldSkipBanner: { focused },
        postNotification: { identifiers.append($0) }
    )
    service.configure(settings: settings)
    let clock = BreakReminderClock(settings: settings, alerts: service, now: { now }, isFocusSuppressing: { focused })
    check(!clock.isEnabled && clock.remainingSeconds == 0, "disabled clock has no countdown")

    settings.breakRemindersEnabled = true
    await finishBreakSettingsChange()
    check(clock.isEnabled && clock.remainingSeconds == 2700, "enable subscription starts a full interval after settings change")
    now.addTimeInterval(60)
    clock.evaluate()
    check(clock.remainingSeconds == 2640, "clock follows wall time without headphone tracking")
    settings.breakIntervalMinutes = 5
    await finishBreakSettingsChange()
    check(clock.remainingSeconds == 300, "interval subscription restarts immediately")
    now.addTimeInterval(299.8)
    clock.evaluate()
    check(clock.remainingSeconds == 1 && identifiers.isEmpty, "clock rounds up and does not fire early")
    now.addTimeInterval(0.2)
    clock.evaluate()
    check(identifiers == ["airposture.break"] && settings.breakMixIndex == 1, "due clock fires once and advances mix")
    check(clock.remainingSeconds == 300, "due clock starts a fresh full interval")
    clock.evaluate()
    check(identifiers.count == 1, "same due evaluation cannot duplicate a break")

    settings.snooze(minutes: 5)
    now.addTimeInterval(300)
    clock.evaluate()
    check(identifiers.count == 1 && settings.breakMixIndex == 2 && clock.remainingSeconds == 300, "snoozed due clock advances without sound, banner, or backlog")
    settings.clearSnooze()
    focused = true
    now.addTimeInterval(300)
    clock.evaluate()
    check(identifiers.count == 1 && settings.breakMixIndex == 3 && clock.remainingSeconds == 300, "focused due clock advances without sound, banner, or backlog")
    focused = false
    now.addTimeInterval(310)
    clock.evaluate()
    check(identifiers.count == 1 && settings.breakMixIndex == 4 && clock.remainingSeconds == 300, "missed fire is skipped and rescheduled from now")
    check(playback.requests.count == 1, "suppressed and missed fires request no sound")

    settings.breakRemindersEnabled = false
    await finishBreakSettingsChange()
    check(!clock.isEnabled && clock.remainingSeconds == 0, "disable subscription clears countdown")
    now.addTimeInterval(3000)
    clock.evaluate()
    check(identifiers.count == 1, "disabled clock never fires")
    settings.breakRemindersEnabled = true
    await finishBreakSettingsChange()
    check(clock.remainingSeconds == 300, "re-enable starts full interval")
    now.addTimeInterval(60)
    settings.breakKind = .water
    clock.evaluate()
    check(clock.remainingSeconds == 240, "kind change preserves current interval")
    settings.breakRemindersEnabled = false
    settings.breakRemindersEnabled = true
    await finishBreakSettingsChange()
    check(clock.remainingSeconds == 300, "rapid off-on still resets interval")

    now.addTimeInterval(4000)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    await finishBreakSettingsChange()
    check(clock.remainingSeconds == 300 && identifiers.count == 1, "wake skips expired deadline and starts full interval")
    now.addTimeInterval(10)
    let relaunched = BreakReminderClock(settings: settings, alerts: service, now: { now }, isFocusSuppressing: { focused })
    check(relaunched.remainingSeconds == 300, "launch never restores leftover seconds")
    settings.breakRemindersEnabled = false
    await finishBreakSettingsChange()
}

@main
private struct AirPostureSoundCheck {
    @MainActor
    static func main() async throws {
        await checkNativeSamePackFallbackOwnership()
        try checkRealSelectedAssetsLoad()
        checkFalsePreparationFallsBackToSameSound()
        checkFalsePlayReportsFailureWhenFallbackFails()
        checkThrowAndAsynchronousFailureFallback()
        checkSecondPreviewReplacesFirst()
        checkPreviewErrorRecoveryAndWarningPolicy()
        checkBreakReminderPolicy()
        checkBreakDoesNotConsumeSlouchCooldown()
        await checkBreakReminderClockScheduling()

        if failures > 0 {
            FileHandle.standardError.write(Data("\(failures) sound check(s) failed\n".utf8))
            exit(1)
        }
        print("AirPosture sound checks passed")
    }
}
