import Foundation

struct Todo: Codable, Equatable, Hashable {
    var content: String?
    var status: String?
}

struct TaskSummary: Codable, Equatable {
    var files: Int?
    var added: Int?
    var removed: Int?
    var seconds: Int?
    var tools: Int?
}

/// One Claude session, as written by hooks/notch-hook.sh.
struct SessionStatus: Codable, Equatable, Identifiable {
    var state: String                 // working | needs_you | done | idle
    var session: String? = nil
    var done: Int? = nil
    var total: Int? = nil
    var action: String? = nil
    var title: String? = nil
    var project: String? = nil
    var cwd: String? = nil
    var started: Double? = nil
    var updated: Double? = nil
    var finished: Double? = nil
    var todos: [Todo]? = nil
    var files: [String]? = nil
    var fails: Int? = nil
    var repeats: Int? = nil
    var tools: Int? = nil
    var lastError: String? = nil
    var inTool: Bool? = nil
    var context: Int? = nil
    var model: String? = nil
    var summary: TaskSummary? = nil
    var entry: String? = nil
    var host_session: String? = nil
    var term: String? = nil
    var pid: Int? = nil

    var id: String { session ?? project ?? "session" }

    var progress: Double {
        if state == "done" { return 1 }
        guard let t = total, t > 0 else { return 0 }
        return Double(done ?? 0) / Double(t)
    }

    /// Why a working session looks stuck, or nil if it looks fine.
    func problem(now: Double) -> String? {
        guard state == "working" else { return nil }
        if let f = fails, f >= 3 { return "Failed \(f)× in a row" + (lastError.map { ": \($0)" } ?? "") }
        if let r = repeats, r >= 3 { return "Repeated the same step \(r)×" }
        let quiet = now - (updated ?? now)
        let limit: Double = (inTool ?? false) ? 30 * 60 : 10 * 60   // long commands get more slack
        if quiet > limit { return "No activity for \(Int(quiet / 60)) min" }
        return nil
    }

    /// working | stuck | needs_you | done
    func displayState(now: Double) -> String {
        problem(now: now) != nil ? "stuck" : state
    }

    var priority: Int {
        switch state {
        case "needs_you": return 3
        case "working": return 2
        case "done": return 1
        default: return 0
        }
    }

    /// Seconds left, blending this task's pace with past tasks' seconds per step.
    func eta(now: Double, historyPerStep: Double?) -> Double? {
        guard state == "working", let t = total, t > 0, let start = started else { return nil }
        let d = done ?? 0
        guard d < t else { return nil }
        let current: Double? = d > 0 ? (now - start) / Double(d) : nil
        let rate: Double
        switch (current, historyPerStep) {
        case let (c?, h?): rate = (c + h) / 2
        case let (c?, nil): rate = c
        case let (nil, h?): rate = h
        default: return nil
        }
        return Double(t - d) * rate
    }

    /// Context window size isn't in the transcript: assume 200k unless usage is past it.
    var contextWindow: Int { (context ?? 0) > 200_000 ? 1_000_000 : 200_000 }
}

/// A pending permission request written by hooks/approve.sh.
struct ApprovalRequest: Codable, Equatable, Identifiable {
    var id: String
    var session: String?
    var tool: String?
    var project: String?
    var detail: String?
    var description: String?
    var created: Double?
    var expires: Double?
}

struct HistoryEntry: Codable {
    var finished: Double?
    var seconds: Double?
    var steps: Int?
}

enum Fmt {
    static func duration(_ secs: Double) -> String {
        let s = max(0, Int(secs))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : "\(n / 1000)k"
    }
}
