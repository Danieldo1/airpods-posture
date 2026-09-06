import AirPostureCore
import Foundation

private var failures = 0

private func expectEqual(_ actual: Double, _ expected: Double, _ name: String, accuracy: Double = 0.0001) {
    if abs(actual - expected) > accuracy {
        FileHandle.standardError.write(Data("FAIL \(name): expected \(expected), got \(actual)\n".utf8))
        failures += 1
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
        failures += 1
    }
}

private func testZeroPoseMapsToOrigin() {
    let pose = PostureGaugeMapping.displayedPose(pitch: 0, roll: 0, isCalibrated: true)
    let point = PostureGaugeMapping.normalizedPoint(pitch: pose.pitch, roll: pose.roll)
    let euler = PostureGaugeMapping.bustEulerRadians(pitch: pose.pitch, roll: pose.roll)
    expectEqual(pose.pitch, 0, "zero pitch")
    expectEqual(pose.roll, 0, "zero roll")
    expectEqual(point.x, 0, "zero pip x")
    expectEqual(point.y, 0, "zero pip y")
    expectEqual(PostureGaugeMapping.washBankDegrees(roll: pose.roll), 0, "zero wash bank")
    expectEqual(euler.x, 0, "zero euler x")
    expectEqual(euler.y, 0, "zero euler y")
    expectEqual(euler.z, 0, "zero euler z")
}

private func testUncalibratedPoseIsForcedToZero() {
    let pose = PostureGaugeMapping.displayedPose(pitch: -12, roll: 8, isCalibrated: false)
    expectEqual(pose.pitch, 0, "uncalibrated pitch")
    expectEqual(pose.roll, 0, "uncalibrated roll")
}

private func testPitchVisualClampsToSpecEdges() {
    expectEqual(PostureGaugeMapping.pitchVisualDegrees(-30), -21, "pitch edge -30")
    expectEqual(PostureGaugeMapping.pitchVisualDegrees(20), 14, "pitch edge +20")
    expectEqual(PostureGaugeMapping.pitchVisualDegrees(-40), -21, "pitch clamp -40")
    expectEqual(PostureGaugeMapping.pitchVisualDegrees(30), 14, "pitch clamp +30")
}

private func testRollVisualClampsToSpecEdges() {
    expectEqual(PostureGaugeMapping.rollVisualDegrees(24), 10.8, "roll edge +24")
    expectEqual(PostureGaugeMapping.rollVisualDegrees(-24), -10.8, "roll edge -24")
    expectEqual(PostureGaugeMapping.rollVisualDegrees(40), 10.8, "roll clamp +40")
    expectEqual(PostureGaugeMapping.rollVisualDegrees(-40), -10.8, "roll clamp -40")
}

private func testChinDownProducesPositiveEulerX() {
    let euler = PostureGaugeMapping.bustEulerRadians(pitch: -10, roll: 0)
    expect(euler.x > 0, "chin-down eulerX > 0")
    expectEqual(euler.y, 0, "chin-down eulerY")
}

private func testPositiveRollMovesPipRightAndNegativeEulerZ() {
    let point = PostureGaugeMapping.normalizedPoint(pitch: 0, roll: 10)
    let euler = PostureGaugeMapping.bustEulerRadians(pitch: 0, roll: 10)
    expect(point.x > 0, "positive roll pip x > 0")
    expect(euler.z < 0, "positive roll eulerZ < 0")
}

private func testWashBankCapsAtEighteenDegrees() {
    expectEqual(
        PostureGaugeMapping.washBankDegrees(roll: PostureGaugeMapping.maxLean),
        18,
        "wash bank at maxLean"
    )
    expectEqual(PostureGaugeMapping.washBankDegrees(roll: 40), 18, "wash bank clamp +")
    expectEqual(PostureGaugeMapping.washBankDegrees(roll: -40), -18, "wash bank clamp -")
}

private func testWashYOffsetMatchesPipY() {
    let pitch = -12.0
    let point = PostureGaugeMapping.normalizedPoint(pitch: pitch, roll: 0)
    let expectedY = min(max(-pitch / PostureGaugeMapping.maxTilt, -1), 1)
    expectEqual(point.y, expectedY, "wash y matches pip y")
    expectEqual(point.x, 0, "wash y case pip x")
}

private func testBustPosePreservesMeasuredRotation() {
    let total = PostureGaugeMapping.bustEulerRadians(pitch: -18, roll: 9, yaw: 24)
    let pose = PostureGaugeMapping.bustPose(pitch: -18, roll: 9, yaw: 24)

    expectEqual(pose.neckEulerRadians.x + pose.headEulerRadians.x, total.x, "bust pitch distribution")
    expectEqual(pose.neckEulerRadians.y + pose.headEulerRadians.y, total.y, "bust yaw distribution")
    expectEqual(pose.neckEulerRadians.z + pose.headEulerRadians.z, total.z, "bust roll distribution")
    expect(
        abs(pose.headEulerRadians.x) > abs(pose.neckEulerRadians.x),
        "head leads cervical pitch"
    )
}

