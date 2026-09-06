import AppKit
import AVFoundation
import Foundation

enum SoundPlaybackChannel: Hashable {
    case warning
    case preview
    case chime
}

enum SoundPlaybackEvent: Equatable {
    case selectedAsset(URL)
    case primaryPrepared(Bool)
    case primaryStarted(Bool)
    case fallbackStarted(Bool)
    case finished(Bool)
    case failed(String)
}

@MainActor
protocol SoundPlaybackServing: AnyObject {
    func play(
        pack: SoundPack,
        volume: Double,
        channel: SoundPlaybackChannel,
        onEvent: @escaping (SoundPlaybackEvent) -> Void
    )
}

@MainActor
protocol PrimarySoundPlaying: AnyObject {
    var volume: Float { get set }
    var onFinished: ((Bool) -> Void)? { get set }
    var onDecodeError: ((Error?) -> Void)? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

@MainActor
protocol FallbackSoundPlaying: AnyObject {
    var volume: Float { get set }
    var onFinished: ((Bool) -> Void)? { get set }
    func play() -> Bool
    func stop()
}

@MainActor
private final class AVAudioPlayerBackend: NSObject, PrimarySoundPlaying, AVAudioPlayerDelegate {
    var onFinished: ((Bool) -> Void)?
    var onDecodeError: ((Error?) -> Void)?

    private let player: AVAudioPlayer

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    func prepareToPlay() -> Bool { player.prepareToPlay() }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onFinished?(flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.onDecodeError?(error)
        }
    }
}

@MainActor
private final class NSSoundBackend: NSObject, FallbackSoundPlaying, NSSoundDelegate {
    var onFinished: ((Bool) -> Void)?

    private let sound: NSSound

    var volume: Float {
        get { sound.volume }
        set { sound.volume = newValue }
    }

    init?(name: String) {
        // Named sounds are cached; each channel needs its own playback,
        // volume, and delegate lifetime.
        guard let sound = NSSound(named: name)?.copy() as? NSSound else { return nil }
        self.sound = sound
        super.init()
        sound.delegate = self
    }

    func play() -> Bool { sound.play() }
    func stop() { sound.stop() }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onFinished?(flag)
        }
    }
}

@MainActor
final class SoundPlayback: NSObject, SoundPlaybackServing {
    typealias PrimaryFactory = (URL) throws -> any PrimarySoundPlaying
    typealias FallbackFactory = (String) -> (any FallbackSoundPlaying)?

    private final class Session {
        let pack: SoundPack
        let volume: Float
        let onEvent: (SoundPlaybackEvent) -> Void
        var primary: (any PrimarySoundPlaying)?
        var fallback: (any FallbackSoundPlaying)?

        init(pack: SoundPack, volume: Float, onEvent: @escaping (SoundPlaybackEvent) -> Void) {
            self.pack = pack
            self.volume = volume
            self.onEvent = onEvent
        }
    }

    private let primaryFactory: PrimaryFactory
    private let fallbackFactory: FallbackFactory
    private var active: [SoundPlaybackChannel: Session] = [:]

    override convenience init() {
        self.init(
            primaryFactory: { try AVAudioPlayerBackend(url: $0) },
            fallbackFactory: { NSSoundBackend(name: $0) }
        )
    }

    init(
        primaryFactory: @escaping PrimaryFactory,
        fallbackFactory: @escaping FallbackFactory
    ) {
        self.primaryFactory = primaryFactory
        self.fallbackFactory = fallbackFactory
        super.init()
    }

