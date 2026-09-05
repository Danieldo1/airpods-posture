import SwiftUI

#if SWIFT_PACKAGE
    import AirPostureCore
#endif

struct PostureGaugeView: View {
    let pitchDelta: Double
    let rollDelta: Double
    let yawDelta: Double
    let tiltThreshold: Double
    let leanThreshold: Double
    let dominantAxis: DominantAxis
    let band: PostureBand
    let slouchProgress: Double
    let isCalibrated: Bool
    let caption: String
    let isLookingAway: Bool
    let showTurnValue: Bool
    let showHeadTurn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trail: [TrailSample] = []

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                AttitudePad(
                    pitchDelta: displayedPose.pitch,
                    rollDelta: displayedPose.roll,
                    tiltThreshold: tiltThreshold,
                    leanThreshold: leanThreshold,
                    band: band,
                    isCalibrated: isCalibrated,
                    trail: reduceMotion ? [] : trail
                )
                .frame(height: 188)

                InstrumentBustView(
                    pitch: displayedPose.pitch,
                    roll: displayedPose.roll,
                    yaw: showHeadTurn ? displayedYaw : 0,
                    band: band
                )
                .frame(height: 188)
            }

            CoachChip(
                caption: caption,
                dominantAxis: dominantAxis,
                pitchDelta: displayedPose.pitch,
                rollDelta: displayedPose.roll,
                yawDelta: displayedYaw,
                isCalibrated: isCalibrated,
                isLookingAway: isLookingAway,
                showTurnValue: showTurnValue
            )
            .accessibilityHidden(true)

            ProgressView(value: slouchProgress)
                .progressViewStyle(.linear)
                .tint(statusColor)
                .opacity(showsGraceProgress ? 1 : 0)
                .frame(height: 6)
                .accessibilityHidden(!showsGraceProgress)
                .accessibilityLabel("Time off neutral posture")
                .accessibilityValue(Text("\(Int(slouchProgress * 100)) percent of grace period"))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Head posture")
        .accessibilityValue(Text(accessibilityValue))
        .task {
            while !Task.isCancelled {
                handleTrailTick()
                try? await Task.sleep(for: .milliseconds(125))
            }
        }
        .onChange(of: isCalibrated) { _, calibrated in
            if !calibrated {
                trail.removeAll()
            }
        }
    }

    private var displayedPose: (pitch: Double, roll: Double) {
        PostureGaugeMapping.displayedPose(
            pitch: pitchDelta,
            roll: rollDelta,
            isCalibrated: isCalibrated
        )
    }

    private var displayedYaw: Double {
        isCalibrated ? yawDelta : 0
    }

    private var showsGraceProgress: Bool {
        band == .leaning || band == .slouching
    }

    private var statusColor: Color {
        switch band {
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
        if !isCalibrated {
            return caption
        }
        var parts = [
            caption,
            "Tilt \(PostureFormatting.signedDegrees(displayedPose.pitch))",
            "Lean \(PostureFormatting.signedDegrees(displayedPose.roll))"
        ]
        if showTurnValue {
            parts.append("Turn \(PostureFormatting.signedDegrees(displayedYaw))")
        }
        return parts.joined(separator: ", ")
    }

    private func handleTrailTick() {
        guard isCalibrated, !reduceMotion else {
            if !trail.isEmpty {
                trail.removeAll()
            }
            return
        }
        trail.append(TrailSample(pitch: displayedPose.pitch, roll: displayedPose.roll))
        if trail.count > 8 {
            trail.removeFirst(trail.count - 8)
        }
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

private struct TrailSample: Equatable {
    var pitch: Double
    var roll: Double
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

private struct AttitudePad: View {
    let pitchDelta: Double
    let rollDelta: Double
    let tiltThreshold: Double
    let leanThreshold: Double
    let band: PostureBand
    let isCalibrated: Bool
    let trail: [TrailSample]

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            let rect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            let center = CGPoint(x: rect.midX, y: rect.midY)

            let frame = Path(roundedRect: rect, cornerRadius: 16)
            context.fill(frame, with: .color(.primary.opacity(0.04)))
            context.stroke(frame, with: .color(.primary.opacity(0.08)), lineWidth: 1)

            context.drawLayer { layer in
                layer.clip(to: frame)
                drawWash(in: &layer, size: size, rect: rect, center: center)
            }

            var cross = Path()
            cross.move(to: CGPoint(x: rect.minX + 10, y: center.y))
            cross.addLine(to: CGPoint(x: rect.maxX - 10, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: rect.minY + 10))
            cross.addLine(to: CGPoint(x: center.x, y: rect.maxY - 10))
            context.stroke(
                cross, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            let ellipseRect = thresholdRect(in: rect)
            if !reduceTransparency {
                context.stroke(
                    Path(ellipseIn: ellipseRect.insetBy(dx: -3, dy: -3)),
                    with: .color(ellipseColor.opacity(0.22)),
                    lineWidth: 6
                )
            }
            context.stroke(
                Path(ellipseIn: ellipseRect),
                with: .color(ellipseColor),
                lineWidth: 2
            )

            for (index, sample) in trail.enumerated() {
                let t = trail.count <= 1 ? 0 : Double(index) / Double(trail.count - 1)
                let diameter = 10 - 6 * t
                let opacity = 0.35 - 0.30 * t
                let point = markerPoint(pitch: sample.pitch, roll: sample.roll, in: rect)
                let markerRect = CGRect(
                    x: point.x - diameter / 2,
                    y: point.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: markerRect), with: .color(fillColor.opacity(opacity)))
            }

            let marker = markerPoint(pitch: pitchDelta, roll: rollDelta, in: rect)
            let markerRect = CGRect(x: marker.x - 7, y: marker.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: markerRect), with: .color(fillColor))
            context.stroke(
                Path(ellipseIn: markerRect.insetBy(dx: -1.5, dy: -1.5)),
                with: .color(.white.opacity(0.85)),
                lineWidth: 2
            )
        }
    }

    private func drawWash(
        in context: inout GraphicsContext,
        size: CGSize,
        rect: CGRect,
        center: CGPoint
    ) {
        let point = PostureGaugeMapping.normalizedPoint(pitch: pitchDelta, roll: rollDelta)
        let travelY = CGFloat(point.y) * (rect.height / 2 - 14)
        let bank = Angle.degrees(PostureGaugeMapping.washBankDegrees(roll: rollDelta))

        context.translateBy(x: center.x, y: center.y + travelY)
        context.rotate(by: bank)

        let washHeight = size.height * 3
        let washWidth = size.width * 2
        let washRect = CGRect(
            x: -washWidth / 2,
            y: -washHeight / 2,
            width: washWidth,
            height: washHeight
        )
        context.fill(
            Path(washRect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.46, green: 0.52, blue: 0.60).opacity(0.15),
                    Color(red: 0.58, green: 0.50, blue: 0.42).opacity(0.15)
                ]),
                startPoint: CGPoint(x: 0, y: washRect.minY),
                endPoint: CGPoint(x: 0, y: washRect.maxY)
            )
        )
    }

    private var fillColor: Color {
        switch band {
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

    private var ellipseColor: Color {
        if !isCalibrated {
            return Color.secondary
        }
        switch band {
        case .upright:
            return Color.green
        case .leaning:
            return Color.orange
        case .slouching:
            return Color.red
        case .paused, .uncalibrated, .waitingForHeadphones:
            return Color.secondary
        }
    }

    private func markerPoint(pitch: Double, roll: Double, in rect: CGRect) -> CGPoint {
        let point = PostureGaugeMapping.normalizedPoint(pitch: pitch, roll: roll)
        return CGPoint(
            x: rect.midX + CGFloat(point.x) * (rect.width / 2 - 14),
            y: rect.midY + CGFloat(point.y) * (rect.height / 2 - 14)
        )
    }

    private func thresholdRect(in rect: CGRect) -> CGRect {
        let xRadius =
            CGFloat(min(leanThreshold / PostureGaugeMapping.maxLean, 1)) * (rect.width / 2 - 14)
        let yRadius =
            CGFloat(min(tiltThreshold / PostureGaugeMapping.maxTilt, 1)) * (rect.height / 2 - 14)
        return CGRect(
            x: rect.midX - xRadius,
            y: rect.midY - yRadius,
            width: xRadius * 2,
            height: yRadius * 2
        )
    }
}
