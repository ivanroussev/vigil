import SwiftUI

enum Palette {
    static let working = Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude coral
    static let needsYou = Color(red: 1.0, green: 0.76, blue: 0.20)   // amber
    static let done = Color(red: 0.30, green: 0.87, blue: 0.50)      // green
    static let stuck = Color(red: 0.62, green: 0.58, blue: 0.95)     // lavender
    static let dim = Color.white.opacity(0.55)

    static func color(for state: String) -> Color {
        switch state {
        case "needs_you": return needsYou
        case "done": return done
        case "stuck": return stuck
        default: return working
        }
    }
}

/// Hover + hit-test state shared with the panel's mouse tracking.
final class UIState: ObservableObject {
    @Published var hovered = false
    var hitRect: CGRect = .zero          // in view coordinates, top-left origin
}

struct FrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Flat top, rounded bottom corners: reads as part of the notch.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct PulsingDot: View {
    var color: Color
    var pulsing: Bool
    var size: CGFloat = 8
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: on ? 5 : 1)
            .scaleEffect(pulsing && on ? 1.25 : 1)
            .opacity(pulsing && on ? 0.55 : 1)
            .onAppear { restart() }
            .onChange(of: pulsing) { _, _ in restart() }
    }

    private func restart() {
        on = false
        guard pulsing else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
    }
}

struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var ui: UIState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var onJump: (SessionStatus) -> Void

    var body: some View {
        let s = store.shown
        let state = s?.displayState(now: store.now) ?? "working"
        let color = Palette.color(for: state)
        let progress = CGFloat(s?.progress ?? 0)
        let expanded = s != nil && (ui.hovered || store.pendingRequest != nil)
        // Each side of the notch grows from 44pt to 110pt as steps complete.
        let wing: CGFloat = s == nil ? 0 : 44 + 66 * progress
        let width = expanded ? max(notchWidth + wing * 2, 430) : notchWidth + wing * 2
        let side = (width - notchWidth) / 2

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    PulsingDot(color: color, pulsing: state == "working")
                    ForEach(store.others.prefix(4)) { o in
                        Circle().fill(Palette.color(for: o.displayState(now: store.now))).frame(width: 5, height: 5)
                    }
                }
                .frame(width: side)
                Spacer(minLength: notchWidth)
                trailing(s, state: state, color: color).frame(width: side)
            }
            .frame(height: notchHeight)
            .contentShape(Rectangle())
            .onTapGesture { if let s { onJump(s) } }
            .overlay(alignment: .bottomLeading) {
                if !expanded, let s, s.state != "needs_you", (s.total ?? 0) > 0 || s.state == "done" {
                    ProgressLine(progress: progress, color: color, width: width - 28)
                        .padding(.leading, 14).padding(.bottom, 3)
                }
            }

            if expanded, let s {
                NotchCard(store: store, s: s, state: state, color: color, onJump: onJump)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width)
        .background(NotchShape(radius: expanded ? 20 : 10).fill(Color.black))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ui.hitRect = $0 }
        .shadow(color: state == "working" && !expanded ? color.opacity(0.35) : .black.opacity(expanded ? 0.4 : 0),
                radius: expanded ? 16 : 10, y: 2)
        .opacity(s == nil ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: s)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expanded)
    }

    @ViewBuilder
    private func trailing(_ s: SessionStatus?, state: String, color: Color) -> some View {
        let font = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
        switch state {
        case "needs_you":
            Image(systemName: "hand.raised.fill").font(font).foregroundStyle(color)
        case "done":
            Image(systemName: "checkmark").font(font.weight(.bold)).foregroundStyle(color)
        case "stuck":
            Image(systemName: "questionmark").font(font.weight(.bold)).foregroundStyle(color)
        default:
            if let t = s?.total, t > 0 {
                Text("\(s?.done ?? 0)/\(t)").font(font).foregroundStyle(.white.opacity(0.9))
            } else if let started = s?.started {
                Text(Fmt.duration(store.now - started)).font(font).foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

struct ProgressLine: View {
    var progress: CGFloat
    var color: Color
    var width: CGFloat
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.15))
            Capsule().fill(color).frame(width: max(6, width * progress)).shadow(color: color, radius: 4)
        }
        .frame(width: width, height: 3)
    }
}

/// The card that drops out of the notch on hover (or for an approval).
struct NotchCard: View {
    @ObservedObject var store: StatusStore
    let s: SessionStatus
    let state: String
    let color: Color
    var onJump: (SessionStatus) -> Void

