import AppKit
import Combine
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

    var cancellables = Set<AnyCancellable>()
    let detailItem = NSMenuItem(title: "No active Claude session", action: nil, keyEquivalent: "")

    /// Menu bar status: "● ▰▰▰▱▱▱▱▱ 3/8" while working, amber when it needs you, green when done.
    func updateStatusBar(_ s: SessionStatus?) {
        guard let button = statusItem?.button else { return }
        guard let s else {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Claude Notch")
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "No active Claude session"
            detailItem.title = "No active Claude session"
            return
        }
        button.image = nil
        let color: NSColor = s.state == "needs_you" ? .systemOrange : s.state == "done" ? .systemGreen
            : NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let text = NSMutableAttributedString()
        func add(_ str: String, _ c: NSColor) {
            text.append(NSAttributedString(string: str, attributes: [.foregroundColor: c, .font: font]))
        }
        switch s.state {
        case "needs_you": add("✋ needs you", color)
        case "done": add("✓ done", color)
        default:
            add("● ", color)
            if let t = s.total, t > 0 {
                let slots = 10
                let filled = Int((s.progress * Double(slots)).rounded())
                add(String(repeating: "▰", count: filled), color)
                add(String(repeating: "▱", count: slots - filled), .tertiaryLabelColor)
                add(" \(s.done ?? 0)/\(t)", .labelColor)
            } else if let started = s.started {
                let m = Int(Date().timeIntervalSince1970 - started) / 60
                add("working \(m)m", .labelColor)
            } else {
                add("working", .labelColor)
            }
        }
        button.attributedTitle = text
        let where_ = s.project.map { " · \($0)" } ?? ""
        button.toolTip = (s.action ?? "") + where_
        detailItem.title = (s.action ?? s.state) + where_
    }

    func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Claude Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Claude Notch", action: nil, keyEquivalent: "")
        menu.addItem(detailItem)
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

        // Refresh on every change, plus once a minute for the elapsed time.
        store.$primary.combineLatest(store.$demo)
            .receive(on: RunLoop.main)
            .sink { [weak self] p, d in self?.updateStatusBar(d ?? p) }
            .store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateStatusBar(self.store.shown)
        }
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
