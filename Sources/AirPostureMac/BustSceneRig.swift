#if SWIFT_PACKAGE
import AirPostureCore
#endif
import AppKit
import SceneKit
import simd

/// Cached production rig shared by the view and the native snapshot fixture.
/// After initialization, only the SceneKit renderer callback may call `apply`.
final class BustSceneRig {
    let scene: SCNScene
    let cameraNode: SCNNode

    private let chest: Joint
    private let neck: Joint
    private let head: Joint
    private let leftShoulder: Joint
    private let rightShoulder: Joint
    private let leftElbow: Joint
    private let rightElbow: Joint
    private let leftWrist: Joint
    private let rightWrist: Joint
    private let leftEye: Joint?
    private let rightEye: Joint?
    private let leftBrow: Joint?
    private let rightBrow: Joint?
    private let leftMouth: Joint?
    private let rightMouth: Joint?

    enum LoadError: LocalizedError {
        case missingNode(String)

        var errorDescription: String? {
            switch self {
            case .missingNode(let name): "The avatar asset is missing \(name)."
            }
        }
    }

    init(assetURL: URL) throws {
        let importedScene = try SCNScene(url: assetURL)
        guard let importedRoot = importedScene.rootNode.childNode(
            withName: "AirPostureBust", recursively: false
        ) else { throw LoadError.missingNode("AirPostureBust") }

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        importedRoot.removeFromParentNode()
        importedRoot.childNode(withName: "env_light", recursively: false)?.removeFromParentNode()
        scene.rootNode.addChildNode(importedRoot)
        self.scene = scene

        func joint(_ name: String) throws -> Joint {
            guard let node = importedRoot.childNode(withName: name, recursively: true) else {
                throw LoadError.missingNode(name)
            }
            return Joint(node: node)
        }
        func optionalJoint(_ name: String) -> Joint? {
            importedRoot.childNode(withName: name, recursively: true).map(Joint.init)
        }

        _ = try joint("CTRL_root")
        chest = try joint("CTRL_chest")
        neck = try joint("CTRL_neck")
        head = try joint("CTRL_head")
        leftShoulder = try joint("CTRL_shoulderLeft")
        rightShoulder = try joint("CTRL_shoulderRight")
        leftElbow = try joint("CTRL_elbowLeft")
        rightElbow = try joint("CTRL_elbowRight")
        leftWrist = try joint("CTRL_wristLeft")
        rightWrist = try joint("CTRL_wristRight")
        leftEye = optionalJoint("CTRL_eyeLeft")
        rightEye = optionalJoint("CTRL_eyeRight")
        leftBrow = optionalJoint("CTRL_browLeft")
        rightBrow = optionalJoint("CTRL_browRight")
        leftMouth = optionalJoint("CTRL_mouthLeft")
        rightMouth = optionalJoint("CTRL_mouthRight")

        Self.configureMaterials(in: importedRoot)

        // The asset is two units tall, from hips at -1 to head at +1.
        // Its export is already +Y up, +Z facing the camera. Keep the bind
        // transforms intact; do not add the old sculpture's 180-degree turn.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        // SceneKit uses half the vertical span here: 2.4 units leaves
        // 16pt of breathing room above and below a 156pt-tall neutral bust.
        camera.orthographicScale = 1.2
        camera.zNear = 0.1
        camera.zFar = 20
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.exposureOffset = 0
        cameraNode = SCNNode()
        cameraNode.name = "AvatarCamera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        Self.addLight(to: scene, name: "SoftKey", type: .omni,
                      intensity: 100, color: .white, position: SCNVector3(-2.5, 3, 4))
        Self.addLight(to: scene, name: "SoftFill", type: .omni,
                      intensity: 35, color: NSColor(calibratedRed: 0.83, green: 0.90, blue: 1, alpha: 1),
                      position: SCNVector3(2.8, 0.5, 4))
        Self.addLight(to: scene, name: "ShoulderRim", type: .omni,
                      intensity: 60, color: .white, position: SCNVector3(0.5, 2, -3))
        Self.addLight(to: scene, name: "AmbientFill", type: .ambient,
                      intensity: 30, color: .white, position: SCNVector3Zero)
    }

    func apply(_ output: BustAnimationOutput) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        chest.apply(rotation: output.chestEulerRadians,
                    scale: SIMD3(1, 1 + Float(output.breathing) * 0.5, 1 + Float(output.breathing)))
        neck.apply(rotation: output.neckEulerRadians, offset: output.neckOffset)
        head.apply(rotation: output.headEulerRadians)
        leftShoulder.apply(rotation: output.leftShoulderEulerRadians, offset: output.leftShoulderOffset)
        rightShoulder.apply(rotation: output.rightShoulderEulerRadians, offset: output.rightShoulderOffset)
        leftElbow.apply(rotation: output.leftElbowEulerRadians)
        rightElbow.apply(rotation: output.rightElbowEulerRadians)
        leftWrist.apply(rotation: output.leftWristEulerRadians)
        rightWrist.apply(rotation: output.rightWristEulerRadians)

        // Facial geometry is skinned to its corresponding controls. Scaling
        // along canonical Y also handles imported joints with rotated axes.
        let eyeScale = SIMD3<Float>(1, Float(output.eyeOpenness), 1)
        leftEye?.apply(scale: eyeScale)
        rightEye?.apply(scale: eyeScale)
        leftBrow?.apply(rotation: BustVector3(x: 0, y: 0, z: output.leftBrowAngleRadians),
                        offset: BustVector3(x: 0, y: output.leftBrowHeight, z: 0))
        rightBrow?.apply(rotation: BustVector3(x: 0, y: 0, z: output.rightBrowAngleRadians),
                         offset: BustVector3(x: 0, y: output.rightBrowHeight, z: 0))
        let mouthOffset = BustVector3(x: 0, y: (output.smileWeight - output.frownWeight) * 0.055, z: 0)
        leftMouth?.apply(offset: mouthOffset)
        rightMouth?.apply(offset: mouthOffset)
        SCNTransaction.commit()
    }