    private let small = Font.system(size: 11, weight: .medium, design: .rounded)
    private let body12 = Font.system(size: 12, weight: .medium, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let req = store.pendingRequest { approval(req) }

            // Header: project and task, click to open the session.
            Button { onJump(s) } label: {
                HStack(spacing: 6) {
                    Text(s.project ?? "Claude").font(body12.weight(.bold)).foregroundStyle(.white)
                    if let t = s.title, !t.isEmpty {
                        Text(t).font(body12).foregroundStyle(Palette.dim).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app").font(small).foregroundStyle(Palette.dim)
                }
            }
            .buttonStyle(.plain)

            // What it's doing now + heartbeat.
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(statusLine).font(body12).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                Spacer(minLength: 4)
                Text(Fmt.duration(store.now - (s.updated ?? store.now)) + " ago").font(small).foregroundStyle(Palette.dim)
            }

            if let p = s.problem(now: store.now) {
                Label(p, systemImage: "exclamationmark.triangle.fill")
                    .font(small).foregroundStyle(Palette.stuck).lineLimit(2)
            }

            if let todos = s.todos, !todos.isEmpty { steps(todos) }

            metrics

            if s.state == "done", let sum = s.summary { finishSummary(sum) }

            if !store.others.isEmpty { othersList }

            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Text("Today: \(Fmt.duration(store.todaySeconds)) · \(store.todayTasks) task\(store.todayTasks == 1 ? "" : "s")")
                Spacer()
                if let m = s.model { Text(m.replacingOccurrences(of: "claude-", with: "")) }
            }
            .font(small).foregroundStyle(Palette.dim)
        }
    }

    private var statusLine: String {
        switch s.state {
        case "done": return "Finished"
        case "needs_you": return s.action ?? "Needs you"
        default: return s.action ?? "Working"
        }
    }

    private func steps(_ todos: [Todo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(todos.prefix(8).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 7) {
                    Image(systemName: t.status == "completed" ? "checkmark.circle.fill"
                          : t.status == "in_progress" ? "circle.dotted.circle" : "circle")
                        .foregroundStyle(t.status == "completed" ? Palette.done
                                         : t.status == "in_progress" ? color : Palette.dim)
                    Text(t.content ?? "").lineLimit(1)
                        .foregroundStyle(t.status == "completed" ? Palette.dim : .white.opacity(0.92))
                        .strikethrough(t.status == "completed", color: Palette.dim)
                }
                .font(small)
            }
            if todos.count > 8 {
                Text("+\(todos.count - 8) more").font(small).foregroundStyle(Palette.dim)
            }
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 18) {
            if let st = s.started {
                metric("Elapsed", Fmt.duration((s.finished ?? store.now) - st))
            }
            if let eta = s.eta(now: store.now, historyPerStep: store.perStep) {
                metric("Left", "~" + Fmt.duration(eta))
            }
            if let ctx = s.context {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Context").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.dim)
                    HStack(spacing: 6) {
                        let frac = min(1, Double(ctx) / Double(s.contextWindow))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(frac > 0.8 ? Palette.needsYou : Color.white.opacity(0.75))
                                .frame(width: 70 * frac)
                        }
                        .frame(width: 70, height: 4)
                        Text("\(Fmt.tokens(ctx)) / \(Fmt.tokens(s.contextWindow))")
                            .font(small).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.dim)
            Text(value).font(body12).monospacedDigit().foregroundStyle(.white.opacity(0.92))
        }
    }

    private func finishSummary(_ sum: TaskSummary) -> some View {
        HStack(spacing: 10) {
            Label("\(sum.files ?? 0) file\(sum.files == 1 ? "" : "s")", systemImage: "doc.text")
            Text("+\(sum.added ?? 0)").foregroundStyle(Palette.done)
            Text("−\(sum.removed ?? 0)").foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
            Text("\(sum.tools ?? 0) tool calls").foregroundStyle(Palette.dim)
        }
        .font(small).foregroundStyle(.white.opacity(0.9))
    }

    private var othersList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Other sessions").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.dim)
            ForEach(store.others.prefix(5)) { o in
                Button { onJump(o) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Palette.color(for: o.displayState(now: store.now))).frame(width: 6, height: 6)
                        Text(o.project ?? "Claude").font(small.weight(.bold)).foregroundStyle(.white)
                        Text(o.state == "done" ? "Finished" : (o.action ?? "")).font(small)
                            .foregroundStyle(Palette.dim).lineLimit(1)
                        Spacer(minLength: 4)
                        if let t = o.total, t > 0 { Text("\(o.done ?? 0)/\(t)").font(small).monospacedDigit().foregroundStyle(Palette.dim) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func approval(_ req: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Palette.needsYou)
                Text("Allow \(req.tool ?? "tool")?").font(body12.weight(.bold)).foregroundStyle(.white)
                if let p = req.project { Text(p).font(small).foregroundStyle(Palette.dim) }
                Spacer()
                if let exp = req.expires {
                    Text("\(max(0, Int(exp - store.now)))s").font(small).monospacedDigit().foregroundStyle(Palette.dim)
                }
            }
            if let d = req.description { Text(d).font(small).foregroundStyle(Palette.dim).lineLimit(2) }
            Text(req.detail ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            HStack(spacing: 8) {
                Text("Or answer in Claude").font(small).foregroundStyle(Palette.dim)
                Spacer()
                Button("Deny") { store.respond(req, allow: false) }
                    .buttonStyle(PillButton(fill: Color.white.opacity(0.12), text: .white))
                Button("Allow") { store.respond(req, allow: true) }
                    .buttonStyle(PillButton(fill: Palette.needsYou, text: .black))
            }
            if store.requests.count > 1 {
                Text("\(store.requests.count - 1) more waiting").font(small).foregroundStyle(Palette.dim)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.needsYou.opacity(0.5), lineWidth: 1))
    }
}

struct PillButton: ButtonStyle {
    var fill: Color
    var text: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(text)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
