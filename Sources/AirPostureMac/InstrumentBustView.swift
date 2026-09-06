#if SWIFT_PACKAGE
import AirPostureCore
#endif
import AppKit
import SceneKit
import SwiftUI

struct InstrumentBustView: View {
    let pitch: Double
    let roll: Double
    let yaw: Double
    let band: PostureBand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var lifetime = BustViewLifetime()
#if DEBUG
    @StateObject private var debugState = BustDebugState()
#endif

    var body: some View {
        representation
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(alignment: .topTrailing) {
#if DEBUG
                if BustDebugState.isEnabled {
                    BustDebugView(state: debugState)
                }
#endif
            }
            .onAppear { lifetime.setPresented(true) }
            .onDisappear { lifetime.setPresented(false) }
    }

    private var representation: InstrumentBustRepresentable {
        var representation = InstrumentBustRepresentable(
            input: BustTrackingPose(pitch: pitch, roll: roll, yaw: yaw, expression: expression),
            config: animationConfig,
            reduceMotion: reduceMotion,
            lifetime: lifetime
        )
#if DEBUG
        if BustDebugState.isEnabled {
            representation.debugReadout = debugState.readout
        }
#endif
        return representation
    }

    private var animationConfig: BustAnimationConfig {
#if DEBUG
        if BustDebugState.isEnabled { return debugState.config }
#endif
        return BustAnimationConfig()
    }

    private var expression: BustExpression {
        switch band {
        case .upright: .upright
        case .leaning: .leaning
        case .slouching: .slouching
        case .paused, .uncalibrated, .waitingForHeadphones: .inactive
        }
    }
}

/// Main-thread lifecycle owner. Its weak reference belongs to this SwiftUI
/// identity only, so disappearing views cannot pause another avatar instance.
private final class BustViewLifetime: ObservableObject {
    private weak var view: InstrumentSCNView?
    private var isPresented = false

    func attach(_ view: InstrumentSCNView) {
        self.view = view
        view.setPresented(isPresented)
    }

    func detach(_ view: InstrumentSCNView) {
        view.setPresented(false)
        if self.view === view { self.view = nil }
    }

    func setPresented(_ isPresented: Bool) {
        self.isPresented = isPresented
        view?.setPresented(isPresented)
    }
}

/// Only value data crosses from SwiftUI's main thread to SceneKit's render
/// thread. Neither thread holds the lock while doing scene or UI work.
private final class BustRendererMailbox {
    struct Snapshot {
        var input = BustTrackingPose()
        var config = BustAnimationConfig()
        var reduceMotion = false
        var isActive = false
        var activation: UInt64 = 0
    }

    private let lock = NSLock()
    private var value = Snapshot()

    func update(input: BustTrackingPose, config: BustAnimationConfig, reduceMotion: Bool) {
        lock.lock()
        value.input = input
        value.config = config
        value.reduceMotion = reduceMotion
        lock.unlock()
    }

    func setActive(_ isActive: Bool) {
        lock.lock()
        if isActive != value.isActive {
            value.isActive = isActive
            value.activation &+= 1
        }
        lock.unlock()
    }

