import AppKit
import Combine
import SwiftUI

@MainActor
final class WarningOverlayManager: ObservableObject {
    private let tracker: PostureTrackingManager
    private let settings: AirPostureSettings

    private var panels: [NSNumber: OverlayPanel] = [:]
    private var tickTimer: Timer?
    private var escapeMonitor: Any?
    private var slouchVisibleSince: Date?
    private var fadeStartedAt: Date?
    private var fadeFromStrength: Double = 0
    private var lastAppliedStrength: Double = 0
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    private enum Timing {
        static let tick: TimeInterval = 1.0 / 30.0
        static let rampDuration: TimeInterval = 8
        static let fadeDuration: TimeInterval = 0.350
        static let minVisibleFraction = 0.20
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

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldShow = settings.warningStyle != .off
            && !settings.isSnoozed
            && tracker.isSlouching

        if shouldShow {
            fadeStartedAt = nil
            if slouchVisibleSince == nil {
                slouchVisibleSince = Date()
            }
            let strength = currentShowStrength(reduceMotion: reduceMotion)
            lastAppliedStrength = strength
            ensurePanels()
            apply(strength: strength)
            installEscapeMonitorIfNeeded()
            return
        }

        slouchVisibleSince = nil

        guard !panels.isEmpty || lastAppliedStrength > 0 else {
            removeEscapeMonitor()
            return
        }

        if reduceMotion {
            hideImmediately()
            return
        }

        if fadeStartedAt == nil {
            fadeStartedAt = Date()
            fadeFromStrength = max(lastAppliedStrength, 0.01)
        }

        let elapsed = Date().timeIntervalSince(fadeStartedAt ?? Date())
        if elapsed >= Timing.fadeDuration {
            hideImmediately()
            return
        }

        let progress = elapsed / Timing.fadeDuration
        let strength = fadeFromStrength * (1 - progress)
        lastAppliedStrength = strength
        if !panels.isEmpty {
            apply(strength: strength, windowAlpha: 1 - progress)
        }
    }

    private func currentShowStrength(reduceMotion: Bool) -> Double {
        let maxStrength = settings.maxOverlayStrength
        if reduceMotion {
            return maxStrength
        }
        let elapsed = Date().timeIntervalSince(slouchVisibleSince ?? Date())
        let u = min(1, elapsed / Timing.rampDuration)
        let ramp = u * u * (3 - 2 * u)
        return (Timing.minVisibleFraction + (1 - Timing.minVisibleFraction) * ramp) * maxStrength
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
        hideImmediately()
    }

    private func apply(strength: Double, windowAlpha: CGFloat = 1) {
        let style = resolvedStyle()
        let tint = settings.overlayTint
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        for panel in panels.values {
            panel.alphaValue = windowAlpha
            panel.apply(
                style: style,
                tint: tint,
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

    private func hideImmediately() {
        fadeStartedAt = nil
        lastAppliedStrength = 0
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

    func apply(style: WarningStyle, tint: OverlayTint, strength: Double, increaseContrast: Bool) {
        rootView.apply(style: style, tint: tint, strength: strength, increaseContrast: increaseContrast)
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

    func apply(style: WarningStyle, tint: OverlayTint, strength: Double, increaseContrast: Bool) {
        var resolved = style
        if resolved == .blur && !blurMaterialAvailable {
            resolved = .dim
        }

        blurView.isHidden = resolved != .blur
        if resolved == .blur {
            _ = applyBlurMaterial()
        }

        drawView.style = resolved
        drawView.tint = tint
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
    var tint: OverlayTint = .warm
    var strength: Double = 0
    var increaseContrast: Bool = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
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
        let clear = tint.nsColor.withAlphaComponent(0).cgColor
        let edge = tint.nsColor.withAlphaComponent(edgeAlpha).cgColor
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
        var alpha = 0.45 + 0.45 * strength
        if increaseContrast {
            alpha = max(alpha, 0.75)
        }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: 16, yRadius: 16)
        path.lineWidth = 4 + 10 * strength
        tint.nsColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func drawDim(in rect: CGRect) {
        let alpha = clampedAlpha(0.10 + 0.28 * strength, glowOrDim: true)
        let color = tint.nsColor
        NSColor(
            srgbRed: color.srgbRed * 0.30,
            green: color.srgbGreen * 0.30,
            blue: color.srgbBlue * 0.30,
            alpha: alpha
        ).setFill()
        rect.fill()
    }

    private func drawBlurTint(in rect: CGRect) {
        tint.nsColor.withAlphaComponent(clampedAlpha(0.06 + 0.16 * strength, glowOrDim: true)).setFill()
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

private extension OverlayTint {
    var nsColor: NSColor {
        switch self {
        case .warm:
            NSColor(srgbRed: 1.00, green: 0.62, blue: 0.11, alpha: 1)
        case .cool:
            NSColor(srgbRed: 0.18, green: 0.70, blue: 0.68, alpha: 1)
        case .alert:
            NSColor(srgbRed: 0.91, green: 0.22, blue: 0.21, alpha: 1)
        }
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
