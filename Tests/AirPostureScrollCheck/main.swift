import AppKit
import SwiftUI

private var failures = 0

// AppKit can emit bounds notifications while it is still aligning a layer.
// Refuse nested writes so this regression reports a failure instead of overflowing
// the test process's stack like the real popover did.
private final class AligningClipView: NSClipView {
    private var isAligning = false
    private(set) var nestedBoundsWrites = 0

    func alignBounds(to point: NSPoint) {
        isAligning = true
        super.setBoundsOrigin(point)
        isAligning = false
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        if isAligning {
            nestedBoundsWrites += 1
            return
        }
        super.setBoundsOrigin(newOrigin)
    }
}

private struct SwiftUIScrollFixture: View {
    let contentHeight: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            Text("An intrinsically wide child")
                .frame(width: 520, height: contentHeight)
                .frame(width: 360)
                .background(ConsoleScrollBehavior())
        }
        .frame(width: 360, height: 300)
    }
}

@MainActor
private func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        fputs("FAIL \(message)\n", stderr)
    }
}

@main
private struct ScrollCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        checkBoundsNotificationReentrancy()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 900))
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .allowed

        let policy = ConsoleScrollBehavior.SettingsView(frame: .zero)
        document.addSubview(policy)
        policy.configureScrollView()

        check(scroll.horizontalScrollElasticity == .none, "horizontal rubber-banding is disabled")
        check(scroll.verticalScrollElasticity == .none, "vertical rubber-banding is disabled")
        check(!scroll.hasHorizontalScroller, "horizontal scroller stays disabled")

        let clip = scroll.contentView
        clip.setBoundsOrigin(NSPoint(x: 100, y: 200))
        settleScrollCorrections()
        check(clip.bounds.minX == 0, "overflowing children cannot move the document horizontally")
        check(abs(clip.bounds.minY - 200) < 0.5, "locking X preserves normal vertical scrolling")

        // Layout changes and direct clip scrolling must obey the same boundary.
        document.setFrameSize(NSSize(width: 700, height: 1400))
        clip.setBoundsOrigin(NSPoint(x: -40, y: 400))
        settleScrollCorrections()
        check(clip.bounds.minX == 0 && abs(clip.bounds.minY - 400) < 0.5,
              "expanded content remains vertically scrollable without X drift")

        for delta in [1200, -1200] as [Int32] {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 2, wheel1: delta, wheel2: 100, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
            settleScrollCorrections()
            let maximumY = max(0, document.frame.height - clip.bounds.height)
            check(clip.bounds.minX == 0, "diagonal wheel input cannot scroll on X")
            check(clip.bounds.minY >= 0 && clip.bounds.minY <= maximumY,
                  "wheel input stays within vertical document bounds")
        }

        // A reparented SwiftUI helper must stop constraining its former scroll view.
        policy.removeFromSuperview()
        policy.configureScrollView()
        clip.setBoundsOrigin(NSPoint(x: 50, y: 100))
        settleScrollCorrections()
        check(clip.bounds.minX == 50, "detached policy releases its former clip view")

        checkSwiftUIIntegration()
        if failures > 0 { exit(1) }
        print("AirPosture scroll boundary checks passed")
    }

    @MainActor
    private static func checkBoundsNotificationReentrancy() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        let clip = AligningClipView(frame: scroll.bounds)
        scroll.contentView = clip
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 900))
        scroll.documentView = document
        let policy = ConsoleScrollBehavior.SettingsView(frame: .zero)
        document.addSubview(policy)
        policy.configureScrollView()

        clip.alignBounds(to: NSPoint(x: 40, y: 200))
        check(clip.nestedBoundsWrites == 0, "bounds notifications must not mutate an in-flight AppKit layout")
        settleScrollCorrections()
        check(abs(clip.bounds.minX) < 0.5 && abs(clip.bounds.minY - 200) < 0.5,
              "horizontal correction happens after native layout while preserving Y")

        clip.alignBounds(to: NSPoint(x: 0.000_001, y: 200))
        settleScrollCorrections()
        check(clip.nestedBoundsWrites == 0 && abs(clip.bounds.minX - 0.000_001) < 0.000_000_01,
              "subpixel alignment is left alone instead of causing a correction loop")

        clip.alignBounds(to: NSPoint(x: 40, y: 200))
        policy.removeFromSuperview()
        settleScrollCorrections()
        check(clip.bounds.minX == 40, "queued corrections do not touch a detached clip view")
    }

    @MainActor
    private static func settleScrollCorrections() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private static func checkSwiftUIIntegration() {
        let host = NSHostingView(rootView: SwiftUIScrollFixture(contentHeight: 200))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host

        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }

        for height in [200.0, 1200.0, 200.0] {
            host.rootView = SwiftUIScrollFixture(contentHeight: height)
            host.layoutSubtreeIfNeeded()
            // The helper runs again after SwiftUI configures its native scroll view.
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            guard let scroll = scrollView(in: host) else {
                check(false, "SwiftUI installs a native scroll view")
                return
            }
            check(scroll.horizontalScrollElasticity == .none && scroll.verticalScrollElasticity == .none,
                  "SwiftUI content resizing preserves disabled elasticity")
            scroll.contentView.setBoundsOrigin(NSPoint(x: 30, y: 0))
            settleScrollCorrections()
            check(scroll.contentView.bounds.minX == 0, "SwiftUI installs the horizontal boundary helper")
        }
        withExtendedLifetime(window) {}
    }
}
