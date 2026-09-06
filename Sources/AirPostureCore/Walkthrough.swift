public enum WalkthroughStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case headphones
    case motion
    case calibrate
    case nudges
    case ready
}

public struct WalkthroughPage: Equatable, Sendable {
    public let step: WalkthroughStep
    public let title: String
    public let body: String
    public let primaryTitle: String
    public let showsBack: Bool
    public let showsSkip: Bool
    public let showsConnectionStatus: Bool
    public let showsCalibrateControl: Bool
    public let showsMotionDeniedHint: Bool
}

public enum Walkthrough {
    public static let stepCount = 6

    public static func page(for step: WalkthroughStep) -> WalkthroughPage {
        switch step {
        case .welcome:
            return WalkthroughPage(
                step: step,
                title: "Welcome to AirPosture",
                body: "AirPosture lives in the menu bar. It uses the motion sensors in compatible AirPods to notice when your head stays tilted or leaned, then nudges you to sit up. Nothing is sent off this Mac.",
                primaryTitle: "Next",
                showsBack: false,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .headphones:
            return WalkthroughPage(
                step: step,
                title: "Connect your AirPods",
                body: "Put on AirPods Pro, AirPods Max, AirPods 3 or 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 cannot do this. The badge in the header turns Connected when they are ready.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: true,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .motion:
            return WalkthroughPage(
                step: step,
                title: "Allow Motion & Fitness",
                body: "macOS will ask for Motion & Fitness so AirPosture can read those sensors. If you already tapped Don’t Allow, open System Settings → Privacy & Security → Motion & Fitness and turn AirPosture on.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: true
            )
        case .calibrate:
            return WalkthroughPage(
                step: step,
                title: "Set your Neutral Posture",
                body: "Sit the way you want to hold yourself. Then press Set Neutral Posture. Desk and Sofa remember different sitting positions — switch the preset and set Neutral again when you change how you sit.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: true,
                showsMotionDeniedHint: false
            )
        case .nudges:
            return WalkthroughPage(
                step: step,
                title: "How reminders work",
                body: "A faint Glow can appear as you start to slouch. If you stay past your Neutral for a few seconds, AirPosture plays a sound and can show a Sit up straight! banner. Press Esc during a warning to snooze 15 minutes. The Glow never blocks clicks.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .ready:
            return WalkthroughPage(
                step: step,
                title: "You’re set",
                body: "Leave tracking on and wear your AirPods. Open Options anytime to change sensitivity, sounds, or optional break reminders. Replay these steps from How it works at the bottom of this window.",
                primaryTitle: "Done",
                showsBack: true,
                showsSkip: false,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        }
    }

    public static func advance(_ step: WalkthroughStep) -> WalkthroughStep? {
        WalkthroughStep(rawValue: step.rawValue + 1)
    }

    public static func back(_ step: WalkthroughStep) -> WalkthroughStep? {
        WalkthroughStep(rawValue: step.rawValue - 1)
    }

    public static func clamp(_ raw: Int) -> WalkthroughStep {
        if raw < 0 { return .welcome }
        if raw > stepCount - 1 { return .ready }
        return WalkthroughStep(rawValue: raw) ?? .welcome
    }

    public static func displayIndex(_ step: WalkthroughStep) -> Int {
        step.rawValue + 1
    }

    public static func progressText(_ step: WalkthroughStep) -> String {
        "\(displayIndex(step)) of \(stepCount)"
    }

    public static func accessibilityProgress(_ step: WalkthroughStep) -> String {
        "Step \(displayIndex(step)) of \(stepCount)"
    }

    public static func shouldAutoPresent(hasCompleted: Bool) -> Bool {
        !hasCompleted
    }

    public static func shouldMigrateAsCompleted(hasCompletionKey: Bool, hasAnyCalibration: Bool) -> Bool {
        !hasCompletionKey && hasAnyCalibration
    }
}
