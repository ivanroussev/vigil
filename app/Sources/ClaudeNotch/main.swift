import AppKit
import SwiftUI

/// Borderless panel that may sit over the menu bar.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StatusStore()
    var panel: NotchPanel?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        placePanel()
        setUpMenu()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.placePanel() }
    }

    /// Finds the notch and centers a click-through panel on it.
    func placePanel() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        let f = screen.frame
        var notchWidth: CGFloat = 0
        var centerX = f.midX
        var height = screen.safeAreaInsets.top
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = r.minX - l.maxX
            centerX = (l.maxX + r.minX) / 2
        }
        if height == 0 { height = NSStatusBar.system.thickness }   // no notch: pill under the menu bar

        let size = NSSize(width: notchWidth + 400, height: height + 24)
        let frame = NSRect(x: centerX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)

        let p = panel ?? NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        p.setFrame(frame, display: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(rootView:
            NotchView(store: store, notchWidth: notchWidth, notchHeight: height))
        p.orderFrontRegardless()
        panel = p
    }

    func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Claude Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Claude Notch", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (title, tag) in [("Preview: working", 1), ("Preview: needs you", 2), ("Preview: done", 3), ("Stop preview", 0)] {
            let m = NSMenuItem(title: title, action: #selector(preview(_:)), keyEquivalent: "")
            m.target = self
            m.tag = tag
            menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc func preview(_ sender: NSMenuItem) {
        let now = Date().timeIntervalSince1970
        switch sender.tag {
        case 1: store.demo = SessionStatus(state: "working", done: 3, total: 8, action: "Editing index.html", started: now - 300, updated: now)
        case 2: store.demo = SessionStatus(state: "needs_you", done: 3, total: 8, action: "Needs approval", updated: now)
        case 3: store.demo = SessionStatus(state: "done", done: 8, total: 8, updated: now)
        default: store.demo = nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
