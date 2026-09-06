// Manual native QA host. Compiles the production views without the app entry point.
// Uses a unique bundle/preferences domain and temporary generated analytics only.
import AppKit
import Combine
import SwiftUI

@MainActor final class FixtureState: ObservableObject {
    enum Scenario: String, CaseIterable { case empty = "Empty", mixed = "Mixed", dense = "Dense" }
    @Published var scenario = Scenario.mixed { didSet { store = Self.makeStore(scenario) } }
    @Published var store: WeeklyAnalyticsStore
    let settings: AirPostureSettings
    let tracker: PostureTrackingManager
    init() {
        UserDefaults.standard.set(false, forKey: "isTrackingEnabled")
        settings = AirPostureSettings()
        if CommandLine.arguments.contains("--smoke-console") {
            tracker = PostureTrackingManager(
                defaults: .standard, now: Date.init,
                monotonic: { ProcessInfo.processInfo.systemUptime }, motionManager: nil
            )
        } else {
            tracker = PostureTrackingManager()
        }
        tracker.configure(settings: settings)
        AlertService.shared.configure(settings: settings)
        store = Self.makeStore(.mixed)
    }
    private static func makeDays(_ scenario: Scenario, now: Date = Date(), calendar: Calendar = .current) -> [String: DayBucket] {
        var days: [String: DayBucket] = [:]
        for offset in 0..<90 where scenario != .empty {
            // Gaps, very short sessions, and legacy/new mixed records in one week.
            if scenario == .mixed && [2, 5, 8, 9, 14, 21].contains(offset % 29) { continue }
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            let monitored = offset == 3 ? 17.5 : Double(1800 + (offset % 9) * 1200)
            let offNeutral = monitored * (0.12 + Double(offset % 5) * 0.10)
            let legacy = offset > 35 || offset % 4 == 0
            let countdown = offNeutral * (legacy ? 0.15 : 0.35)
            let slouch = offNeutral * (legacy ? 0.40 : 0.65)
            let unsplit = legacy ? offNeutral * 0.45 : 0
            // Match accumulator composition: independently multiplied fractions can
            // sum one ULP above their source total (for example the 17.5s fixture).
            let classifiedOffNeutral = (countdown + slouch) + unsplit
            days[PostureAnalytics.dayKey(for: date, calendar: calendar)] = DayBucket(
                monitoredSeconds: monitored, offNeutralSeconds: classifiedOffNeutral,
                countdownSeconds: countdown, slouchSeconds: slouch, slouchEpisodes: offset % 6)
        }
        return days
    }
    static func validateFixtureData() throws {
        for scenario in Scenario.allCases {
            let document = AnalyticsDocument(days: makeDays(scenario))
            let encoded = try JSONEncoder().encode(document)
            let decoded = try JSONDecoder().decode(AnalyticsDocument.self, from: encoded)
            precondition(decoded == document, "Fixture JSON round trip must preserve every duration")
            switch scenario {
            case .empty: precondition(document.days.isEmpty)
            case .mixed: precondition(!document.days.isEmpty && document.days.count < 90)
            case .dense: precondition(document.days.count == 90)
            }
            print("Validated \(scenario.rawValue): \(document.days.count) dates, valid categories and lossless JSON round trip")
        }
    }
    private static func makeStore(_ scenario: Scenario) -> WeeklyAnalyticsStore {
        let days = makeDays(scenario)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirPostureUIFixture-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("weekly-analytics.json")
        try! JSONEncoder().encode(AnalyticsDocument(days: days)).write(to: file)
        return WeeklyAnalyticsStore(observations: Empty<AnalyticsObservation, Never>().eraseToAnyPublisher(), fileURL: file)
    }
}

struct FixtureView: View {
    @StateObject var state = FixtureState()
    @State private var dark = false
    @State private var page = "Console"
    @State private var expanded = true
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Native UI fixtures").font(.headline)
                Picker("Data", selection: $state.scenario) {
                    ForEach(FixtureState.Scenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
                Toggle("Dark appearance", isOn: $dark)
                Picker("Production view", selection: $page) {
                    Text("Console").tag("Console")
                    Text("Reminders").tag("Reminders")
                    Text("Analytics").tag("Analytics")
                }.pickerStyle(.radioGroup)
                Text("Console uses the actual menu-bar view. Expand This week and Options, then scroll. Reminders and Analytics isolate those same views for closer inspection.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Temporary data · separate preferences · motion starts paused")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }.padding(16).frame(width: 220)
            Divider()
            Group {
                if page == "Console" {
                    MenuBarView().environmentObject(state.tracker).environmentObject(state.settings).environmentObject(state.store)
                } else if page == "Reminders" {
                    ScrollView(.vertical) {
                        ReminderOptionsView(settings: state.settings).padding(16).frame(width: 360)
                            .background(ConsoleScrollBehavior())
                    }
                } else {
                    ScrollView(.vertical) {
                        PostureAnalyticsView(store: state.store, isExpanded: $expanded).padding(16).frame(width: 360)
                            .background(ConsoleScrollBehavior())
                    }
                }
            }.frame(width: 360)
        }
        .preferredColorScheme(dark ? .dark : .light)
        .frame(width: 581)
    }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let visible = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: visible.maxX - 601, y: visible.minY + 8, width: 581, height: visible.height - 48),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AirPosture UI Fixture"
        window.contentView = NSHostingView(rootView: FixtureView())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-console") {
            Task { @MainActor in
                for attempt in 1...3 {
                    try? await Task.sleep(for: .milliseconds(500))
                    window.displayIfNeeded()
                    precondition(window.isVisible, "Console smoke window must be displayed")
                    if attempt < 3 {
                        // Recreate the real console and its layer-backed scroll view.
                        window.contentView = NSHostingView(rootView: FixtureView())
                    }
                }
                print("AirPosture console smoke check passed: three displayed console lifecycles")
                fflush(stdout)
                window.orderOut(nil)
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FixtureApp {
    static func main() {
        if CommandLine.arguments.contains("--validate-fixtures") {
            do { try FixtureState.validateFixtureData() }
            catch { fputs("Fixture validation failed: \(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
