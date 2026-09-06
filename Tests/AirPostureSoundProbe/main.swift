import Foundation

@MainActor
private final class RecordingPlayback: SoundPlaybackServing {
    private let playback = SoundPlayback()
    private(set) var requests: [(pack: SoundPack, volume: Double, channel: SoundPlaybackChannel)] = []
    private(set) var events: [SoundPlaybackChannel: [SoundPlaybackEvent]] = [:]

    func play(
        pack: SoundPack,
        volume: Double,
        channel: SoundPlaybackChannel,
        onEvent: @escaping (SoundPlaybackEvent) -> Void
    ) {
        requests.append((pack, volume, channel))
        events[channel] = []
        playback.play(pack: pack, volume: volume, channel: channel) { [weak self] event in
            self?.events[channel, default: []].append(event)
            onEvent(event)
        }
    }

    func terminalEvent(for channel: SoundPlaybackChannel) -> SoundPlaybackEvent? {
        events[channel]?.last(where: {
            switch $0 {
            case .finished(true), .failed:
                true
            default:
                false
            }
        })
    }
}

@MainActor
private func waitForTerminalEvent(
    _ playback: RecordingPlayback,
    channel: SoundPlaybackChannel,
    timeout: TimeInterval = 3
) -> SoundPlaybackEvent? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, playback.terminalEvent(for: channel) == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.025))
    }
    return playback.terminalEvent(for: channel)
}

@main
private struct AirPostureSoundProbe {
    @MainActor
    static func main() {
        let suite = "AirPostureSoundProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            FileHandle.standardError.write(Data("Could not create isolated defaults\n".utf8))
            exit(1)
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AirPostureSettings(defaults: defaults)
        settings.soundVolume = 0.30
        let playback = RecordingPlayback()
        var clock = Date()
        var bannerCount = 0
        let alerts = AlertService(
            playback: playback,
            now: { clock },
            shouldSkipBanner: { false },
            postNotification: { bannerCount += 1 }
        )
        alerts.configure(settings: settings)

        print("runtime=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("defaultsSuite=\(suite) notifications=injected")

        var failed = false
        for pack in SoundPack.allCases {
            settings.soundPack = pack
            let persisted = defaults.string(forKey: "soundPack") ?? "nil"
            alerts.previewSound(pack: pack, volume: settings.soundVolume)
            let previewTerminal = waitForTerminalEvent(playback, channel: .preview)
            let previewEvents = playback.events[.preview, default: []]
            print(
                "preview pack=\(pack.rawValue) persisted=\(persisted) path=\(pack.systemSoundURL.path) events=\(previewEvents) terminal=\(String(describing: previewTerminal)) error=\(alerts.lastPlaybackError ?? "none")"
            )
            if previewTerminal != .finished(true) || alerts.lastPlaybackError != nil {
                failed = true
            }

            clock.addTimeInterval(46)
            alerts.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
            let warningTerminal = waitForTerminalEvent(playback, channel: .warning)
            let warningEvents = playback.events[.warning, default: []]
            print(
                "warning pack=\(pack.rawValue) path=\(pack.systemSoundURL.path) volume=\(settings.soundVolume) events=\(warningEvents) terminal=\(String(describing: warningTerminal)) banners=\(bannerCount) error=\(alerts.lastPlaybackError ?? "none")"
            )
            if warningTerminal != .finished(true) || alerts.lastPlaybackError != nil {
                failed = true
            }
        }

        let expectedRequests = SoundPack.allCases.count * 2
        if playback.requests.count != expectedRequests || bannerCount != SoundPack.allCases.count {
            failed = true
            FileHandle.standardError.write(
                Data("Unexpected request/banner counts: \(playback.requests.count)/\(bannerCount)\n".utf8)
            )
        }
        if failed {
            exit(1)
        }
        print("AirPosture native sound probe completed through playback callbacks")
    }
}