#if DEBUG
    /// Joint-local values include imported rest orientation. Queried at most 5 Hz.
    func debugTransformText() -> String {
        [head, neck, chest, leftShoulder, leftElbow, leftWrist,
         rightShoulder, rightElbow, rightWrist].map { joint in
            let angles = joint.node.eulerAngles
            let degrees = 180.0 / Double.pi
            return String(format: "%@: %+.1f %+.1f %+.1f", joint.node.name ?? "Joint",
                          Double(angles.x) * degrees, Double(angles.y) * degrees, Double(angles.z) * degrees)
        }.joined(separator: "\n")
    }
#endif

    private static func addLight(to scene: SCNScene, name: String, type: SCNLight.LightType,
                                 intensity: CGFloat, color: NSColor, position: SCNVector3) {
        let node = SCNNode()
        node.name = name
        let light = SCNLight()
        light.type = type
        light.intensity = intensity
        light.color = color
        light.castsShadow = false
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private static func configureMaterials(in root: SCNNode) {
        var materials: [String: SCNMaterial] = [:]
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for (index, imported) in geometry.materials.enumerated() {
                let name = imported.name ?? "CoolioClay"
                if let shared = materials[name] {
                    geometry.replaceMaterial(at: index, with: shared)
                    continue
                }
                let material = SCNMaterial()
                material.name = name
                material.lightingModel = .physicallyBased
                material.metalness.contents = 0
                material.roughness.contents = 0.72
                switch name {
                case "CoolioClay":
                    material.diffuse.contents = NSColor(calibratedRed: 0.82, green: 0.63, blue: 0.52, alpha: 1)
                case "FeatureBlack":
                    material.diffuse.contents = NSColor(calibratedWhite: 0.012, alpha: 1)
                    material.roughness.contents = 0.68
                case "MouthDark":
                    material.diffuse.contents = NSColor(calibratedRed: 0.15, green: 0.065, blue: 0.05, alpha: 1)
                case "TeethIvory":
                    material.diffuse.contents = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1)
                default:
                    material.diffuse.contents = imported.diffuse.contents
                }
                materials[name] = material
                geometry.replaceMaterial(at: index, with: material)
            }
        }
    }

    /// Canonical animation axes are +X screen-right, +Y up, +Z face-forward.
    /// USD can retain a different basis for each imported joint. Conjugating
    /// by its parent's rest frame expresses the canonical delta in that
    /// parent space, while preserving the original joint matrix and skin bind.
    /// Animated parent rotations still carry children naturally.
    private struct Joint {
        let node: SCNNode
        let restTransform: simd_float4x4
        let parentBasis: simd_float4x4
        let inverseParentBasis: simd_float4x4

        init(node: SCNNode) {
            self.node = node
            restTransform = node.simdTransform
            var basis = node.parent?.simdWorldTransform ?? matrix_identity_float4x4
            basis.columns.3 = SIMD4(0, 0, 0, 1)
            parentBasis = basis
            inverseParentBasis = basis.inverse
        }

        func apply(rotation: BustVector3 = BustVector3(x: 0, y: 0, z: 0),
                   offset: BustVector3 = BustVector3(x: 0, y: 0, z: 0),
                   scale: SIMD3<Float> = SIMD3(repeating: 1)) {
            let x = simd_quatf(angle: Float(rotation.x), axis: SIMD3(1, 0, 0))
            let y = simd_quatf(angle: Float(rotation.y), axis: SIMD3(0, 1, 0))
            let z = simd_quatf(angle: Float(rotation.z), axis: SIMD3(0, 0, 1))
            var expansion = matrix_identity_float4x4
            expansion.columns.0.x = scale.x
            expansion.columns.1.y = scale.y
            expansion.columns.2.z = scale.z
            let delta = inverseParentBasis * simd_float4x4(z * y * x) * expansion * parentBasis
            var restLinear = restTransform
            restLinear.columns.3 = SIMD4(0, 0, 0, 1)
            var transformed = delta * restLinear
            let displacement = inverseParentBasis * SIMD4(Float(offset.x), Float(offset.y), Float(offset.z), 0)
            transformed.columns.3 = restTransform.columns.3 + displacement
            node.simdTransform = transformed
        }
    }
}
