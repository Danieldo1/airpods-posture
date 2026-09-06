import AppKit
import Combine
import Foundation
import Intents
import UserNotifications

@MainActor
final class AlertService: ObservableObject {
    static let shared = AlertService()

    @Published private(set) var lastPlaybackError: String?

    private let cooldown: TimeInterval = 45
    private var lastAlertAt: Date?
    private weak var settings: AirPostureSettings?
    private let playback: any SoundPlaybackServing
    private let now: () -> Date
    private let bannerPolicy: (() -> Bool)?
    private let notificationPoster: (() -> Void)?

    private init() {
        playback = SoundPlayback()
        now = Date.init
        bannerPolicy = nil
        notificationPoster = nil
    }

    init(
        playback: any SoundPlaybackServing,
        now: @escaping () -> Date,
        shouldSkipBanner: @escaping () -> Bool,
        postNotification: @escaping () -> Void
    ) {
        self.playback = playback
        self.now = now
        bannerPolicy = shouldSkipBanner
        notificationPoster = postNotification
    }

    func configure(settings: AirPostureSettings) {
        self.settings = settings
    }

    func requestNotificationAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func requestFocusStatusAccess() {
        INFocusStatusCenter.default.requestAuthorization { _ in }
    }

    func nudgeIfAllowed(slouchElapsedSeconds: Double, gracePeriodSeconds: Double) {
        guard let settings else { return }
        if settings.isSnoozed {
            return
        }
        if settings.soundAfterDoubleGrace,
           slouchElapsedSeconds < 2 * gracePeriodSeconds {
            return
        }
        let alertDate = now()
        if let lastAlertAt, alertDate.timeIntervalSince(lastAlertAt) < cooldown {
            return
        }

        lastAlertAt = alertDate
        playWarningSound(pack: settings.soundPack, volume: settings.soundVolume)
        if shouldSkipBanner() {
            return
        }
        postSitUpNotification()
    }

    func playSitUpChimeIfAllowed() {
        guard let settings, settings.sitUpChimeEnabled, !settings.isSnoozed else { return }
        let pack: SoundPack = settings.soundPack == .tink ? .pop : .tink
        playChime(pack: pack, volume: 0.40 * settings.soundVolume)
    }

    func previewSound(pack: SoundPack, volume: Double) {
        play(pack: pack, volume: volume, channel: .preview)
    }

    private func shouldSkipBanner() -> Bool {
        if let bannerPolicy {
            return bannerPolicy()
        }
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused == true
    }

    private func playWarningSound(pack: SoundPack, volume: Double) {
        play(pack: pack, volume: volume, channel: .warning)
    }

    private func playChime(pack: SoundPack, volume: Double) {
        play(pack: pack, volume: volume, channel: .chime)
    }

    private func play(pack: SoundPack, volume: Double, channel: SoundPlaybackChannel) {
        playback.play(pack: pack, volume: volume, channel: channel) { [weak self] event in
            guard let self else { return }
            switch event {
            case .primaryStarted(true), .fallbackStarted(true), .finished(true):
                self.lastPlaybackError = nil
            case let .failed(reason):
                NSLog("AirPosture could not play %@: %@", pack.rawValue, reason)
                self.lastPlaybackError = "Couldn’t play \(pack.title)."
            case .selectedAsset, .primaryPrepared, .primaryStarted, .fallbackStarted, .finished:
                break
            }
        }
    }

    private func postSitUpNotification() {
        if let notificationPoster {
            notificationPoster()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Sit up straight!"
        content.body = "Your head has drifted past your tilt or lean threshold."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "airposture.slouch",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
