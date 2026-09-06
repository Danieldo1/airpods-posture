import AirPostureCore
import Foundation

func runWalkthroughChecks() {
    expectValue(Walkthrough.stepCount, 6, "six steps")
    expectValue(WalkthroughStep.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5], "raw values are contiguous")

    expectValue(Walkthrough.advance(.welcome), .headphones, "advance welcome")
    expectValue(Walkthrough.advance(.nudges), .ready, "advance nudges")
    expectTrue(Walkthrough.advance(.ready) == nil, "advance past last is nil")
    expectTrue(Walkthrough.back(.welcome) == nil, "back from first is nil")
    expectValue(Walkthrough.back(.headphones), .welcome, "back headphones")
    expectValue(Walkthrough.back(.ready), .nudges, "back ready")

    expectValue(Walkthrough.clamp(-3), .welcome, "clamp low")
    expectValue(Walkthrough.clamp(0), .welcome, "clamp welcome")
    expectValue(Walkthrough.clamp(5), .ready, "clamp ready")
    expectValue(Walkthrough.clamp(99), .ready, "clamp high")

    expectValue(Walkthrough.displayIndex(.welcome), 1, "first page is 1")
    expectValue(Walkthrough.displayIndex(.ready), 6, "last page is 6")
    expectValue(Walkthrough.progressText(.motion), "3 of 6", "progress text")
    expectValue(Walkthrough.accessibilityProgress(.motion), "Step 3 of 6", "progress a11y")

    expectTrue(Walkthrough.shouldAutoPresent(hasCompleted: false), "incomplete auto-presents")
    expectTrue(!Walkthrough.shouldAutoPresent(hasCompleted: true), "completed does not auto-present")

    expectTrue(Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: false, hasAnyCalibration: true), "existing calibrated user migrates")
    expectTrue(!Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: false, hasAnyCalibration: false), "brand-new user does not migrate")
    expectTrue(!Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: true, hasAnyCalibration: true), "written key is left alone")
    expectTrue(!Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: true, hasAnyCalibration: false), "written key without calibration is left alone")

    let welcome = Walkthrough.page(for: .welcome)
    expectValue(welcome.title, "Welcome to AirPosture", "welcome title")
    expectValue(welcome.body, "AirPosture lives in the menu bar. It uses the motion sensors in compatible AirPods to notice when your head stays tilted or leaned, then nudges you to sit up. Nothing is sent off this Mac.", "welcome body")
    expectValue(welcome.primaryTitle, "Next", "welcome primary")
    expectTrue(!welcome.showsBack && welcome.showsSkip, "welcome chrome")
    expectTrue(!welcome.showsConnectionStatus && !welcome.showsCalibrateControl && !welcome.showsMotionDeniedHint, "welcome extras off")

    let headphones = Walkthrough.page(for: .headphones)
    expectValue(headphones.title, "Connect your AirPods", "headphones title")
    expectValue(headphones.body, "Put on AirPods Pro, AirPods Max, AirPods 3 or 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 cannot do this. The badge in the header turns Connected when they are ready.", "headphones body")
    expectTrue(headphones.showsConnectionStatus, "headphones shows status")

    let motion = Walkthrough.page(for: .motion)
    expectValue(motion.title, "Allow Motion & Fitness", "motion title")
    expectValue(motion.body, "macOS will ask for Motion & Fitness so AirPosture can read those sensors. If you already tapped Don’t Allow, open System Settings → Privacy & Security → Motion & Fitness and turn AirPosture on.", "motion body")
    expectTrue(motion.showsMotionDeniedHint, "motion may show denied hint")

    let calibrate = Walkthrough.page(for: .calibrate)
    expectValue(calibrate.title, "Set your Neutral Posture", "calibrate title")
    expectValue(calibrate.body, "Sit the way you want to hold yourself. Then press Set Neutral Posture. Desk and Sofa remember different sitting positions — switch the preset and set Neutral again when you change how you sit.", "calibrate body")
    expectTrue(calibrate.showsCalibrateControl, "calibrate shows button")

    let nudges = Walkthrough.page(for: .nudges)
    expectValue(nudges.title, "How reminders work", "nudges title")
    expectValue(nudges.body, "A faint Glow can appear as you start to slouch. If you stay past your Neutral for a few seconds, AirPosture plays a sound and can show a Sit up straight! banner. Press Esc during a warning to snooze 15 minutes. The Glow never blocks clicks.", "nudges body")
    expectValue(nudges.primaryTitle, "Next", "nudges primary")

    let ready = Walkthrough.page(for: .ready)
    expectValue(ready.title, "You’re set", "ready title")
    expectValue(ready.body, "Leave tracking on and wear your AirPods. Open Options anytime to change sensitivity, sounds, or optional break reminders. Replay these steps from How it works at the bottom of this window.", "ready body")
    expectValue(ready.primaryTitle, "Done", "ready primary")
    expectTrue(ready.showsBack && !ready.showsSkip, "ready chrome")
}
