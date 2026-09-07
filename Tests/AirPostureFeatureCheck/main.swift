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

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
        failures += 1
    }
}

func runTurnChecks() {
    // The zero is captured from the first sample of a new reference frame.
    var reference = YawReference()
    expect(reference.zeroDegrees == nil, "turn zero starts unestablished")
    expectEqual(reference.turnDegrees(forYaw: 20), 0, "first sample defines the zero")
    expectEqual(reference.turnDegrees(forYaw: 32), 12, "turn measured from the zero")

    // Sleep/wake and reconnects hand the headphones a fresh yaw origin, so a zero
    // captured against the old frame is meaningless and must not survive.
    reference.invalidate()
    expect(reference.zeroDegrees == nil, "frame change discards the zero")
    expectEqual(reference.turnDegrees(forYaw: 140), 0, "zero re-captured after frame change")
    expectEqual(reference.turnDegrees(forYaw: 150), 10, "turn measured from the new zero")

    // A gap in samples is not a new reference frame, so nothing about resuming
    // may move the zero. Re-capturing it here is what used to snap the turn to
    // 0 mid-turn and leave straight-ahead reading as a large offset.
    var dropout = YawReference()
    _ = dropout.turnDegrees(forYaw: 20)
    expectEqual(dropout.turnDegrees(forYaw: 50), 30, "zero survives a gap in samples")
    expect(dropout.zeroDegrees == 20, "resuming does not re-capture the zero")

    // Calibration moves the zero to whatever the user is facing now.
    reference.rezero(toYaw: 150)
    expectEqual(reference.turnDegrees(forYaw: 150), 0, "calibration zeroes the turn")

    // The zero is a circular value and must take the short way round the seam.
    var seam = YawReference()
    _ = seam.turnDegrees(forYaw: 178)
    expectEqual(seam.turnDegrees(forYaw: -175), 7, "turn crosses the ±180° seam")

    // The sensor delivers about 50 Hz; 0.04 s steps pace these checks a little
    // coarser than that, which only makes the time-based math work harder.
    let sampleStep = 0.04
    let gate = 35.0

    // THE regression. The zero must not follow the head: a real turn has to keep
    // reading for as long as it is held, and straight ahead has to keep reading
    // zero afterwards. Easing the zero toward the head's heading is what used to
    // leave a held glance decaying away and the return shifted the other way.
    var held = YawReference()
    _ = held.turnDegrees(forYaw: 0)
    var heldTurn = 0.0
    for step in 1...25 {
        heldTurn = held.turnDegrees(
            forYaw: Double(step),
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(heldTurn, 25, "a real turn reads its full angle")
    for step in 0..<Int(600 / sampleStep) {
        // Flat to a tenth of a degree, the way a resting head reads.
        let jitter = 0.1 * sin(Double(step) * sampleStep * 7)
        heldTurn = held.turnDegrees(
            forYaw: 25 + jitter,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(heldTurn, 25, "a turn held still for ten minutes still reads", accuracy: 0.5)
    var returned = 0.0
    for step in stride(from: 24, through: 0, by: -1) {
        returned = held.turnDegrees(
            forYaw: Double(step),
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(returned, 0, "looking back after a long hold reads straight ahead", accuracy: 0.5)

    // Calibration is the user saying "this is forward". Nothing about a turn
    // taken seconds later may be treated as provisional.
    var calibrated = YawReference()
    calibrated.rezero(toYaw: 100)
    for _ in 0..<Int(2 / sampleStep) {
        _ = calibrated.turnDegrees(
            forYaw: 100,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    var freshTurn = 0.0
    for step in 1...25 {
        freshTurn = calibrated.turnDegrees(
            forYaw: 100 + Double(step),
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    for _ in 0..<Int(180 / sampleStep) {
        freshTurn = calibrated.turnDegrees(
            forYaw: 125,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(freshTurn, 25, "a turn taken right after calibration is not absorbed", accuracy: 0.5)

    // Real drift is yaw moving while the head is not: absorb it into the zero so
    // it never reaches the readout, however long it creeps.
    var creeping = YawReference()
    _ = creeping.turnDegrees(forYaw: 0)
    var worstCreep = 0.0
    for step in 1...Int(1800 / sampleStep) {
        let creepingYaw = Double(step) * sampleStep / 60
        let turn = creeping.turnDegrees(
            forYaw: creepingYaw,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
        worstCreep = max(worstCreep, abs(turn))
    }
    expect(worstCreep < 0.2, "a degree a minute of drift never reaches the readout, worst was \(worstCreep)")
    expectEqual(creeping.zeroDegrees ?? .nan, 30, "the zero followed the drift", accuracy: 0.2)

    var fastDrift = YawReference()
    _ = fastDrift.turnDegrees(forYaw: 0)
    var fastDriftTurn = 0.0
    for step in 1...Int(60 / sampleStep) {
        fastDriftTurn = fastDrift.turnDegrees(
            forYaw: Double(step) * sampleStep * 0.5,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(fastDriftTurn, 0, "half a degree a second of drift is absorbed too", accuracy: 0.05)

    // The heading is still converging just after the sensor establishes a frame.
    var converging = YawReference()
    _ = converging.turnDegrees(forYaw: 0)
    var convergingTurn = 0.0
    for step in 1...Int(2 / sampleStep) {
        convergingTurn = converging.turnDegrees(
            forYaw: Double(step) * sampleStep * 1.5,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(convergingTurn, 0, "a heading converging after connect is absorbed", accuracy: 0.1)

    // Absorption is capped per sample, so a real turn the gyro failed to notice
    // leaks through as a turn instead of disappearing into the zero.
    var misflagged = YawReference()
    _ = misflagged.turnDegrees(forYaw: 0)
    let leaked = misflagged.turnDegrees(
        forYaw: 6,
        elapsedSeconds: sampleStep,
        isHeadStill: true,
        lookAwayThresholdDegrees: gate
    )
    expect(leaked > 5.5, "a turn wrongly flagged still is not erased, got \(leaked)")

    // Nor may one sample claim a long stall and absorb the whole jump across it.
    var stalled = YawReference()
    _ = stalled.turnDegrees(forYaw: 0)
    let afterStall = stalled.turnDegrees(
        forYaw: 20,
        elapsedSeconds: 4,
        isHeadStill: true,
        lookAwayThresholdDegrees: gate
    )
    expect(afterStall > 19.5, "a stalled sample absorbs at most one step, got \(afterStall)")

    // A turn parked past the gate with the head motionless for minutes is a
    // stale zero, not a glance. Under that time it must still read in full.
    var latched = YawReference()
    _ = latched.turnDegrees(forYaw: 0)
    for step in 1...50 {
        _ = latched.turnDegrees(
            forYaw: Double(step),
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    var latchedTurn = 0.0
    for _ in 0..<Int(170 / sampleStep) {
        latchedTurn = latched.turnDegrees(
            forYaw: 50,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(latchedTurn, 50, "a held look-away reads in full before the un-latch time")
    expectEqual(latched.zeroDegrees ?? .nan, 0, "holding a look-away does not drag the zero")
    for _ in 0..<Int(20 / sampleStep) {
        latchedTurn = latched.turnDegrees(
            forYaw: 50,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(latchedTurn, 0, "a look-away held motionless past the un-latch time becomes forward")
    expectEqual(latched.zeroDegrees ?? .nan, 50, "un-latching takes the current heading as the zero")

    // Time only counts while the head is motionless, so walking around with the
    // head turned cannot redefine forward mid-stride.
    var walking = YawReference()
    _ = walking.turnDegrees(forYaw: 0)
    var walkingTurn = 0.0
    for _ in 0..<Int(600 / sampleStep) {
        walkingTurn = walking.turnDegrees(
            forYaw: 50,
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(walkingTurn, 50, "moving samples do not age a held look-away")

    // Looking forward again restarts the clock: two glances short of the
    // un-latch time do not add up to one long one.
    var glancing = YawReference()
    _ = glancing.turnDegrees(forYaw: 0)
    for step in 1...50 {
        _ = glancing.turnDegrees(
            forYaw: Double(step),
            elapsedSeconds: sampleStep,
            isHeadStill: false,
            lookAwayThresholdDegrees: gate
        )
    }
    var glanceTurn = 0.0
    for pass in 0..<2 {
        for _ in 0..<Int(170 / sampleStep) {
            glanceTurn = glancing.turnDegrees(
                forYaw: 50,
                elapsedSeconds: sampleStep,
                isHeadStill: true,
                lookAwayThresholdDegrees: gate
            )
        }
        if pass == 0 {
            _ = glancing.turnDegrees(
                forYaw: 0,
                elapsedSeconds: sampleStep,
                isHeadStill: false,
                lookAwayThresholdDegrees: gate
            )
        }
    }
    expect(glanceTurn > 45, "looking forward restarts the un-latch clock, got \(glanceTurn)")

    // With the gate off there is no angle to un-latch from.
    var ungated = YawReference()
    _ = ungated.turnDegrees(forYaw: 0)
    for step in 1...50 {
        _ = ungated.turnDegrees(forYaw: Double(step), elapsedSeconds: sampleStep, isHeadStill: false)
    }
    var ungatedTurn = 0.0
    for _ in 0..<Int(600 / sampleStep) {
        ungatedTurn = ungated.turnDegrees(forYaw: 50, elapsedSeconds: sampleStep, isHeadStill: true)
    }
    expectEqual(ungatedTurn, 50, "a zero threshold never un-latches")

    // The zero is circular, so absorbing drift has to cross the seam and stay
    // inside ±180 rather than wander off the scale.
    var seamDrift = YawReference()
    _ = seamDrift.turnDegrees(forYaw: 179)
    var seamDriftTurn = 0.0
    var seamYaw = 179.0
    for _ in 0..<100 {
        seamYaw = PostureGaugeMapping.wrappedDegreesDelta(current: seamYaw + 0.02, baseline: 0)
        seamDriftTurn = seamDrift.turnDegrees(
            forYaw: seamYaw,
            elapsedSeconds: sampleStep,
            isHeadStill: true,
            lookAwayThresholdDegrees: gate
        )
    }
    expectEqual(seamDriftTurn, 0, "drift across the ±180° seam stays at zero", accuracy: 0.01)
    expectEqual(seamDrift.zeroDegrees ?? .nan, -179, "the zero stays normalized across the seam", accuracy: 0.01)

    // The first sample after a gap carries an interval nobody observed, so the
    // jump across it shows as a turn instead of being absorbed.
    var resumed = YawReference()
    _ = resumed.turnDegrees(forYaw: 0)
    let afterGap = resumed.turnDegrees(
        forYaw: 30,
        elapsedSeconds: 0,
        isHeadStill: true,
        lookAwayThresholdDegrees: gate
    )
    expectEqual(afterGap, 30, "a sample after a gap is not absorbed")
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
    case "breaks":
        runBreakReminderChecks()
    case "walkthrough":
        runWalkthroughChecks()
    case "turn":
        runTurnChecks()
    default:
        FileHandle.standardError.write(Data("FAIL unknown feature-check group: \(name)\n".utf8))
        failures += 1
    }
}

let requestedGroups = CommandLine.arguments.dropFirst()
let groups = requestedGroups.isEmpty ? ["warnings", "analytics", "breaks", "walkthrough", "turn"] : Array(requestedGroups)
for group in groups {
    runGroup(named: group)
}

if failures > 0 {
    FileHandle.standardError.write(Data("\(failures) feature check(s) failed\n".utf8))
    exit(1)
}

print("AirPosture feature checks passed: \(groups.joined(separator: ", "))")
