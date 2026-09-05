import SwiftUI

struct PostureGaugeView: View {
    let pitchDelta: Double
    let rollDelta: Double
    let tiltThreshold: Double
    let leanThreshold: Double
    let dominantAxis: DominantAxis
    let band: PostureBand
    let slouchProgress: Double
    let isCalibrated: Bool
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trail: [TrailSample] = []

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                AttitudePad(
                    pitchDelta: displayedPitch,
                    rollDelta: displayedRoll,
                    tiltThreshold: tiltThreshold,
                    leanThreshold: leanThreshold,
                    band: band,
                    isCalibrated: isCalibrated,
                    trail: reduceMotion ? [] : trail
                )
                .frame(height: 188)

                Image(systemName: figureName)
                    .font(.system(size: 30, weight: .medium))
                    .rotationEffect(.degrees(figurePitch))
                    .rotation3DEffect(.degrees(figureRoll), axis: (x: 0, y: 0, z: 1))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                    .offset(y: -2)
            }

            CoachChip(
                caption: caption,
                dominantAxis: dominantAxis,
                pitchDelta: displayedPitch,
                rollDelta: displayedRoll,
                isCalibrated: isCalibrated
            )
            .accessibilityHidden(true)

            if band == .leaning || band == .slouching {
                ProgressView(value: slouchProgress)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .accessibilityLabel("Time off neutral posture")
                    .accessibilityValue(Text("\(Int(slouchProgress * 100)) percent of grace period"))
            }
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

    private var displayedPitch: Double {
        isCalibrated ? pitchDelta : 0
    }

    private var displayedRoll: Double {
        isCalibrated ? rollDelta : 0
    }

    private var figureName: String {
        switch band {
        case .slouching, .leaning:
            "figure.seated.side"
        default:
            "figure.stand"
        }
    }

    private var figurePitch: Double {
        min(max(displayedPitch, -28), 16) * 0.55
    }

    private var figureRoll: Double {
        min(max(displayedRoll, -24), 24) * 0.45
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
        return "\(caption), Tilt \(PostureFormatting.signedDegrees(displayedPitch)), Lean \(PostureFormatting.signedDegrees(displayedRoll))"
    }

    private func handleTrailTick() {
        guard isCalibrated, !reduceMotion else {
            if !trail.isEmpty {
                trail.removeAll()
            }
            return
        }
        trail.append(TrailSample(pitch: displayedPitch, roll: displayedRoll))
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
    let isCalibrated: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isCalibrated {
                Text(dominantAxis.title)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isCalibrated {
                Text("Tilt \(PostureFormatting.signedDegrees(pitchDelta))")
                    .foregroundStyle(dominantAxis == .tilt ? .primary : .secondary)
                Text("Lean \(PostureFormatting.signedDegrees(rollDelta))")
                    .foregroundStyle(dominantAxis == .lean ? .primary : .secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: Capsule())
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

    private let maxTilt = 30.0
    private let maxLean = 20.0

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

            var cross = Path()
            cross.move(to: CGPoint(x: rect.minX + 10, y: center.y))
            cross.addLine(to: CGPoint(x: rect.maxX - 10, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: rect.minY + 10))
            cross.addLine(to: CGPoint(x: center.x, y: rect.maxY - 10))
            context.stroke(cross, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            if isCalibrated {
                let ellipseRect = thresholdRect(in: rect)
                context.stroke(
                    Path(ellipseIn: ellipseRect),
                    with: .color(ellipseColor),
                    lineWidth: 2
                )
            }

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
        switch band {
        case .upright:
            Color.green
        case .leaning:
            Color.orange
        case .slouching:
            Color.red
        case .paused, .uncalibrated, .waitingForHeadphones:
            Color.secondary
        }
    }

    private func markerPoint(pitch: Double, roll: Double, in rect: CGRect) -> CGPoint {
        let x = CGFloat(min(max(roll / maxLean, -1), 1))
        let y = CGFloat(min(max(-pitch / maxTilt, -1), 1))
        return CGPoint(
            x: rect.midX + x * (rect.width / 2 - 14),
            y: rect.midY + y * (rect.height / 2 - 14)
        )
    }

    private func thresholdRect(in rect: CGRect) -> CGRect {
        let xRadius = CGFloat(min(leanThreshold / maxLean, 1)) * (rect.width / 2 - 14)
        let yRadius = CGFloat(min(tiltThreshold / maxTilt, 1)) * (rect.height / 2 - 14)
        return CGRect(
            x: rect.midX - xRadius,
            y: rect.midY - yRadius,
            width: xRadius * 2,
            height: yRadius * 2
        )
    }
}
