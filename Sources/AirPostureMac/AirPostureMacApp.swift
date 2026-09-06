import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AirPostureCore
#endif

@main
struct AirPostureMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(session.tracker)
                .environmentObject(session.settings)
                .environmentObject(session.weekStore)
                .environmentObject(session.overlayManager)
                .environmentObject(session.breakClock)
        } label: {
            MenuBarStatusLabel(tracker: session.tracker, settings: session.settings, breakClock: session.breakClock)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var tracker: PostureTrackingManager
    @ObservedObject var settings: AirPostureSettings
    @ObservedObject var breakClock: BreakReminderClock

    var body: some View {
        HStack(spacing: 4) {
            MenuBarIcon(tracker: tracker, settings: settings, breakClock: breakClock)
            if breakClock.isEnabled {
                Text(breakClock.statusItemText)
                    .font(.caption.monospacedDigit())
                    .accessibilityHidden(true)
            }
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    let tracker: PostureTrackingManager
    let settings: AirPostureSettings
    let overlayManager: WarningOverlayManager
    let weekStore: WeeklyAnalyticsStore
    let breakClock: BreakReminderClock

    init() {
        let tracker = PostureTrackingManager()
        let settings = AirPostureSettings()
        self.tracker = tracker
        self.settings = settings
        self.overlayManager = WarningOverlayManager(tracker: tracker, settings: settings)
        self.weekStore = WeeklyAnalyticsStore(tracker: tracker)
        tracker.configure(settings: settings)
        settings.migrateWalkthroughIfNeeded(hasAnyCalibration: tracker.hasAnyCalibration)
        settings.isWalkthroughPresented = Walkthrough.shouldAutoPresent(
            hasCompleted: settings.hasCompletedWalkthrough
        )
        AlertService.shared.configure(settings: settings)
        self.breakClock = BreakReminderClock(settings: settings, alerts: .shared)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AlertService.shared.requestNotificationAccess()
        AlertService.shared.requestFocusStatusAccess()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
