import AppKit
import Combine
import SwiftUI

/// Borderless panel that may sit over the menu bar.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }     // lets buttons work; never activates the app
}

/// Buttons react to the first click even though the app is never frontmost.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StatusStore()
    let ui = UIState()
    var panel: NotchPanel?
    var statusItem: NSStatusItem?
    var cancellables = Set<AnyCancellable>()
    var lastInside: TimeInterval = 0
    let detailItem = NSMenuItem(title: "No active Claude session", action: nil, keyEquivalent: "")
    let todayItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let soundsItem = NSMenuItem(title: "Sounds", action: #selector(toggleSounds), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")

    var soundsOn: Bool {
        get { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sounds") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        placePanel()
        setUpMenu()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.placePanel() }

        store.onTransition = { [weak self] _, to in
            guard let self, self.soundsOn else { return }
            if to == "done" { NSSound(named: "Glass")?.play() }
            if to == "needs_you" { NSSound(named: "Tink")?.play() }
        }

        // Hover tracking: the panel is click-through except over the pill / card.
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.trackMouse() }
    }

    func trackMouse() {
        guard let panel else { return }
        let m = NSEvent.mouseLocation
        let f = panel.frame
        let local = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        let inside = store.shown != nil && ui.hitRect.insetBy(dx: -6, dy: -6).contains(local)
        let t = ProcessInfo.processInfo.systemUptime
        if inside { lastInside = t }
        let hovered = inside || t - lastInside < 0.3          // small grace so it doesn't flicker
        if hovered != ui.hovered { ui.hovered = hovered }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        debugLog("mouse=\(Int(local.x)),\(Int(local.y)) hit=\(ui.hitRect.integral) inside=\(inside) shown=\(store.shown?.state ?? "nil") panel=\(f.integral)")
    }

    /// Set ~/.claude/notch/.appdebug to log hit testing twice a second.
    var lastDebug: TimeInterval = 0
    func debugLog(_ line: String) {
        let t = ProcessInfo.processInfo.systemUptime
        guard t - lastDebug > 0.5 else { return }
        lastDebug = t
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/notch")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".appdebug").path) else { return }
        let url = root.appendingPathComponent("app-debug.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        } else {
            try? Data((line + "\n").utf8).write(to: url)
        }
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

        let size = NSSize(width: max(notchWidth + 400, 560), height: 560)
        let frame = NSRect(x: centerX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)

        let p = panel ?? NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        p.setFrame(frame, display: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.sharingType = .none                                        // hidden from screen sharing / recording
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]   // not over fullscreen apps
        p.contentView = FirstClickHostingView(rootView:
            NotchView(store: store, ui: ui, notchWidth: notchWidth, notchHeight: height,
                      onJump: { [weak self] s in self?.jump(to: s) }))
        p.orderFrontRegardless()
        panel = p
    }

    /// Brings the app running that session to the front.
    func jump(to s: SessionStatus) {
        let terminals = [
            "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
            "vscode": "com.microsoft.VSCode", "ghostty": "com.mitchellh.ghostty",
            "WarpTerminal": "dev.warp.Warp-Stable", "WezTerm": "com.github.wez.wezterm",
            "zed": "dev.zed.Zed",
        ]
        var bundle = "com.anthropic.claudefordesktop"
        if s.entry != "claude-desktop", let term = s.term, let b = terminals[term] { bundle = b }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: Menu bar

    /// "◔ 3/8 ~6m" while working, yellow "!" when it needs you, teal "✓" when done.
    func updateStatusBar(_ s: SessionStatus?) {
        guard let button = statusItem?.button else { return }
        todayItem.title = "Today: \(Fmt.duration(store.todaySeconds)) across \(store.todayTasks) task\(store.todayTasks == 1 ? "" : "s")"
        guard let s else {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Claude Notch")
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "No active Claude session"
            detailItem.title = "No active Claude session"
            return
        }
        button.image = nil
        let state = s.displayState(now: store.now)
        // No green / orange dots: those look like the macOS camera and mic indicators.
        let color: NSColor = state == "needs_you" ? .systemYellow : state == "done" ? .systemTeal
            : state == "stuck" ? .systemPurple : .labelColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let text = NSMutableAttributedString()
        func add(_ str: String, _ c: NSColor) {
            text.append(NSAttributedString(string: str, attributes: [.foregroundColor: c, .font: font]))
        }
        switch state {
        case "needs_you": add("! needs you", color)
        case "done": add("✓ done", color)
        case "stuck": add("? stuck", color)
        default:
            if let t = s.total, t > 0 {
                // Ring glyph fills in quarters: ○ ◔ ◑ ◕
                let rings = ["○", "◔", "◑", "◕"]
                add(rings[min(3, Int(s.progress * 4))] + " ", color)
                add("\(s.done ?? 0)/\(t)", .labelColor)
                if let eta = s.eta(now: store.now, historyPerStep: store.perStep) {
                    add(" ~\(Fmt.duration(eta))", .secondaryLabelColor)
                }
            } else if let started = s.started {
                add("◌ working \(Fmt.duration(store.now - started))", .labelColor)
            } else {
                add("working", .labelColor)
            }
        }
        button.attributedTitle = text
        let where_ = s.project.map { " · \($0)" } ?? ""
        let detail = (s.problem(now: store.now) ?? s.action ?? s.state) + where_
        button.toolTip = detail
        detailItem.title = detail
    }

    func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "Claude Notch", action: nil, keyEquivalent: "")
        menu.addItem(detailItem)
        menu.addItem(todayItem)
        menu.addItem(.separator())
        for (title, tag) in [("Preview: working", 1), ("Preview: needs you", 2), ("Preview: stuck", 4),
                             ("Preview: done", 3), ("Stop preview", 0)] {
            let m = NSMenuItem(title: title, action: #selector(preview(_:)), keyEquivalent: "")
            m.target = self
            m.tag = tag
            menu.addItem(m)
        }
        menu.addItem(.separator())
        soundsItem.target = self
        soundsItem.state = soundsOn ? .on : .off
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(soundsItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        // Refresh on every change; `now` ticks twice a second for elapsed / ETA.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.updateStatusBar(self?.store.shown) }
            .store(in: &cancellables)
        updateStatusBar(store.shown)
    }

    @objc func toggleSounds() {
        soundsOn.toggle()
        soundsItem.state = soundsOn ? .on : .off
        if soundsOn { NSSound(named: "Glass")?.play() }
    }

    @objc func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
        loginItem.state = LoginItem.isEnabled ? .on : .off
    }

    @objc func preview(_ sender: NSMenuItem) {
        let now = Date().timeIntervalSince1970
        let todos = [Todo(content: "Read the codebase", status: "completed"),
                     Todo(content: "Write the hook script", status: "completed"),
                     Todo(content: "Build the notch pill", status: "completed"),
                     Todo(content: "Add hover card", status: "in_progress"),
                     Todo(content: "Approve from the notch", status: "pending"),
                     Todo(content: "Test end to end", status: "pending")]
        var s = SessionStatus(state: "working", session: "demo", done: 3, total: 6, action: "Editing NotchView.swift",
                              title: "Make the notch more useful", project: "claude-notch",
                              started: now - 540, updated: now - 4, todos: todos, context: 118_000,
                              model: "claude-opus-5-5")
        switch sender.tag {
        case 2: s.state = "needs_you"; s.action = "Needs approval: Running npm test"
        case 3:
            s.state = "done"; s.done = 6; s.finished = now; s.action = "Done"
            s.todos = todos.map { Todo(content: $0.content, status: "completed") }
            s.summary = TaskSummary(files: 4, added: 312, removed: 48, seconds: 540, tools: 37)
        case 4: s.fails = 3; s.lastError = "Exit code 1: Cannot find module 'express'"
        case 0: store.demo = nil; return
        default: break
        }
        store.demo = s
    }
}

/// Launch at login via a LaunchAgent (works for an unsigned local build).
enum LoginItem {
    static let label = "com.roussev.claudenotch"
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func set(_ on: Bool) {
        if on {
            let dict: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            (dict as NSDictionary).write(to: plist, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: plist)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
