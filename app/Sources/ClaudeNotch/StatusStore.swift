import Foundation
import Combine

/// One Claude session, as written by hooks/notch-hook.sh.
struct SessionStatus: Decodable, Equatable {
    var state: String          // working | needs_you | done | idle
    var done: Int?
    var total: Int?
    var action: String?
    var title: String?
    var project: String?
    var started: Double?
    var updated: Double?

    var progress: Double {
        if state == "done" { return 1 }
        guard let t = total, t > 0 else { return 0 }
        return Double(done ?? 0) / Double(t)
    }

    var priority: Int {
        switch state {
        case "needs_you": return 3
        case "working": return 2
        case "done": return 1
        default: return 0
        }
    }
}

/// Reads ~/.claude/notch/sessions/*.json twice a second and picks the
/// session the pill should show (needs you > working > done).
final class StatusStore: ObservableObject {
    @Published private(set) var primary: SessionStatus?
    @Published private(set) var activeCount = 0
    /// Set from the menu to preview each state without a real session.
    @Published var demo: SessionStatus?

    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/notch/sessions")
    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    private func reload() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SessionStatus.self, from: Data(contentsOf: $0)) }
            .filter { s in
                let age = now - (s.updated ?? 0)
                if s.state == "done" { return age < 30 * 60 }   // done fades after 30 min
                if s.state == "idle" { return false }
                return age < 3 * 3600                            // ignore crashed sessions
            }

        let best = sessions.max { a, b in
            a.priority != b.priority ? a.priority < b.priority : (a.updated ?? 0) < (b.updated ?? 0)
        }
        let count = sessions.filter { $0.state != "done" }.count
        if best != primary { primary = best }
        if count != activeCount { activeCount = count }
    }

    var shown: SessionStatus? { demo ?? primary }
}
