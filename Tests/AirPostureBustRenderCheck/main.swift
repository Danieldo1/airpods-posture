// Native offscreen QA of the production rig, without launching the application.
import AppKit
import SceneKit
import Foundation

@main struct BustRenderCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let asset = root.appendingPathComponent("Sources/AirPostureMac/Resources/AirPostureBust.usdz")
        let directory = root.appendingPathComponent("DesignAssets")
        let rig = try BustSceneRig(assetURL: asset)
        for name in ["CTRL_elbowLeft", "CTRL_elbowRight", "CTRL_wristLeft", "CTRL_wristRight"] {
            precondition(rig.scene.rootNode.childNode(withName:name,recursively:true) != nil,
                         "Restored arms require joint \(name)")
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = rig.scene
        renderer.pointOfView = rig.cameraNode
        renderer.autoenablesDefaultLighting = false
        let size = NSSize(width: 656, height: 376) // 328×188 points @2x
        var config = BustAnimationConfig()
        config.idleIntensity = 0
        let scenarios: [(String, BustTrackingPose)] = [
            ("Upright", .init(expression: .upright)),
            ("Look right", .init(yaw: -30, expression: .upright)),
            ("Look left", .init(yaw: 30, expression: .upright)),
            ("Slouch", .init(pitch: -25, expression: .slouching)),
            ("Lean right", .init(roll: -18, expression: .leaning)),
            ("Lean left", .init(roll: 18, expression: .leaning)),
            ("Chin up", .init(pitch: 20, expression: .upright)),
            ("Combined limit", .init(pitch: -60, roll: 60, yaw: 90, expression: .slouching)),
            ("Concern", .init(expression: .slouching)),
            ("Blink", .init(expression: .upright)),
            ("Recovery", .init(expression:.upright)),
            ("Other limit", .init(pitch:60,roll:-60,yaw:-90,expression:.leaning)),
            ("Brow response", .init(expression:.leaning)),
            ("Arm sway", .init(expression:.upright)),
            ("Inactive", .init(expression: .inactive)),
        ]
        let sheet = NSImage(size: NSSize(width: 984, height: 1090))
        var images: [(String, NSImage)] = []
        var measurements: [String] = []
        for (index, scenario) in scenarios.enumerated() {
            var processor = BustAnimationProcessor(config: config)
            var output = processor.step(input: scenario.1, deltaTime: 1/30, reduceMotion: true)
            if scenario.0 == "Blink" {
                for _ in 0..<86 { output = processor.step(input: scenario.1, deltaTime:1/30) }
                precondition(output.eyeOpenness < 0.3, "Blink snapshot must show closed eyes")
            }
            if scenario.0 == "Recovery" || scenario.0 == "Brow response" {
                _ = processor.step(input:.init(expression:.slouching),deltaTime:1/30,reduceMotion:true)
                // Arm recovery is armed by observed active tracking, never by
                // the Reduce Motion snapshot/reset used to seed this fixture.
                _ = processor.step(input:.init(expression:.slouching),deltaTime:1/30)
                for _ in 0..<11 { output = processor.step(input:scenario.1,deltaTime:1/30) }
                precondition(output.leftBrowHeight > 0.01, "Transition should visibly lift a brow")
            }
            if scenario.0 == "Arm sway" {
                var animatedConfig = config
                animatedConfig.idleIntensity = 1
                processor.config = animatedConfig
                for _ in 0..<165 { output = processor.step(input:scenario.1,deltaTime:1/30) }
            }
            rig.apply(output)
            let image = renderer.snapshot(atTime: Double(index), with: size, antialiasingMode: .multisampling4X)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            if scenario.0 == "Upright" {
                try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("CoolioBust-popover.png"))
            }
            var x0 = bitmap.pixelsWide, x1 = -1, y0 = bitmap.pixelsHigh, y1 = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.08 {
                    x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                }
            }
            precondition(x1 > x0 && y1 > y0, "Missing rendered avatar in \(scenario.0)")
            precondition(x0 > 3 && x1 < bitmap.pixelsWide-4 && y0 > 3 && y1 < bitmap.pixelsHigh-4,
                         "Clipped silhouette in \(scenario.0): \(x0),\(y0)...\(x1),\(y1)")
            if scenario.0 == "Upright" {
                precondition(y1-y0 > 280 && y1-y0 < 350, "Avatar must fill the 188pt hero without excessive margins")
            }
            measurements.append("\(scenario.0): alpha bounds \(x0),\(y0)...\(x1),\(y1) at \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
            images.append((scenario.0,image))
        }
        // Verify that rotations actually carry facial landmarks in SceneKit.
        func joint(_ name: String) -> SCNNode { rig.scene.rootNode.childNode(withName: name, recursively: true)! }
        var processor = BustAnimationProcessor(config: config)
        rig.apply(processor.step(input: .init(expression: .upright), deltaTime: 1/30, reduceMotion: true))
        let neutralFace = (joint("CTRL_eyeLeft").simdWorldPosition + joint("CTRL_eyeRight").simdWorldPosition)/2
        rig.apply(processor.step(input: .init(yaw: -30, expression: .upright), deltaTime: 1/30, reduceMotion: true))
        let turnedFace = (joint("CTRL_eyeLeft").simdWorldPosition + joint("CTRL_eyeRight").simdWorldPosition)/2
        precondition(turnedFace.x > neutralFace.x + 0.15, "Mirror: negative tracker yaw must turn actual face screen-right")
        rig.apply(processor.step(input: .init(roll: -18, expression: .leaning), deltaTime: 1/30, reduceMotion: true))
        let tiltedFace = (joint("CTRL_eyeLeft").simdWorldPosition + joint("CTRL_eyeRight").simdWorldPosition)/2
        precondition(tiltedFace.x > neutralFace.x + 0.1, "Mirror: negative tracker roll must lean actual head screen-right")
        precondition(joint("CTRL_shoulderLeft").worldPosition.y < joint("CTRL_shoulderRight").worldPosition.y,
                     "Mirror: screen-right shoulder follows the rightward lean")
        rig.apply(processor.step(input:.init(roll:18,expression:.leaning),deltaTime:1/30,reduceMotion:true))
        let leftTiltedFace = (joint("CTRL_eyeLeft").simdWorldPosition + joint("CTRL_eyeRight").simdWorldPosition)/2
        precondition(leftTiltedFace.x < neutralFace.x-0.1,"Mirror: opposite roll must lean screen-left")
        precondition(joint("CTRL_shoulderLeft").worldPosition.y > joint("CTRL_shoulderRight").worldPosition.y,
                     "Mirror: opposite shoulder follows the leftward lean")
        rig.apply(processor.step(input:.init(expression:.upright),deltaTime:1/30,reduceMotion:true))
        let restingHand = joint("CTRL_wristLeft").simdWorldPosition
        precondition(restingHand.x > 0.4 && restingHand.y > -1, "Restored wrist rests beside torso above hip base")
        rig.apply(processor.step(input: .init(pitch: -25, expression: .slouching), deltaTime: 1/30, reduceMotion: true))
        let slouchedFace = (joint("CTRL_eyeLeft").simdWorldPosition + joint("CTRL_eyeRight").simdWorldPosition)/2
        precondition(slouchedFace.y < neutralFace.y - 0.1, "Chin-down must lower face")
        precondition(joint("CTRL_neck").simdWorldPosition.z > 0.05, "Slouch must move neck forward")
        let slouchElbow = joint("CTRL_elbowLeft").simdWorldOrientation
        precondition(abs(slouchElbow.imag.x) > 0.01,"Slouch must animate the restored elbow")
        _ = processor.step(input:.init(pitch:-25,expression:.slouching),deltaTime:1/30)
        for _ in 0..<11 { rig.apply(processor.step(input:.init(expression:.upright),deltaTime:1/30)) }
        let liftedBrow = joint("CTRL_browLeft").position.y
        let gestureHand = joint("CTRL_wristLeft").simdWorldPosition
        rig.apply(processor.step(input:.init(expression:.upright),deltaTime:1/30,reduceMotion:true))
        precondition(liftedBrow > joint("CTRL_browLeft").position.y+0.012,"Recovery raises the actual brow joint")
        precondition(simd_distance(gestureHand,restingHand) > 0.015,
                     "Recovery visibly moves a restored hand: \(simd_distance(gestureHand,restingHand))")
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index,item) in images.enumerated() {
            let x = CGFloat(index % 3)*328
            let y = CGFloat(4-index/3)*218
            item.1.draw(in: NSRect(x:x,y:y+24,width:328,height:188))
            (item.0 as NSString).draw(at:NSPoint(x:x+14,y:y+7),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.darkGray])
        }
        sheet.unlockFocus()
        let sheetBitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try sheetBitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("CoolioBust-popover-check.png"))
        // Bounded CPU workload; no renderer/window/timer is started or left behind.
        var totalSteps = 0.0
        let start = ProcessInfo.processInfo.systemUptime
        for i in 0..<10_000 {
            let out = processor.step(input: .init(pitch:sin(Double(i)*0.01)*20,roll:cos(Double(i)*0.01)*15,yaw:15,expression:.leaning),deltaTime:1/30)
            rig.apply(out)
            totalSteps += out.processedPose.pitch
        }
        let cpuMS = (ProcessInfo.processInfo.systemUptime-start)*1000/10_000
        var renderTimes: [Double] = []
        for i in 0..<30 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = renderer.snapshot(atTime: Double(i)/30, with:size,antialiasingMode:.multisampling4X)
            renderTimes.append((ProcessInfo.processInfo.systemUptime-start)*1000)
        }
        renderTimes.sort()
        measurements.append(String(format:"Animation + rig apply: %.4f ms/frame (10,000 iterations, checksum %.3f)",cpuMS,totalSteps))
        measurements.append(String(format:"Offscreen render including readback @656×376: median %.2f ms, p95 %.2f ms (30 samples)",renderTimes[15],renderTimes[28]))
        measurements.append("These snapshot timings include CPU image readback; they are not live popover GPU utilization or energy measurements.")
        let report = measurements.joined(separator:"\n")+"\n"
        try report.write(to:directory.appendingPathComponent("CoolioBust-render-check.txt"),atomically:true,encoding:.utf8)
        print(report)
        print("Production SceneKit rig direction and framing checks passed")
    }
}
