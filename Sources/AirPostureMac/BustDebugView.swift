#if DEBUG
#if SWIFT_PACKAGE
import AirPostureCore
#endif
import SwiftUI

/// Compiled out of release builds. The launch flag also keeps diagnostics and
/// their main-queue updates disabled in ordinary debug runs.
final class BustDebugState: ObservableObject {
    static let isEnabled = ProcessInfo.processInfo.environment["AIRPOSTURE_BUST_DEBUG"] == "1"
    @Published var config = BustAnimationConfig()
    let readout = BustDebugReadoutState()
}

final class BustDebugReadoutState: ObservableObject {
    @Published var snapshot: BustDebugSnapshot?
}

struct BustDebugSnapshot {
    let input: BustTrackingPose
    let output: BustAnimationOutput
    let boneText: String
}

struct BustDebugView: View {
    @ObservedObject var state: BustDebugState
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .padding(7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Avatar animation tuning")
        .help("Avatar animation tuning")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Avatar tuning").font(.headline)
                        Spacer()
                        Button("Reset") { state.config = BustAnimationConfig() }
                            .controlSize(.small)
                    }
                    Text("Body and arm motion is inferred.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    slider("Yaw", \.yawMultiplier, in: 0.5...2.5, suffix: "×")
                    slider("Pitch", \.pitchMultiplier, in: 0.5...2.5, suffix: "×")
                    slider("Roll", \.rollMultiplier, in: 0.5...2.5, suffix: "×")
                    Divider()
                    slider("Chest", \.chestInfluence, in: 0...0.4)
                    slider("Shoulders", \.shoulderInfluence, in: 0...1)
                    slider("Neck share", \.neckShare, in: 0.15...0.5)
                    Divider()
                    slider("Response", \.responseSeconds, in: 0.04...0.3, suffix: "s")
                    slider("Settling", \.settlingSeconds, in: 0.1...0.6, suffix: "s")
                    slider("Dead zone", \.deadZoneDegrees, in: 0...1, suffix: "°")
                    slider("Hysteresis", \.hysteresisDegrees, in: 0...0.5, suffix: "°")
                    slider("Idle", \.idleIntensity, in: 0...2, suffix: "×")
                    slider("Gestures", \.gestureIntensity, in: 0...2, suffix: "×")
                    Divider()
                    BustDebugReadoutView(state: state.readout)
                }
                .padding(16)
            }
            .frame(width: 350, height: 620)
        }
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<BustAnimationConfig, Double>,
                        in range: ClosedRange<Double>, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 76, alignment: .leading)
            Slider(value: Binding(
                get: { state.config[keyPath: keyPath] },
                set: { state.config[keyPath: keyPath] = $0 }
            ), in: range)
            .accessibilityLabel(title)
            Text(String(format: "%.2f%@", state.config[keyPath: keyPath], suffix))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption)
    }
}

private struct BustDebugReadoutView: View {
    @ObservedObject var state: BustDebugReadoutState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Pose readout · 5 Hz").font(.caption.weight(.semibold))
            if let snapshot = state.snapshot {
                Text("Degrees: pitch / roll / yaw")
                    .foregroundStyle(.secondary)
                Text(poseLine("Tracker", snapshot.input))
                Text(poseLine("Processed", snapshot.output.processedPose))
                Text("Expression: \(String(describing: snapshot.output.processedPose.expression))")
                Text("Final joint-local XYZ degrees")
                    .foregroundStyle(.secondary)
                Text(snapshot.boneText)
                Text(String(format: "Brow lift L/R: %+.3f / %+.3f",
                            snapshot.output.leftBrowHeight, snapshot.output.rightBrowHeight))
                Text(String(format: "Eyes %.2f · smile %.2f · frown %.2f",
                            snapshot.output.eyeOpenness, snapshot.output.smileWeight, snapshot.output.frownWeight))
            } else {
                Text("Waiting for a visible avatar.").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func poseLine(_ title: String, _ pose: BustTrackingPose) -> String {
        String(format: "%@: %+.1f / %+.1f / %+.1f", title, pose.pitch, pose.roll, pose.yaw)
    }
}
#endif