    func play(
        pack: SoundPack,
        volume: Double,
        channel: SoundPlaybackChannel,
        onEvent: @escaping (SoundPlaybackEvent) -> Void
    ) {
        stop(channel: channel)

        let clampedVolume = Float(min(max(volume.isFinite ? volume : 0, 0), 1))
        let session = Session(pack: pack, volume: clampedVolume, onEvent: onEvent)
        active[channel] = session
        emit(.selectedAsset(pack.systemSoundURL), for: session, channel: channel)

        do {
            let player = try primaryFactory(pack.systemSoundURL)
            guard isActive(session, on: channel) else { return }
            session.primary = player
            player.volume = clampedVolume
            player.onFinished = { [weak self, weak session] successful in
                guard let self, let session else { return }
                self.primaryFinished(successful, session: session, channel: channel)
            }
            player.onDecodeError = { [weak self, weak session] error in
                guard let self, let session else { return }
                self.startFallback(
                    for: session,
                    channel: channel,
                    primaryFailure: "AVAudioPlayer decode failed: \(error.map(String.init(describing:)) ?? "unknown error")"
                )
            }

            let prepared = player.prepareToPlay()
            emit(.primaryPrepared(prepared), for: session, channel: channel)
            guard prepared else {
                startFallback(
                    for: session,
                    channel: channel,
                    primaryFailure: "AVAudioPlayer preparation returned false"
                )
                return
            }

            let started = player.play()
            emit(.primaryStarted(started), for: session, channel: channel)
            guard started else {
                startFallback(
                    for: session,
                    channel: channel,
                    primaryFailure: "AVAudioPlayer play returned false"
                )
                return
            }
        } catch {
            startFallback(
                for: session,
                channel: channel,
                primaryFailure: "AVAudioPlayer load threw: \(error)"
            )
        }
    }

    private func primaryFinished(
        _ successful: Bool,
        session: Session,
        channel: SoundPlaybackChannel
    ) {
        guard isActive(session, on: channel) else { return }
        emit(.finished(successful), for: session, channel: channel)
        if successful {
            finish(session, on: channel)
        } else {
            startFallback(
                for: session,
                channel: channel,
                primaryFailure: "AVAudioPlayer finished unsuccessfully"
            )
        }
    }

    private func startFallback(
        for session: Session,
        channel: SoundPlaybackChannel,
        primaryFailure: String
    ) {
        guard isActive(session, on: channel) else { return }
        NSLog("AirPosture sound %@ primary failure: %@", session.pack.rawValue, primaryFailure)
        session.primary?.onFinished = nil
        session.primary?.onDecodeError = nil
        session.primary?.stop()
        session.primary = nil

        guard let fallback = fallbackFactory(session.pack.systemSoundName) else {
            fail(session, on: channel, reason: "\(primaryFailure); NSSound could not load the selected name")
            return
        }
        session.fallback = fallback
        fallback.volume = session.volume
        fallback.onFinished = { [weak self, weak session] successful in
            guard let self, let session, self.isActive(session, on: channel) else { return }
            self.emit(.finished(successful), for: session, channel: channel)
            if successful {
                self.finish(session, on: channel)
            } else {
                self.fail(
                    session,
                    on: channel,
                    reason: "\(primaryFailure); NSSound finished unsuccessfully"
                )
            }
        }

        let started = fallback.play()
        emit(.fallbackStarted(started), for: session, channel: channel)
        if !started {
            fail(session, on: channel, reason: "\(primaryFailure); NSSound play returned false")
        }
    }

    private func stop(channel: SoundPlaybackChannel) {
        guard let session = active.removeValue(forKey: channel) else { return }
        session.primary?.onFinished = nil
        session.primary?.onDecodeError = nil
        session.fallback?.onFinished = nil
        session.primary?.stop()
        session.fallback?.stop()
    }

    private func finish(_ session: Session, on channel: SoundPlaybackChannel) {
        guard isActive(session, on: channel) else { return }
        session.primary?.onFinished = nil
        session.primary?.onDecodeError = nil
        session.fallback?.onFinished = nil
        active.removeValue(forKey: channel)
    }

    private func fail(_ session: Session, on channel: SoundPlaybackChannel, reason: String) {
        guard isActive(session, on: channel) else { return }
        emit(.failed(reason), for: session, channel: channel)
        finish(session, on: channel)
    }

    private func isActive(_ session: Session, on channel: SoundPlaybackChannel) -> Bool {
        active[channel] === session
    }

    private func emit(
        _ event: SoundPlaybackEvent,
        for session: Session,
        channel: SoundPlaybackChannel
    ) {
        guard isActive(session, on: channel) else { return }
        NSLog(
            "AirPosture sound %@ channel=%@ volume=%.3f event=%@",
            session.pack.rawValue,
            String(describing: channel),
            session.volume,
            String(describing: event)
        )
        session.onEvent(event)
    }
}
