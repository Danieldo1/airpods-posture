import AppKit
import AVFoundation
import Foundation
import Intents
import UserNotifications

@MainActor
final class AlertService {
    static let shared = AlertService()

    private let cooldown: TimeInterval = 45
    private var lastAlertAt: Date?
    private var warningPlayer: AVAudioPlayer?
    private var chimePlayer: AVAudioPlayer?
    private var fallbackSound: NSSound?
    private weak var settings: AirPostureSettings?

    private init() {}

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
        if let lastAlertAt, Date().timeIntervalSince(lastAlertAt) < cooldown {
            return
        }

        lastAlertAt = Date()
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

    private func shouldSkipBanner() -> Bool {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused == true
    }

    private func playWarningSound(pack: SoundPack, volume: Double) {
        play(pack: pack, volume: volume, store: { self.warningPlayer = $0 })
    }

    private func playChime(pack: SoundPack, volume: Double) {
        play(pack: pack, volume: volume, store: { self.chimePlayer = $0 })
    }

    private func play(pack: SoundPack, volume: Double, store: (AVAudioPlayer) -> Void) {
        let clamped = Float(min(max(volume, 0), 1))
        do {
            let player = try AVAudioPlayer(contentsOf: pack.systemSoundURL)
            player.volume = clamped
            player.prepareToPlay()
            player.play()
            store(player)
        } catch {
            guard let sound = NSSound(named: pack.systemSoundName) else { return }
            sound.volume = clamped
            sound.play()
            fallbackSound = sound
        }
    }

    private func postSitUpNotification() {
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
