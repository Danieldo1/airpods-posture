import AppKit
import Combine
import Foundation
import Intents
#if SWIFT_PACKAGE
import AirPostureCore
#endif

@MainActor
final class BreakReminderClock: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isEnabled = false

    var statusItemText: String { BreakReminder.statusItemText(remainingSeconds: remainingSeconds) }
    var popoverText: String { BreakReminder.popoverText(remainingSeconds: remainingSeconds) }
    var accessibilityRemaining: String { BreakReminder.accessibilityRemaining(remainingSeconds: remainingSeconds) }

    private static let tickInterval: TimeInterval = 1
    private let settings: AirPostureSettings
    private let alerts: AlertService
    private let now: () -> Date
    private let isFocusSuppressing: () -> Bool
    private var nextFire: Date?
    private var scheduledIntervalMinutes: Double?
    private var wasEnabled = false
    private var isSleeping = false
    private var subscriptions = Set<AnyCancellable>()
    private var timerSubscriptions = Set<AnyCancellable>()

    init(
        settings: AirPostureSettings,
        alerts: AlertService,
        now: @escaping () -> Date = Date.init,
        isFocusSuppressing: @escaping () -> Bool = {
            let center = INFocusStatusCenter.default
            guard center.authorizationStatus == .authorized else { return false }
            return center.focusStatus.isFocused == true
        }
    ) {
        self.settings = settings
        self.alerts = alerts
        self.now = now
        self.isFocusSuppressing = isFocusSuppressing

        // @Published emits before storage changes. Defer evaluation until didSet
        // has finished, including interval normalization. Keep each transition
        // so even an off/on pair within one run-loop turn restarts the clock.
        settings.$breakRemindersEnabled
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.nextFire = nil
                self?.evaluate()
            }
            .store(in: &subscriptions)
        settings.$breakIntervalMinutes
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.nextFire = nil
                self?.evaluate()
            }
            .store(in: &subscriptions)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isSleeping = true
                self?.timerSubscriptions.removeAll()
            }
            .store(in: &subscriptions)
        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let wakeDate = self.now()
                if let nextFire = self.nextFire, BreakReminder.isDue(now: wakeDate, nextFire: nextFire) {
                    self.settings.breakMixIndex = BreakReminder.nextMixIndex(self.settings.breakMixIndex)
                }
                self.isSleeping = false
                self.nextFire = nil
                self.evaluate(now: wakeDate)
            }
            .store(in: &subscriptions)
        evaluate()
    }

    func evaluate(now: Date? = nil) {
        let date = now ?? self.now()
        let enabled = settings.breakRemindersEnabled
        let interval = settings.breakIntervalMinutes
        if enabled && (!wasEnabled || scheduledIntervalMinutes != interval) {
            nextFire = nil
        }
        wasEnabled = enabled
        scheduledIntervalMinutes = interval
        if isEnabled != enabled { isEnabled = enabled }

        guard enabled else {
            remainingSeconds = 0
            nextFire = nil
            timerSubscriptions.removeAll()
            return
        }
        guard !isSleeping else { return }

        if timerSubscriptions.isEmpty {
            Timer.publish(every: Self.tickInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.evaluate() }
                .store(in: &timerSubscriptions)
        }

        var fire = nextFire ?? BreakReminder.nextFireDate(now: date, intervalMinutes: Int(interval))
        if BreakReminder.isDue(now: date, nextFire: fire) {
            // A normal 1 Hz tick can arrive less than one tick after the deadline.
            // Older deadlines were missed (sleep or a stalled run loop): skip them.
            let missed = date.timeIntervalSince(fire) >= Self.tickInterval
            let suppressed = settings.isSnoozed || isFocusSuppressing()
            if !missed && !suppressed {
                alerts.remindBreakIfAllowed(
                    banner: BreakReminder.banner(kind: settings.breakKind, mixIndex: settings.breakMixIndex)
                )
            }
            settings.breakMixIndex = BreakReminder.nextMixIndex(settings.breakMixIndex)
            fire = BreakReminder.nextFireDate(now: date, intervalMinutes: Int(interval))
        }
        nextFire = fire
        remainingSeconds = BreakReminder.remainingSeconds(now: date, nextFire: fire)
    }
}
