import AppKit
import SceneKit
import SwiftUI
import Darwin

@MainActor final class AvatarFixtureState: ObservableObject {
    @Published var yaw = 0.0
    @Published var showsAvatar = true
}

struct AvatarFixture: View {
    @ObservedObject var state: AvatarFixtureState
    var body: some View {
        VStack {
            if state.showsAvatar {
                InstrumentBustView(pitch: 0, roll: 0, yaw: state.yaw, band: .upright)
                    .frame(width: 328, height: 188)
            }
            Color.clear.frame(height: 500)
        }
        .frame(width: 360)
    }
}

@MainActor final class LifecycleDelegate: NSObject, NSApplicationDelegate {
    let state = AvatarFixtureState()
    var window: NSWindow!
    var scroll: NSScrollView!
    var host: NSHostingView<AvatarFixture>!
    var failed = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 300,y:300,width:360,height:220),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "AirPosture avatar verification"
        host = NSHostingView(rootView:AvatarFixture(state:state))
        host.frame = NSRect(x:0,y:0,width:360,height:720)
        scroll = NSScrollView(frame:NSRect(x:0,y:0,width:360,height:220))
        scroll.documentView = host
        scroll.hasVerticalScroller = true
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        if !CommandLine.arguments.contains("--interactive") { Task { await verify() } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        CommandLine.arguments.contains("--interactive")
    }
    func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds:UInt64(seconds*1e9)) }
    func sceneView(_ node: NSView) -> SCNView? {
        if let view=node as? SCNView { return view }
        for child in node.subviews { if let found=sceneView(child) { return found } }
        return nil
    }
    func check(_ condition: Bool,_ message:String) {
        if condition { print("PASS \(message)") }
        else { failed=true; print("FAIL \(message)") }
    }
    func verify() async {
        // NSHostingView is flipped; start at the top of the scroll document.
        scroll.contentView.scroll(to:NSPoint(x:0,y:0))
        await pause(0.8)
        guard let initial=sceneView(host) else { print("FAIL missing avatar view"); exit(1) }
        print("Initial window visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), view hidden=\(initial.isHiddenOrHasHiddenAncestor), visibleRect=\(initial.visibleRect), sceneLoaded=\(initial.scene != nil)")
        check(initial.isPlaying,"visible avatar plays")
        let scene=initial.scene
        let head=scene?.rootNode.childNode(withName:"CTRL_head",recursively:true)
        let initialYaw=head?.eulerAngles.y ?? 0
        state.yaw = -25
        await pause(0.7)
        check(initial.scene === scene,"pose updates reuse the same loaded scene")
        check((head?.eulerAngles.y ?? 0)>initialYaw+0.2,"render callback mirrors negative tracker yaw to screen-right")
        let cpuStart = clock()
        let wallStart = ProcessInfo.processInfo.systemUptime
        await pause(2)
        let cpuSeconds = Double(clock()-cpuStart)/Double(CLOCKS_PER_SEC)
        let cpuPercent = 100*cpuSeconds/(ProcessInfo.processInfo.systemUptime-wallStart)
        print(String(format:"Visible native fixture CPU: %.2f%% of one core over 2 seconds",cpuPercent))
        scroll.contentView.scroll(to:NSPoint(x:0,y:450))
        scroll.reflectScrolledClipView(scroll.contentView)
        await pause(0.35)
        print("Scrolled avatar visibleRect=\(initial.visibleRect)")
        check(!initial.isPlaying && !initial.rendersContinuously,"scrolled-out avatar pauses")
        scroll.contentView.scroll(to:.zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        await pause(0.35)
        check(initial.isPlaying,"scrolling back resumes rendering")
        window.orderOut(nil)
        await pause(0.3)
        check(!initial.isPlaying && !initial.rendersContinuously,"hidden window pauses")
        window.makeKeyAndOrderFront(nil)
        await pause(0.3)
        check(initial.isPlaying,"visible window resumes")
        state.showsAvatar=false
        await pause(0.35)
        check(!initial.isPlaying,"removed SwiftUI avatar pauses")
        state.showsAvatar=true
        await pause(0.4)
        let replacement=sceneView(host)
        check(replacement != nil && replacement!.isPlaying,"recreated avatar resumes")
        check(!initial.isPlaying,"old view cannot resume or pause its replacement")
        window.close()
        await pause(0.2)
        check(replacement?.isPlaying == false,"closing fixture stops rendering")
        print(failed ? "Avatar lifecycle checks failed" : "Avatar lifecycle checks passed")
        fflush(stdout)
        exit(failed ? 1 : 0)
    }
}

@main struct LifecycleCheck {
    @MainActor static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate=LifecycleDelegate()
        app.delegate=delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
