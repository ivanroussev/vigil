import Foundation
import Combine

/// Reads ~/.claude/vigil twice a second: live sessions, approval requests and task history.
final class StatusStore: ObservableObject {
    @Published private(set) var sessions: [SessionStatus] = []     // most important first
    @Published private(set) var requests: [ApprovalRequest] = []
    @Published private(set) var now = Date().timeIntervalSince1970
    @Published private(set) var todaySeconds: Double = 0
    @Published private(set) var todayTasks = 0
    @Published private(set) var perStep: Double?                   // past seconds per plan step
    /// Set from the menu to preview each state without a real session.
    @Published var demo: SessionStatus?

    /// Called when a session changes state (used for sounds).
    var onTransition: ((_ from: String, _ to: String) -> Void)?

    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/vigil")
    private var timer: Timer?
    private var lastStates: [String: String] = [:]
    private var lastHistoryLoad: Double = 0

    var primary: SessionStatus? { sessions.first }
    var shown: SessionStatus? { demo ?? primary }
    var others: [SessionStatus] { demo == nil ? Array(sessions.dropFirst()) : [] }
    var pendingRequest: ApprovalRequest? { requests.first }

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.reload() }
    }

    private func decodeDir<T: Decodable>(_ name: String) -> [T] {
        let dir = root.appendingPathComponent(name)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(T.self, from: Data(contentsOf: $0)) }
    }

    private func isAlive(_ pid: Int?) -> Bool {
        guard let pid, pid > 1 else { return true }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private func reload() {
        let t = Date().timeIntervalSince1970
        now = t

        var live: [SessionStatus] = decodeDir("sessions").filter { s in
            let age = t - (s.updated ?? 0)
            switch s.state {
            case "done": return age < 30 * 60                      // done fades after 30 min
            case "idle": return false
            default: return age < 6 * 3600 && isAlive(s.pid)       // drop crashed sessions
            }
        }
        // scripts/demo.sh: while its session exists, show only that one.
        if live.contains(where: { $0.session == "vigil-demo" }) {
            live = live.filter { $0.session == "vigil-demo" }
        }
        let sorted = live.sorted { a, b in
            a.priority != b.priority ? a.priority > b.priority : (a.updated ?? 0) > (b.updated ?? 0)
        }
        if sorted != sessions { sessions = sorted }

        // Sounds etc. fire only for sessions we've already seen.
        for s in sorted {
            if let old = lastStates[s.id], old != s.state { onTransition?(old, s.state) }
            lastStates[s.id] = s.state
        }

        let reqs: [ApprovalRequest] = decodeDir("requests")
            .filter { ($0.expires ?? 0) > t }
            .sorted { ($0.created ?? 0) < ($1.created ?? 0) }
        if reqs != requests { requests = reqs }

        if t - lastHistoryLoad > 10 { loadHistory(now: t) }
    }

    private func loadHistory(now t: Double) {
        lastHistoryLoad = t
        guard let text = try? String(contentsOf: root.appendingPathComponent("history.jsonl"), encoding: .utf8) else { return }
        let entries = text.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(HistoryEntry.self, from: Data($0.utf8))
        }
        let dayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let today = entries.filter { ($0.finished ?? 0) >= dayStart }
        todaySeconds = today.reduce(0) { $0 + ($1.seconds ?? 0) }
        todayTasks = today.count

        let planned = entries.suffix(200).filter { ($0.steps ?? 0) > 0 && ($0.seconds ?? 0) > 0 }
        let steps = planned.reduce(0) { $0 + ($1.steps ?? 0) }
        perStep = planned.count >= 3 && steps > 0
            ? planned.reduce(0) { $0 + ($1.seconds ?? 0) } / Double(steps) : nil
    }

    /// Writes the answer approve.sh is waiting for.
    func respond(_ req: ApprovalRequest, allow: Bool) {
        let dir = root.appendingPathComponent("responses")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = Data("{\"behavior\":\"\(allow ? "allow" : "deny")\"}".utf8)
        try? body.write(to: dir.appendingPathComponent("\(req.id).json"), options: .atomic)
        requests.removeAll { $0.id == req.id }
    }
}
