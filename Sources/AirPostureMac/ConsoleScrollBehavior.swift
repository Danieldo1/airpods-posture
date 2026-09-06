import AppKit
import SwiftUI

/// Apply native scroll boundaries to the enclosing SwiftUI scroll view.
struct ConsoleScrollBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsView { SettingsView(frame: .zero) }

    func updateNSView(_ view: SettingsView, context: Context) {
        view.configureScrollView()
        view.configureAfterLayout()
    }

    static func dismantleNSView(_ view: SettingsView, coordinator: ()) {
        view.stopObserving()
    }

    final class SettingsView: NSView {
        private weak var observedClip: NSClipView?
        private var boundsObserver: NSObjectProtocol?
        private var horizontalLockScheduled = false
        private var isApplyingHorizontalLock = false

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureScrollView()
            configureAfterLayout()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollView()
            configureAfterLayout()
        }

        func configureAfterLayout() {
            // SwiftUI can configure its NSScrollView after updating this child.
            DispatchQueue.main.async { [weak self] in self?.configureScrollView() }
        }

        func configureScrollView() {
            let scroll = enclosingScrollView
            if observedClip !== scroll?.contentView {
                stopObserving()
                if let clip = scroll?.contentView {
                    observedClip = clip
                    clip.postsBoundsChangedNotifications = true
                    boundsObserver = NotificationCenter.default.addObserver(
                        forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleHorizontalLock() }
                    }
                }
            }
            guard let scroll else { return }
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.horizontalScrollElasticity != .none { scroll.horizontalScrollElasticity = .none }
            if scroll.verticalScrollElasticity != .none { scroll.verticalScrollElasticity = .none }
            scheduleHorizontalLock()
        }

        private func scheduleHorizontalLock() {
            guard !horizontalLockScheduled, !isApplyingHorizontalLock,
                  let clip = observedClip, clip.bounds.origin.x.isFinite,
                  abs(clip.bounds.origin.x) > 0.5 else { return }
            horizontalLockScheduled = true
            // AppKit posts bounds notifications partway through layer alignment.
            // Writing bounds inside that notification recursively re-enters layout.
            DispatchQueue.main.async { [weak self, weak clip] in
                guard let self, let clip, self.observedClip === clip else { return }
                self.horizontalLockScheduled = false
                self.lockHorizontalPosition()
            }
        }

        private func lockHorizontalPosition() {
            guard let clip = observedClip, clip.documentView != nil else { return }
            var proposedBounds = clip.bounds
            proposedBounds.origin.x = 0
            let targetX = clip.constrainBoundsRect(proposedBounds).origin.x
            guard targetX.isFinite, abs(clip.bounds.origin.x - targetX) > 0.5 else { return }
            // Respect native alignment/insets and avoid chasing subpixel rounding.
            isApplyingHorizontalLock = true
            defer { isApplyingHorizontalLock = false }
            clip.scroll(to: NSPoint(x: targetX, y: clip.bounds.origin.y))
            clip.enclosingScrollView?.reflectScrolledClipView(clip)
        }

        func stopObserving() {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            observedClip = nil
            horizontalLockScheduled = false
        }

        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        }
    }
}