private func testForwardPitchCreatesNeckSlouch() {
    let pose = PostureGaugeMapping.bustPose(pitch: -30, roll: 0)
    expect(pose.neckOffset.z > 0, "slouch moves neck forward")
    expect(pose.headOffset.z > pose.neckOffset.z, "slouch moves head farther forward")
    expectEqual(pose.neckOffset.y, 0, "slouch does not compress neck vertically")
    expectEqual(pose.headOffset.y, 0, "slouch does not compress head vertically")
}

private func testUprightAndChinUpDoNotTranslateNeck() {
    for pitch in [0.0, 12.0] {
        let pose = PostureGaugeMapping.bustPose(pitch: pitch, roll: 10, yaw: 20)
        expectEqual(pose.neckOffset.y, 0, "non-slouch neck y at pitch \(pitch)")
        expectEqual(pose.neckOffset.z, 0, "non-slouch neck z at pitch \(pitch)")
        expectEqual(pose.headOffset.y, 0, "non-slouch head y at pitch \(pitch)")
        expectEqual(pose.headOffset.z, 0, "non-slouch head z at pitch \(pitch)")
    }
}

private func testWrappedDegreesDeltaHandlesWrap() {
    expectEqual(PostureGaugeMapping.wrappedDegreesDelta(current: 10, baseline: 0), 10, "plain +10")
    expectEqual(PostureGaugeMapping.wrappedDegreesDelta(current: -10, baseline: 0), -10, "plain -10")
    expectEqual(PostureGaugeMapping.wrappedDegreesDelta(current: -179, baseline: 179), 2, "wrap +179 to -179")
    expectEqual(PostureGaugeMapping.wrappedDegreesDelta(current: 179, baseline: -179), -2, "wrap -179 to +179")
    expectEqual(PostureGaugeMapping.wrappedDegreesDelta(current: 180, baseline: -180), 0, "±180 same heading")
}

private func testIsLookingAwayGate() {
    expect(
        PostureGaugeMapping.isLookingAway(yawDelta: 40, threshold: 35, enabled: true),
        "gate on past threshold"
    )
    expect(
        !PostureGaugeMapping.isLookingAway(yawDelta: 20, threshold: 35, enabled: true),
        "gate on under threshold"
    )
    expect(
        !PostureGaugeMapping.isLookingAway(yawDelta: 40, threshold: 35, enabled: false),
        "gate off ignores delta"
    )
    expect(
        PostureGaugeMapping.isLookingAway(yawDelta: -35, threshold: 35, enabled: true),
        "gate on at exact |threshold|"
    )
}

private func testYawVisualClampsAndPositiveYawFacesPadRight() {
    expectEqual(PostureGaugeMapping.yawVisualDegrees(40), 18, "yaw edge +40")
    expectEqual(PostureGaugeMapping.yawVisualDegrees(-40), -18, "yaw edge -40")
    expectEqual(PostureGaugeMapping.yawVisualDegrees(60), 18, "yaw clamp +60")
    expectEqual(PostureGaugeMapping.yawVisualDegrees(-60), -18, "yaw clamp -60")

    let euler = PostureGaugeMapping.bustEulerRadians(pitch: 0, roll: 0, yaw: 20)
    expect(euler.y < 0, "positive yaw eulerY < 0 (pad-right)")
    expectEqual(euler.x, 0, "yaw-only eulerX")
    expectEqual(euler.z, 0, "yaw-only eulerZ")

    let zeroYaw = PostureGaugeMapping.bustEulerRadians(pitch: -10, roll: 10, yaw: 0)
    let legacy = PostureGaugeMapping.bustEulerRadians(pitch: -10, roll: 10)
    expectEqual(zeroYaw.x, legacy.x, "yaw=0 keeps eulerX")
    expectEqual(zeroYaw.y, 0, "yaw=0 keeps eulerY 0")
    expectEqual(zeroYaw.z, legacy.z, "yaw=0 keeps eulerZ")
}

testZeroPoseMapsToOrigin()
testUncalibratedPoseIsForcedToZero()
testPitchVisualClampsToSpecEdges()
testRollVisualClampsToSpecEdges()
testChinDownProducesPositiveEulerX()
testPositiveRollMovesPipRightAndNegativeEulerZ()
testWashBankCapsAtEighteenDegrees()
testWashYOffsetMatchesPipY()
testBustPosePreservesMeasuredRotation()
testForwardPitchCreatesNeckSlouch()
testUprightAndChinUpDoNotTranslateNeck()
testWrappedDegreesDeltaHandlesWrap()
testIsLookingAwayGate()
testYawVisualClampsAndPositiveYawFacesPadRight()

if failures > 0 {
    FileHandle.standardError.write(Data("\(failures) mapping check(s) failed\n".utf8))
    exit(1)
}

print("AirPosture mapping checks passed")