    func read() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct InstrumentBustRepresentable: NSViewRepresentable {
    let input: BustTrackingPose
    let config: BustAnimationConfig
    let reduceMotion: Bool
    let lifetime: BustViewLifetime
#if DEBUG
    var debugReadout: BustDebugReadoutState?
#endif

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let mailbox = BustRendererMailbox()
        let rig: BustSceneRig?
        let lifetime: BustViewLifetime
        // Only renderer(_:updateAtTime:) touches animation state.
        private var processor = BustAnimationProcessor()
        private var previousTime: TimeInterval?
        private var previousActivation: UInt64 = 0
#if DEBUG
        weak var debugReadout: BustDebugReadoutState?
        private var lastDebugTime = -Double.infinity
#endif

        init(lifetime: BustViewLifetime) {
            self.lifetime = lifetime
            do {
                if let assetURL = InstrumentBustRepresentable.bustAssetURL {
                    rig = try BustSceneRig(assetURL: assetURL)
                } else {
                    rig = nil
                    NSLog("AirPosture: avatar asset is unavailable.")
                }
            } catch {
                rig = nil
                NSLog("AirPosture: avatar could not load: %@", error.localizedDescription)
            }
            super.init()
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let state = mailbox.read()
            guard state.isActive, let rig else {
                previousTime = nil
                return
            }
            if previousActivation != state.activation {
                previousTime = nil
                previousActivation = state.activation
            }
            let delta = previousTime.map { max(0, min(time - $0, 0.1)) } ?? (1.0 / 30.0)
            previousTime = time
            processor.config = state.config
            let output = processor.step(input: state.input, deltaTime: delta, reduceMotion: state.reduceMotion)
            rig.apply(output)
#if DEBUG
            if let debugReadout, time - lastDebugTime >= 0.2 {
                lastDebugTime = time
                let snapshot = BustDebugSnapshot(input: state.input, output: output,
                                                 boneText: rig.debugTransformText())
                DispatchQueue.main.async { [weak debugReadout] in
                    debugReadout?.snapshot = snapshot
                }
            }
#endif
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(lifetime: lifetime)
#if DEBUG
        coordinator.debugReadout = debugReadout
#endif
        return coordinator
    }

    func makeNSView(context: Context) -> InstrumentSCNView {
        let coordinator = context.coordinator
        coordinator.mailbox.update(input: input, config: config, reduceMotion: reduceMotion)
        let view = InstrumentSCNView(mailbox: coordinator.mailbox)
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.scene = coordinator.rig?.scene
        view.pointOfView = coordinator.rig?.cameraNode
        view.delegate = coordinator
        lifetime.attach(view)
        return view
    }

    func updateNSView(_ view: InstrumentSCNView, context: Context) {
        context.coordinator.mailbox.update(input: input, config: config, reduceMotion: reduceMotion)
        // Reconcile attachment and window visibility on the main thread. Pose
        // updates never touch the scene graph or restart an animation action.
        view.updatePlayback()
    }

    static func dismantleNSView(_ view: InstrumentSCNView, coordinator: Coordinator) {
        coordinator.lifetime.detach(view)
        view.delegate = nil
        view.stopObservingWindow()
    }

    private static var bustAssetURL: URL? {
        if let url = Bundle.main.url(forResource: "AirPostureBust", withExtension: "usdz") {
            return url
        }
#if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "AirPostureBust", withExtension: "usdz")
#else
        return nil
#endif
    }
}

private final class InstrumentSCNView: SCNView {
    private let mailbox: BustRendererMailbox
    private var isPresented = false
    private var windowObservers: [NSObjectProtocol] = []
    private var clipObservers: [NSObjectProtocol] = []

    init(mailbox: BustRendererMailbox) {
        self.mailbox = mailbox
        super.init(frame: .zero, options: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPresented(_ isPresented: Bool) {
        self.isPresented = isPresented
        updatePlayback()
    }

    func updatePlayback() {
        let isDrawable = isPresented && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && scene != nil
        mailbox.setActive(isDrawable)
        isPlaying = isDrawable
        rendersContinuously = isDrawable
    }

    private func pausePlayback() {
        mailbox.setActive(false)
        isPlaying = false
        rendersContinuously = false
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { pausePlayback() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in self?.updatePlayback() })
            }
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                // isVisible can still be true during willClose, so this must
                // stop playback directly instead of reevaluating visibility.
                self?.pausePlayback()
            })
        }
        observeClippingViews()
        updatePlayback()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeClippingViews()
        updatePlayback()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePlayback()
    }

    private func observeClippingViews() {
        for observer in clipObservers { NotificationCenter.default.removeObserver(observer) }
        clipObservers.removeAll()
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                clip.postsFrameChangedNotifications = true
                for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                    clipObservers.append(NotificationCenter.default.addObserver(
                        forName: name, object: clip, queue: .main
                    ) { [weak self] _ in self?.updatePlayback() })
                }
            }
            ancestor = view.superview
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        updatePlayback()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updatePlayback()
    }

    func stopObservingWindow() {
        for observer in windowObservers + clipObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
        clipObservers.removeAll()
    }

    deinit {
        for observer in windowObservers + clipObservers { NotificationCenter.default.removeObserver(observer) }
    }
}
