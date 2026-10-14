import AppKit
import Observation
import SwiftUI

/// Own status item + borderless panel instead of MenuBarExtra: MenuBarExtra always draws a system
/// frame with a small fixed corner radius behind the content, which we can't remove cleanly.
@MainActor
final class StatusBarController: NSObject {
    private let store: ClimateStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = PopoverPanel()
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    init(store: ClimateStore) {
        self.store = store
        super.init()

        panel.setContent(
            PopoverView()
                .environment(store)
                .onGeometryChange(for: CGSize.self, of: \.size) { [weak panel] size in panel?.fit(to: size) }
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        observeLabel()

        // Dev aid: `CLIMATE_OPEN_ON_LAUNCH=1` opens the panel right away (handy for layout work and debugging).
        if ProcessInfo.processInfo.environment["CLIMATE_OPEN_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.openPanel() }
        }
    }

    // MARK: Status item

    private func observeLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLabel() }
        }
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "air.conditioner.horizontal", accessibilityDescription: "ClimateControl")
        image?.isTemplate = true
        button.image = image
        if let device = store.device, device.power {
            button.title = " \(Int(device.targetTemperature.rounded()))°"
        } else {
            button.title = ""
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func showContextMenu() {
        closePanel()
        let menu = NSMenu()
        menu.addItem(withTitle: "ClimateControl beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Panel

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor, on: buttonWindow.screen ?? NSScreen.main)
        button.highlight(true)

        // Clicks in other apps (or the desktop) close the panel, like a regular menu.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            self?.closePanel()
            return nil
        }
        Task { await store.refresh() }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.dismiss()
        statusItem.button?.highlight(false)
        [outsideClickMonitor, escapeMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        outsideClickMonitor = nil
        escapeMonitor = nil
    }
}

/// Borderless, fully transparent panel: the SwiftUI content draws its own rounded shape and the
/// window shadow follows that shape.
final class PopoverPanel: NSPanel {
    private static let gap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private var anchor: NSRect = .zero
    /// Last size reported by the SwiftUI content. NSHostingView.fittingSize is 0 with sizingOptions = [],
    /// and onGeometryChange only fires on changes, so the size must be remembered for the next show().
    private var contentSize: CGSize = .zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    // Needed for keyboard input and for SwiftUI popovers/menus inside a borderless window.
    override var canBecomeKey: Bool { true }

    func setContent<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content.fixedSize())
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    func show(below anchor: NSRect, on screen: NSScreen?) {
        self.anchor = anchor
        fit(to: contentSize, screen: screen)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }
    }

    /// Keeps the panel centred under the status item with its top edge fixed while the content grows/shrinks.
    func fit(to size: CGSize, screen: NSScreen? = nil) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        guard anchor != .zero else { return } // not shown yet: position is computed on show()
        var x = anchor.midX - size.width / 2
        if let visible = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        }
        let y = anchor.minY - Self.gap - size.height
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }
}
