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
        var neckOrigin = SCNVector3Zero
        var headOrigin = SCNVector3Zero
        var eyeNodes: [SCNNode] = []
        var porcelainMaterial: SCNMaterial?
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
        view.preferredFramesPerSecond = 30

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
            origin: coordinator.neckOrigin,
            by: pose.neckOffset
        )
        coordinator.headPivot?.position = Self.offset(
            origin: coordinator.headOrigin,
            by: pose.headOffset
        )
        SCNTransaction.commit()

        // The material change communicates a discrete posture state, so it
        // should not tween through intermediate colors as the pose settles.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        coordinator.porcelainMaterial?.emission.contents = emission.color
        coordinator.porcelainMaterial?.emission.intensity = CGFloat(emission.porcelainIntensity)
        coordinator.statusMaterial?.emission.contents = emission.color
        coordinator.statusMaterial?.emission.intensity = CGFloat(emission.collarIntensity)
        SCNTransaction.commit()

        updateBlinkAnimation(for: coordinator)
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

    private static func emission(
        for band: PostureBand
    ) -> (color: NSColor, porcelainIntensity: Double, collarIntensity: Double) {
        switch band {
        case .upright:
            (NSColor.systemGreen, 0.055, 1.25)
        case .leaning:
            (NSColor.systemOrange, 0.065, 1.45)
        case .slouching:
            (NSColor.systemRed, 0.075, 1.65)
        case .paused, .uncalibrated, .waitingForHeadphones:
            (NSColor.white, 0.015, 0.18)
        }
    }

    private static func makeScene(coordinator: Coordinator) -> SCNScene? {
        guard
            let assetURL = bustAssetURL,
            let assetScene = try? SCNScene(url: assetURL),
            let importedRoot = assetScene.rootNode.childNode(
                withName: "AirPostureBust",
                recursively: false
            )
        else {
            return nil
        }

        let scene = SCNScene()

        let root = SCNNode()
        root.name = "bustRoot"
        // Blender's USD orientation conversion produces a Y-up model whose
        // face points toward -Z. Turn the imported sculpture toward the
        // existing +Z SceneKit camera and fill the enlarged hero stage.
        root.eulerAngles.y = .pi
        root.scale = SCNVector3(1.35, 1.35, 1.35)
        scene.rootNode.addChildNode(root)
        coordinator.bustRoot = root

        importedRoot.removeFromParentNode()
        importedRoot.childNode(withName: "env_light", recursively: false)?.removeFromParentNode()
        root.addChildNode(importedRoot)

        guard
            let neckPivot = importedRoot.childNode(withName: "CTRL_neck", recursively: true),
            let headPivot = importedRoot.childNode(withName: "CTRL_head", recursively: true)
        else {
            return nil
        }
        coordinator.neckPivot = neckPivot
        coordinator.headPivot = headPivot
        coordinator.neckOrigin = neckPivot.position
        coordinator.headOrigin = headPivot.position
        coordinator.eyeNodes = ["GraphiteEyeLeft", "GraphiteEyeRight"].compactMap {
            importedRoot.childNode(withName: $0, recursively: true)
        }

        configureMaterials(in: importedRoot, coordinator: coordinator)

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
        key.light?.intensity = 100
        key.position = SCNVector3(-2.2, 2.6, 3.4)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 35
        fill.position = SCNVector3(0.4, 0.2, 5.5)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 60
        rim.light?.color = NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.82, alpha: 1)
        rim.position = SCNVector3(2.2, 1.5, -2.0)
        scene.rootNode.addChildNode(rim)

        coordinator.bustRoot = root
        return scene
    }

    private static func configureMaterials(in root: SCNNode, coordinator: Coordinator) {
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else {
                return
            }

            for (index, importedMaterial) in geometry.materials.enumerated() {
                let material = SCNMaterial()
                material.name = importedMaterial.name
                material.lightingModel = .physicallyBased
                material.isDoubleSided = true

                switch importedMaterial.name {
                case "Porcelain":
                    material.diffuse.contents = NSColor(
                        calibratedRed: 0.25,
                        green: 0.31,
                        blue: 0.38,
                        alpha: 1
                    )
                    material.metalness.contents = 0.22
                    material.roughness.contents = 0.36
                    coordinator.porcelainMaterial = material
                case "Graphite":
                    material.diffuse.contents = NSColor(
                        calibratedRed: 0.025,
                        green: 0.035,
                        blue: 0.055,
                        alpha: 1
                    )
                    material.metalness.contents = 0.72
                    material.roughness.contents = 0.23
                case "StatusGlow":
                    material.diffuse.contents = NSColor(calibratedWhite: 0.07, alpha: 1)
                    material.metalness.contents = 0.35
                    material.roughness.contents = 0.20
                    coordinator.statusMaterial = material
                default:
                    break
                }

                geometry.replaceMaterial(at: index, with: material)
            }
        }
    }

    private func updateBlinkAnimation(for coordinator: Coordinator) {
        let actionKey = "naturalBlink"

        guard animatesPoseChanges else {
            coordinator.bustRoot?.removeAction(forKey: actionKey)
            for eye in coordinator.eyeNodes {
                eye.scale.y = 1
            }
            return
        }

        guard
            coordinator.eyeNodes.count == 2,
            coordinator.bustRoot?.action(forKey: actionKey) == nil
        else {
            return
        }

        coordinator.bustRoot?.runAction(
            Self.blinkSequence(coordinator: coordinator),
            forKey: actionKey
        )
    }

    private static func blinkSequence(coordinator: Coordinator) -> SCNAction {
        let wait = SCNAction.wait(duration: 3.8, withRange: 2.2)
        let close = SCNAction.customAction(duration: 0.065) { [weak coordinator] _, elapsed in
            let progress = min(max(elapsed / 0.065, 0), 1)
            coordinator?.eyeNodes.forEach { $0.scale.y = 1 - 0.92 * progress }
        }
        close.timingMode = .easeIn

        let hold = SCNAction.wait(duration: 0.035)
        let open = SCNAction.customAction(duration: 0.10) { [weak coordinator] _, elapsed in
            let progress = min(max(elapsed / 0.10, 0), 1)
            coordinator?.eyeNodes.forEach { $0.scale.y = 0.08 + 0.92 * progress }
        }
        open.timingMode = .easeOut

        return .repeatForever(.sequence([wait, close, hold, open]))
    }

    private static var bustAssetURL: URL? {
        if let appResource = Bundle.main.url(
            forResource: "AirPostureBust",
            withExtension: "usdz"
        ) {
            return appResource
        }

#if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "AirPostureBust", withExtension: "usdz")
#else
        return nil
#endif
    }
}

private final class InstrumentSCNView: SCNView {
    override var acceptsFirstResponder: Bool { false }
}
