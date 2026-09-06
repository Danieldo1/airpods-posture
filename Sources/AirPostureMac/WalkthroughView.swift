import SwiftUI
#if SWIFT_PACKAGE
import AirPostureCore
#endif

struct WalkthroughView: View {
    @Binding var step: WalkthroughStep
    let connectionTitle: String
    let authorizationDenied: Bool
    let canCalibrate: Bool
    let didJustCalibrate: Bool
    let onCalibrate: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void

    var body: some View {
        let page = Walkthrough.page(for: step)
        VStack(alignment: .leading, spacing: 16) {
            Text(Walkthrough.progressText(step))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Walkthrough.accessibilityProgress(step))

            Text(page.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(page.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if page.showsConnectionStatus {
                HStack {
                    Text("Headphones")
                    Spacer()
                    Text(connectionTitle)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Headphones, \(connectionTitle)")
            }

            if page.showsMotionDeniedHint, authorizationDenied {
                Text("Motion access is off. Enable it in System Settings → Privacy & Security → Motion & Fitness.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if page.showsCalibrateControl {
                Button(action: onCalibrate) {
                    Label(
                        didJustCalibrate ? "Neutral Posture Saved" : "Set Neutral Posture",
                        systemImage: didJustCalibrate ? "checkmark.circle.fill" : "scope"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCalibrate)
                .keyboardShortcut("k", modifiers: [.command])
            }

            Spacer(minLength: 12)

            HStack {
                if page.showsSkip {
                    Button("Skip", action: onSkip)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if page.showsBack {
                    Button("Back") {
                        if let previous = Walkthrough.back(step) {
                            step = previous
                        }
                    }
                }
                Button(page.primaryTitle) {
                    if let next = Walkthrough.advance(step) {
                        step = next
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(width: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How AirPosture works")
    }
}
