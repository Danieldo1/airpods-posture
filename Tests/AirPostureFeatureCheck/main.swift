import AirPostureCore
import Foundation

var failures = 0

func expectEqual(
    _ actual: Double,
    _ expected: Double,
    _ name: String,
    accuracy: Double = 0.0000001
) {
    if !actual.isFinite || !expected.isFinite || abs(actual - expected) > accuracy {
        FileHandle.standardError.write(Data("FAIL \(name): expected \(expected), got \(actual)\n".utf8))
        failures += 1
    }
}

func runWarningChecks() {
    expectEqual(
        WarningIntensity.target(
            deviation: 0.7,
            graceProgress: 0,
            isSlouching: false,
            earlyEnabled: true,
            onset: 0.7
        ),
        0,
        "cue is zero at onset"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 0.85,
            graceProgress: 0,
            isSlouching: false,
            earlyEnabled: true,
            onset: 0.7
        ),
        0.125,
        "cue midpoint maps to one-eighth",
        accuracy: 0.0001
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 1,
            graceProgress: 0.5,
            isSlouching: false,
            earlyEnabled: true,
            onset: 1
        ),
        0.625,
        "half grace maps to five-eighths"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 0.999,
            graceProgress: 1,
            isSlouching: false,
            earlyEnabled: true,
            onset: 0.7
        ),
        0.2499917,
        "pre-threshold stage remains capped below one-quarter",
        accuracy: 0.000001
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 1,
            graceProgress: 0,
            isSlouching: false,
            earlyEnabled: true,
            onset: 0.7
        ),
        0.25,
        "threshold begins countdown at one-quarter"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 0,
            graceProgress: 0,
            isSlouching: true,
            earlyEnabled: true,
            onset: 0.7
        ),
        1,
        "sustained slouch reaches full target"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 0.999,
            graceProgress: 0,
            isSlouching: false,
            earlyEnabled: true,
            onset: 1
        ),
        0,
        "one-hundred-percent onset omits pre-threshold cue"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: 2,
            graceProgress: 1,
            isSlouching: false,
            earlyEnabled: false,
            onset: 0.7
        ),
        0,
        "disabled early cue waits for sustained state"
    )
    expectEqual(
        WarningIntensity.target(
            deviation: .nan,
            graceProgress: .infinity,
            isSlouching: false,
            earlyEnabled: true,
            onset: -.infinity
        ),
        0,
        "non-finite motion input produces no cue"
    )

    var heldTarget = WarningEnvelope()
    expectEqual(
        heldTarget.update(target: 1, elapsed: 3, fadeIn: 3, reduceMotion: false),
        0.95,
        "fade-in reaches ninety-five percent at configured duration"
    )

    var singleTick = WarningEnvelope()
    var manyTicks = WarningEnvelope()
    let once = singleTick.update(target: 1, elapsed: 3, fadeIn: 3, reduceMotion: false)
    var stepped = 0.0
    for _ in 0..<180 {
        stepped = manyTicks.update(target: 1, elapsed: 1.0 / 60.0, fadeIn: 3, reduceMotion: false)
    }
    expectEqual(stepped, once, "held-target response is frame-rate independent")

    var lowerTarget = WarningEnvelope()
    _ = lowerTarget.update(target: 1, elapsed: 0, fadeIn: 3, reduceMotion: true)
    expectEqual(
        lowerTarget.update(target: 0.5, elapsed: 0.35, fadeIn: 3, reduceMotion: false),
        0.525,
        "lower positive target completes ninety-five percent recovery in 350ms"
    )

    var zeroTarget = WarningEnvelope()
    _ = zeroTarget.update(target: 1, elapsed: 0, fadeIn: 3, reduceMotion: true)
    expectEqual(
        zeroTarget.update(target: 0, elapsed: 0.349, fadeIn: 3, reduceMotion: false),
        1.0 / 350.0,
        "zero recovery remains visible immediately before 350ms"
    )
    expectEqual(
        zeroTarget.update(target: 0, elapsed: 0.001, fadeIn: 3, reduceMotion: false),
        0,
        "zero recovery reaches exact zero at 350ms"
    )
    expectEqual(
        zeroTarget.update(target: 1, elapsed: 3, fadeIn: 3, reduceMotion: false),
        0.95,
        "envelope recovers after reaching zero"
    )

    var reduceMotion = WarningEnvelope()
    expectEqual(
        reduceMotion.update(target: 0.25, elapsed: 0, fadeIn: 3, reduceMotion: true),
        0.25,
        "Reduce Motion snaps to early cue target"
    )
    expectEqual(
        reduceMotion.update(target: 2, elapsed: 0, fadeIn: 3, reduceMotion: true),
        1,
        "envelope clamps targets above one"
    )
    expectEqual(
        reduceMotion.update(target: .nan, elapsed: 1, fadeIn: 3, reduceMotion: true),
        0,
        "envelope rejects non-finite targets"
    )

    var calibrationTransition = WarningPresentationState()
    expectEqual(
        calibrationTransition.update(
            target: 1,
            elapsed: 3,
            fadeIn: 3,
            reduceMotion: false,
            isEligible: true,
            referenceID: "desk"
        ),
        0.95,
        "presentation state can hold a visible warning"
    )
    expectEqual(
        calibrationTransition.update(
            target: 1,
            elapsed: 0.01,
            fadeIn: 3,
            reduceMotion: false,
            isEligible: false,
            referenceID: "desk"
        ),
        0,
        "calibration transition cancels visible warning immediately"
    )
    expectEqual(
        calibrationTransition.update(
            target: 1,
            elapsed: 0,
            fadeIn: 3,
            reduceMotion: false,
            isEligible: true,
            referenceID: "desk"
        ),
        0,
        "calibration recovery cannot replay the stale envelope"
    )

    var presetTransition = WarningPresentationState()
    _ = presetTransition.update(
        target: 1,
        elapsed: 3,
        fadeIn: 3,
        reduceMotion: false,
        isEligible: true,
        referenceID: "desk"
    )
    expectEqual(
        presetTransition.update(
            target: 1,
            elapsed: 0.01,
            fadeIn: 3,
            reduceMotion: false,
            isEligible: true,
            referenceID: "sofa"
        ),
        0,
        "preset reference change cancels visible warning immediately"
    )
    expectEqual(
        presetTransition.update(
            target: 1,
            elapsed: 0,
            fadeIn: 3,
            reduceMotion: false,
            isEligible: true,
            referenceID: "sofa"
        ),
        0,
        "preset recovery cannot replay the stale envelope"
    )
}

private func runGroup(named name: String) {
    switch name {
    case "warnings":
        runWarningChecks()
    case "analytics":
        runAnalyticsChecks()
    default:
        FileHandle.standardError.write(Data("FAIL unknown feature-check group: \(name)\n".utf8))
        failures += 1
    }
}

let requestedGroups = CommandLine.arguments.dropFirst()
let groups = requestedGroups.isEmpty ? ["warnings", "analytics"] : Array(requestedGroups)
for group in groups {
    runGroup(named: group)
}

if failures > 0 {
    FileHandle.standardError.write(Data("\(failures) feature check(s) failed\n".utf8))
    exit(1)
}

print("AirPosture feature checks passed: \(groups.joined(separator: ", "))")
