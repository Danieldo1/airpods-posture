import AppKit
import Combine
import SwiftUI
#if SWIFT_PACKAGE
import AirPostureCore
#endif

@MainActor
final class WarningOverlayManager: ObservableObject {
    private let tracker: PostureTrackingManager
    private let settings: AirPostureSettings

    private var panels: [NSNumber: OverlayPanel] = [:]
    private var tickTimer: Timer?
    private var escapeMonitor: Any?
    private var presentationState = WarningPresentationState()
    private var lastTickAt: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    private enum Timing {
        static let tick: TimeInterval = 1.0 / 30.0
    }

    init(tracker: PostureTrackingManager, settings: AirPostureSettings) {
        self.tracker = tracker
        self.settings = settings
        start()
    }

    deinit {
        tickTimer?.invalidate()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
            workspace.removeObserver(observer)
        }
    }

    private func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: Timing.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildPanels()
                    self?.tick()
                }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
        )

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.tick()
                }
            }
            .store(in: &cancellables)

        tracker.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.tick()
                }
            }
            .store(in: &cancellables)

        tick()
    }

    private func tick() {
        settings.clearExpiredSnooze()

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastTickAt.map { max(now - $0, 0) } ?? 0
        lastTickAt = now
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let isEligible = settings.warningStyle != .off
            && !settings.isSnoozed
            && tracker.isTrackingEnabled
            && tracker.connectionStatus == .connected
            && tracker.isCalibrated
            && !tracker.didJustCalibrate
            && !tracker.isLookingAway

        guard isEligible else {
            _ = presentationState.update(
                target: 0,
                elapsed: elapsed,
                fadeIn: settings.overlayFadeInSeconds,
                reduceMotion: reduceMotion,
                isEligible: isEligible,
                referenceID: tracker.activePreset.rawValue
            )
            lastTickAt = nil
            hidePanels()
            return
        }

        let target = WarningIntensity.target(
            deviation: tracker.normalizedDeviation,
            graceProgress: tracker.slouchProgressClamped,
            isSlouching: tracker.isSlouching,
            earlyEnabled: settings.earlyCueEnabled,
            onset: settings.cueStartFraction
        )
        let fraction = presentationState.update(
            target: target,
            elapsed: elapsed,
            fadeIn: settings.overlayFadeInSeconds,
            reduceMotion: reduceMotion,
            isEligible: true,
            referenceID: tracker.activePreset.rawValue
        )
        let strength = fraction * settings.maxOverlayStrength

        guard strength > 0 else {
            hidePanels()
            return
        }

        ensurePanels()
        apply(strength: strength)
        installEscapeMonitorIfNeeded()
    }

    private func ensurePanels() {
        let screens = NSScreen.screens
        let ids = Set(screens.compactMap(\.screenNumber))
        for key in panels.keys where !ids.contains(key) {
            panels[key]?.orderOut(nil)
            panels[key]?.close()
            panels.removeValue(forKey: key)
        }

        for screen in screens {
            guard let id = screen.screenNumber else { continue }
            if let existing = panels[id] {
                existing.setFrame(screen.frame, display: true)
                continue
            }
            guard let panel = OverlayPanel.make(on: screen) else { continue }
            panels[id] = panel
        }
    }

    private func rebuildPanels() {
        cancelImmediately()
    }

    private func apply(strength: Double) {
        let style = resolvedStyle()
        let color = settings.overlayColor
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        for panel in panels.values {
            panel.alphaValue = 1
            panel.apply(
                style: style,
                color: color,
                strength: strength,
                increaseContrast: increaseContrast
            )
            if panel.isVisible == false {
                panel.orderFrontRegardless()
            }
        }
    }

    private func resolvedStyle() -> WarningStyle {
        let style = settings.warningStyle
        if style == .off { return .off }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
           style == .glow || style == .blur {
            return .dim
        }
        return style
    }

    private func cancelImmediately() {
        presentationState.reset()
        lastTickAt = nil
        hidePanels()
    }

    private func hidePanels() {
        for panel in panels.values {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        removeEscapeMonitor()
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.settings.snooze(minutes: 15)
            }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

private final class OverlayPanel: NSPanel {
    private let rootView = OverlayRootView()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make(on screen: NSScreen) -> OverlayPanel? {
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.setAccessibilityElement(false)
        panel.setAccessibilityHidden(true)
        panel.contentView = panel.rootView
        panel.rootView.setAccessibilityElement(false)
        panel.rootView.setAccessibilityHidden(true)
        panel.setFrame(screen.frame, display: true)
        return panel
    }

    func apply(style: WarningStyle, color: OverlayColor, strength: Double, increaseContrast: Bool) {
        rootView.apply(style: style, color: color, strength: strength, increaseContrast: increaseContrast)
    }
}

private final class OverlayRootView: NSView {
    private let blurView = NSVisualEffectView()
    private let drawView = OverlayDrawView()
    private var blurMaterialAvailable = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        if !applyBlurMaterial() {
            blurMaterialAvailable = false
        }
        blurView.isHidden = true
        blurView.setAccessibilityElement(false)

        drawView.autoresizingMask = [.width, .height]
        drawView.setAccessibilityElement(false)

        addSubview(blurView)
        addSubview(drawView)
        blurView.frame = bounds
        drawView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    func apply(style: WarningStyle, color: OverlayColor, strength: Double, increaseContrast: Bool) {
        var resolved = style
        if resolved == .blur && !blurMaterialAvailable {
            resolved = .dim
        }

        let strength = min(max(strength, 0), 1)
        blurView.isHidden = resolved != .blur || strength == 0
        blurView.alphaValue = resolved == .blur ? strength : 0
        if resolved == .blur {
            _ = applyBlurMaterial()
        }

        drawView.style = resolved
        drawView.color = color
        drawView.strength = strength
        drawView.increaseContrast = increaseContrast
        drawView.needsDisplay = true
    }

    private func applyBlurMaterial() -> Bool {
        blurView.material = .fullScreenUI
        return true
    }
}

private final class OverlayDrawView: NSView {
    var style: WarningStyle = .glow
    var color: OverlayColor = .warm
    var strength: Double = 0
    var increaseContrast: Bool = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard strength > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        switch style {
        case .glow:
            drawGlow(in: rect, context: context)
        case .border:
            drawBorder(in: rect)
        case .dim:
            drawDim(in: rect)
        case .blur:
            drawBlurTint(in: rect)
        case .off:
            break
        }
    }

    private func drawGlow(in rect: CGRect, context: CGContext) {
        let edgeAlpha = clampedAlpha(0.55 * strength, glowOrDim: true)
        let innerRadius = min(rect.width, rect.height) * 0.55 * 0.5
        let maxRadius = hypot(rect.width, rect.height) / 2
        guard maxRadius > 0 else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let clear = color.nsColor.withAlphaComponent(0).cgColor
        let edge = color.nsColor.withAlphaComponent(edgeAlpha).cgColor
        let colors = [clear, clear, edge] as CFArray
        let innerStop = min(max(innerRadius / maxRadius, 0.01), 0.98)
        let locations: [CGFloat] = [0, innerStop, 1]
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: maxRadius,
            options: [.drawsAfterEndLocation]
        )
    }

    private func drawBorder(in rect: CGRect) {
        var alpha = 0.90 * strength
        if increaseContrast {
            alpha *= 1.15
        }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: 16, yRadius: 16)
        path.lineWidth = 2 + 12 * strength
        color.nsColor.withAlphaComponent(min(alpha, 1)).setStroke()
        path.stroke()
    }

    private func drawDim(in rect: CGRect) {
        let alpha = clampedAlpha(0.38 * strength, glowOrDim: true)
        let color = color.nsColor
        NSColor(
            srgbRed: color.srgbRed * 0.30,
            green: color.srgbGreen * 0.30,
            blue: color.srgbBlue * 0.30,
            alpha: alpha
        ).setFill()
        rect.fill()
    }

    private func drawBlurTint(in rect: CGRect) {
        color.nsColor.withAlphaComponent(clampedAlpha(0.22 * strength, glowOrDim: true)).setFill()
        rect.fill()
    }

    private func clampedAlpha(_ value: Double, glowOrDim: Bool) -> Double {
        var alpha = value
        if glowOrDim && increaseContrast {
            alpha *= 1.15
        }
        return min(max(alpha, 0), 1)
    }
}

private extension OverlayColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

private extension NSColor {
    var srgbRed: CGFloat { srgbComponents.red }
    var srgbGreen: CGFloat { srgbComponents.green }
    var srgbBlue: CGFloat { srgbComponents.blue }

    var srgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard let converted = usingColorSpace(.sRGB) else {
            return (redComponent, greenComponent, blueComponent, alphaComponent)
        }
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }
}

private extension NSScreen {
    var screenNumber: NSNumber? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}
