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

    var body: some View {
        InstrumentBustRepresentable(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            band: band,
            animatesPoseChanges: !reduceMotion
        )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onDisappear {
                InstrumentBustRepresentable.pauseIfNeeded()
            }
    }
}

private struct InstrumentBustRepresentable: NSViewRepresentable {
    let pitch: Double
    let roll: Double
    let yaw: Double
    let band: PostureBand
    let animatesPoseChanges: Bool

    final class Coordinator {
        var bustRoot: SCNNode?
        var neckPivot: SCNNode?
        var headPivot: SCNNode?
        var statusMaterial: SCNMaterial?
        var sceneView: SCNView?
        var didLogFailure = false
    }

    static weak var activeView: SCNView?

    static func pauseIfNeeded() {
        activeView?.isPlaying = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = InstrumentSCNView(frame: .zero)
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        guard let scene = Self.makeScene(coordinator: context.coordinator) else {
            if !context.coordinator.didLogFailure {
                context.coordinator.didLogFailure = true
                NSLog("AirPosture: SceneKit bust unavailable; pad will draw without a figure.")
            }
            let fallback = NSView(frame: .zero)
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.clear.cgColor
            return fallback
        }

        view.scene = scene
        view.isPlaying = true
        context.coordinator.sceneView = view
        Self.activeView = view
        applyPose(to: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard nsView is SCNView else {
            return
        }
        context.coordinator.sceneView?.isPlaying = true
        Self.activeView = context.coordinator.sceneView
        applyPose(to: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? SCNView)?.isPlaying = false
        if activeView === nsView {
            activeView = nil
        }
        coordinator.sceneView = nil
    }

    private func applyPose(to coordinator: Coordinator) {
        let pose = PostureGaugeMapping.bustPose(pitch: pitch, roll: roll, yaw: yaw)
        let emission = Self.emission(for: band)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animatesPoseChanges ? 0.075 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        coordinator.neckPivot?.eulerAngles = Self.vector(pose.neckEulerRadians)
        coordinator.headPivot?.eulerAngles = Self.vector(pose.headEulerRadians)
        coordinator.neckPivot?.position = Self.offset(
            origin: Model.neckOrigin,
            by: pose.neckOffset
        )
        coordinator.headPivot?.position = Self.offset(
            origin: Model.headOrigin,
            by: pose.headOffset
        )
        coordinator.statusMaterial?.emission.contents = emission.color
        coordinator.statusMaterial?.emission.intensity = CGFloat(emission.intensity)
        SCNTransaction.commit()
    }

    private static func vector(_ vector: BustVector3) -> SCNVector3 {
        SCNVector3(Float(vector.x), Float(vector.y), Float(vector.z))
    }

    private static func offset(origin: SCNVector3, by offset: BustVector3) -> SCNVector3 {
        let x = origin.x + CGFloat(offset.x)
        let y = origin.y + CGFloat(offset.y)
        let z = origin.z + CGFloat(offset.z)
        return SCNVector3(x, y, z)
    }

    private static func emission(for band: PostureBand) -> (color: NSColor, intensity: Double) {
        switch band {
        case .upright:
            (NSColor.systemGreen, 0.35)
        case .leaning:
            (NSColor.systemOrange, 0.40)
        case .slouching:
            (NSColor.systemRed, 0.45)
        case .paused, .uncalibrated, .waitingForHeadphones:
            (NSColor.white, 0.08)
        }
    }

    private static func makeScene(coordinator: Coordinator) -> SCNScene? {
        let scene = SCNScene()

        let root = SCNNode()
        root.name = "bustRoot"
        scene.rootNode.addChildNode(root)
        coordinator.bustRoot = root

        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = NSColor(calibratedWhite: 0.72, alpha: 0.82)
        glass.metalness.contents = 0.12
        glass.roughness.contents = 0.16
        glass.transparency = 0.46
        glass.blendMode = .alpha
        glass.isDoubleSided = true
        coordinator.statusMaterial = glass

        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = NSColor(calibratedWhite: 0.52, alpha: 1)
        metal.metalness.contents = 0.78
        metal.roughness.contents = 0.38

        let chest = SCNNode(geometry: SCNSphere(radius: 0.38))
        chest.name = "chest"
        chest.geometry?.firstMaterial = metal
        chest.scale = SCNVector3(1.0, 0.34, 0.62)
        chest.position = SCNVector3(0, -0.43, -0.015)
        root.addChildNode(chest)

        for side in [-1.0, 1.0] {
            let shoulder = SCNNode(geometry: SCNSphere(radius: 0.24))
            shoulder.geometry?.firstMaterial = metal
            shoulder.scale = SCNVector3(1.18, 0.38, 0.72)
            shoulder.position = SCNVector3(Float(side * 0.38), -0.37, 0)
            root.addChildNode(shoulder)
        }

        let neckPivot = SCNNode()
        neckPivot.name = "neckPivot"
        neckPivot.position = Model.neckOrigin
        root.addChildNode(neckPivot)
        coordinator.neckPivot = neckPivot

        let neck = SCNNode(geometry: SCNCapsule(capRadius: 0.13, height: 0.34))
        neck.name = "neck"
        neck.geometry?.firstMaterial = metal
        neck.position = SCNVector3(0, 0.15, 0)
        neckPivot.addChildNode(neck)

        let headPivot = SCNNode()
        headPivot.name = "headPivot"
        headPivot.position = Model.headOrigin
        neckPivot.addChildNode(headPivot)
        coordinator.headPivot = headPivot

        let cranium = SCNNode(geometry: SCNSphere(radius: 0.42))
        cranium.name = "cranium"
        cranium.geometry?.firstMaterial = glass
        cranium.scale = SCNVector3(0.78, 0.92, 0.74)
        cranium.position = SCNVector3(0, 0.23, 0)
        headPivot.addChildNode(cranium)

        let jaw = SCNNode(geometry: SCNSphere(radius: 0.32))
        jaw.name = "jaw"
        jaw.geometry?.firstMaterial = glass
        jaw.scale = SCNVector3(0.88, 0.72, 0.82)
        jaw.position = SCNVector3(0, 0.015, 0.035)
        headPivot.addChildNode(jaw)

        // A small facial keel makes left/right yaw readable even at menu-bar size.
        let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.065, height: 0.15))
        nose.name = "facialDirection"
        nose.geometry?.firstMaterial = metal
        nose.eulerAngles.x = .pi / 2
        nose.position = SCNVector3(0, 0.17, 0.32)
        headPivot.addChildNode(nose)

        for side in [-1.0, 1.0] {
            let ear = SCNNode(geometry: SCNSphere(radius: 0.055))
            ear.geometry?.firstMaterial = metal
            ear.scale = SCNVector3(0.55, 1.15, 0.45)
            ear.position = SCNVector3(Float(side * 0.34), 0.19, 0)
            headPivot.addChildNode(ear)
        }

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.55
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.02, 4)
        cameraNode.look(at: SCNVector3(0, -0.04, 0))
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 800
        key.position = SCNVector3(-2.2, 2.6, 3.4)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 250
        fill.position = SCNVector3(0.4, 0.2, 5.5)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 420
        rim.light?.color = NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.82, alpha: 1)
        rim.position = SCNVector3(2.2, 1.5, -2.0)
        scene.rootNode.addChildNode(rim)

        coordinator.bustRoot = root
        return scene
    }

    private enum Model {
        static let neckOrigin = SCNVector3(0, -0.31, 0)
        static let headOrigin = SCNVector3(0, 0.30, 0)
    }
}

private final class InstrumentSCNView: SCNView {
    override var acceptsFirstResponder: Bool { false }
}
