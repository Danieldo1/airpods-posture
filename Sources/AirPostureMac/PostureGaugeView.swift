import SwiftUI

#if SWIFT_PACKAGE
    import AirPostureCore
#endif

struct PostureGaugeView: View {
    @ObservedObject var readings: LivePostureReadings
    let showTurnValue: Bool
    let showHeadTurn: Bool

    private var snapshot: LivePostureSnapshot { readings.snapshot }

    var body: some View {
        VStack(spacing: 12) {
            InstrumentBustView(
                pitch: displayedPose.pitch,
                roll: displayedPose.roll,
                yaw: showHeadTurn ? displayedYaw : 0,
                band: snapshot.band
            )
            .frame(maxWidth: .infinity)
            .frame(height: 188)

            CoachChip(
                caption: snapshot.caption,
                dominantAxis: snapshot.dominantAxis,
                pitchDelta: displayedPose.pitch,
                rollDelta: displayedPose.roll,
                yawDelta: displayedYaw,
                isCalibrated: snapshot.isCalibrated,
                isLookingAway: snapshot.isLookingAway,
                showTurnValue: showTurnValue
            )
            .accessibilityHidden(true)

            ProgressView(value: snapshot.slouchProgress)
                .progressViewStyle(.linear)
                .tint(statusColor)
                .opacity(showsGraceProgress ? 1 : 0)
                .frame(height: 6)
                .accessibilityHidden(!showsGraceProgress)
                .accessibilityLabel("Time off neutral posture")
                .accessibilityValue(Text("\(Int(snapshot.slouchProgress * 100)) percent of grace period"))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Head posture")
        .accessibilityValue(Text(accessibilityValue))
    }

    private var displayedPose: (pitch: Double, roll: Double) {
        PostureGaugeMapping.displayedPose(
            pitch: snapshot.pitchDeltaDegrees,
            roll: snapshot.rollDeltaDegrees,
            isCalibrated: snapshot.isCalibrated
        )
    }

    private var displayedYaw: Double {
        snapshot.isCalibrated ? snapshot.yawDeltaDegrees : 0
    }

    private var showsGraceProgress: Bool {
        snapshot.band == .leaning || snapshot.band == .slouching
    }

    private var statusColor: Color {
        switch snapshot.band {
        case .slouching:
            Color.red
        case .leaning:
            Color.orange
        case .upright:
            Color.green
        case .paused, .uncalibrated, .waitingForHeadphones:
            Color.secondary
        }
    }

    private var accessibilityValue: String {
        if !snapshot.isCalibrated {
            return snapshot.caption
        }
        var parts = [
            snapshot.caption,
            "Tilt \(PostureFormatting.signedDegrees(displayedPose.pitch))",
            "Lean \(PostureFormatting.signedDegrees(displayedPose.roll))"
        ]
        if showTurnValue {
            parts.append("Turn \(PostureFormatting.signedDegrees(displayedYaw))")
        }
        return parts.joined(separator: ", ")
    }
}

enum PostureFormatting {
    static func signedDegrees(_ value: Double) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(1)))
        if value > 0.05 {
            return "+\(magnitude)°"
        }
        if value < -0.05 {
            return "−\(magnitude)°"
        }
        return "\(abs(value).formatted(.number.precision(.fractionLength(1))))°"
    }
}

private struct CoachChip: View {
    let caption: String
    let dominantAxis: DominantAxis
    let pitchDelta: Double
    let rollDelta: Double
    let yawDelta: Double
    let isCalibrated: Bool
    let isLookingAway: Bool
    let showTurnValue: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isCalibrated {
                Text(isLookingAway ? "Turn" : dominantAxis.title)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isCalibrated {
                Text("Tilt \(PostureFormatting.signedDegrees(pitchDelta))")
                    .foregroundStyle(emphasizeTilt ? .primary : .secondary)
                Text("Lean \(PostureFormatting.signedDegrees(rollDelta))")
                    .foregroundStyle(emphasizeLean ? .primary : .secondary)
                if showTurnValue {
                    Text("Turn \(PostureFormatting.signedDegrees(yawDelta))")
                        .foregroundStyle(emphasizeTurn ? .primary : .secondary)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: Capsule())
    }

    private var emphasizeTilt: Bool {
        !isLookingAway && dominantAxis == .tilt
    }

    private var emphasizeLean: Bool {
        !isLookingAway && dominantAxis == .lean
    }

    private var emphasizeTurn: Bool {
        isLookingAway
    }
}
