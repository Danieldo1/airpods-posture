import AppKit
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var tracker: PostureTrackingManager
    @ObservedObject var settings: AirPostureSettings
    @ObservedObject var breakClock: BreakReminderClock

    var body: some View {
        Image(nsImage: Self.makeImage(tracker: tracker, family: settings.iconFamily))
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let remaining = breakClock.isEnabled ? ", break in \(breakClock.accessibilityRemaining)" : ""
        return postureAccessibilityLabel + remaining
    }

    private var postureAccessibilityLabel: String {
        switch tracker.postureBand {
        case .slouching:
            tracker.dominantAxis == .tilt ? "AirPosture, slouching" : "AirPosture, off center"
        case .leaning:
            tracker.dominantAxis == .tilt ? "AirPosture, tilting forward" : "AirPosture, leaning aside"
        case .upright:
            "AirPosture, upright"
        case .paused:
            "AirPosture, paused"
        case .uncalibrated:
            "AirPosture, not calibrated"
        case .waitingForHeadphones:
            "AirPosture, \(tracker.connectionStatus.title.lowercased())"
        }
    }

    private static func makeImage(tracker: PostureTrackingManager, family: IconFamily) -> NSImage {
        if tracker.connectionStatus == .disconnected {
            return render(symbolName: "airpodspro", tint: .systemGray, isTemplate: false)
        }

        let appearance = appearance(for: tracker, family: family)
        return render(
            symbolName: appearance.symbolName,
            tint: appearance.tint,
            isTemplate: appearance.isTemplate,
            rotationDegrees: appearance.rotationDegrees,
            xOffset: appearance.xOffset
        )
    }

    private static func appearance(
        for tracker: PostureTrackingManager,
        family: IconFamily
    ) -> (symbolName: String, tint: NSColor?, isTemplate: Bool, rotationDegrees: CGFloat, xOffset: CGFloat) {
        let leanHint = tracker.dominantAxis == .lean
            && (tracker.postureBand == .leaning || tracker.postureBand == .slouching)
        let leanSign: CGFloat = {
            if tracker.rollDeltaDegrees > 0 { return 1 }
            if tracker.rollDeltaDegrees < 0 { return -1 }
            return 0
        }()
        let rotation: CGFloat = (family == .horizonCross && leanHint) ? leanSign * 12 : 0
        let xOffset: CGFloat = (family == .minimalDot && leanHint) ? leanSign * 2 : 0

        switch tracker.postureBand {
        case .slouching:
            return (family.slouchSymbol, .systemRed, false, rotation, xOffset)
        case .leaning:
            return (family.warningSymbol, .systemOrange, false, rotation, xOffset)
        case .upright:
            return (family.uprightSymbol, nil, true, 0, 0)
        case .paused, .uncalibrated, .waitingForHeadphones:
            return (family.idleSymbol, nil, true, 0, 0)
        }
    }

    private static func render(
        symbolName: String,
        tint: NSColor?,
        isTemplate: Bool,
        rotationDegrees: CGFloat = 0,
        xOffset: CGFloat = 0
    ) -> NSImage {
        let canvas = NSSize(width: 22, height: 18)
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AirPosture")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirPosture")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let configured = base.withSymbolConfiguration(configuration) ?? base

        let rendered = NSImage(size: canvas)
        rendered.lockFocus()
        let symbolSize = configured.size
        let origin = NSPoint(
            x: (canvas.width - symbolSize.width) / 2,
            y: (canvas.height - symbolSize.height) / 2
        )
        let transform = NSAffineTransform()
        transform.translateX(by: canvas.width / 2 + xOffset, yBy: canvas.height / 2)
        transform.rotate(byDegrees: rotationDegrees)
        transform.translateX(by: -canvas.width / 2, yBy: -canvas.height / 2)
        transform.concat()
        configured.draw(in: NSRect(origin: origin, size: symbolSize))
        if let tint, !isTemplate {
            tint.set()
            NSRect(origin: .zero, size: canvas).fill(using: .sourceAtop)
        }
        rendered.unlockFocus()
        rendered.isTemplate = isTemplate
        return rendered
    }
}

private extension IconFamily {
    var idleSymbol: String {
        switch self {
        case .postureFigure: "airpodspro"
        case .horizonCross: "plus"
        case .minimalDot: "circle"
        }
    }

    var uprightSymbol: String {
        switch self {
        case .postureFigure: "figure.stand"
        case .horizonCross: "plus"
        case .minimalDot: "circle.fill"
        }
    }

    var warningSymbol: String {
        switch self {
        case .postureFigure: "figure.seated.side"
        case .horizonCross: "plus"
        case .minimalDot: "circle.fill"
        }
    }

    var slouchSymbol: String {
        warningSymbol
    }
}
