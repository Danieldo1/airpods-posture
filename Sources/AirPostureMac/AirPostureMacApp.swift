import AppKit
import SwiftUI

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
        } label: {
            MenuBarIcon(tracker: session.tracker, settings: session.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppSession: ObservableObject {
    let tracker: PostureTrackingManager
    let settings: AirPostureSettings
    let overlayManager: WarningOverlayManager
    let weekStore: WeeklyAnalyticsStore

    init() {
        let tracker = PostureTrackingManager()
        let settings = AirPostureSettings()
        self.tracker = tracker
        self.settings = settings
        self.overlayManager = WarningOverlayManager(tracker: tracker, settings: settings)
        self.weekStore = WeeklyAnalyticsStore(tracker: tracker)
        tracker.configure(settings: settings)
        AlertService.shared.configure(settings: settings)
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
