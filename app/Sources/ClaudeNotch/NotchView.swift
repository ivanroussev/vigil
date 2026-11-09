import SwiftUI

enum Palette {
    static let working = Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude coral
    static let needsYou = Color(red: 1.0, green: 0.76, blue: 0.20)   // amber
    static let done = Color(red: 0.30, green: 0.87, blue: 0.50)      // green

    static func color(for state: String) -> Color {
        switch state {
        case "needs_you": return needsYou
        case "done": return done
        default: return working
        }
    }
}

/// Flat top, rounded bottom corners: reads as part of the notch.
struct NotchShape: Shape {
    var radius: CGFloat
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
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
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
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        let s = store.shown
        let color = Palette.color(for: s?.state ?? "working")
        let progress = CGFloat(s?.progress ?? 0)
        // Each side of the notch grows from 44pt to 110pt as steps complete.
        let wing: CGFloat = s == nil ? 0 : 44 + 66 * progress
        let width = notchWidth + wing * 2

        ZStack(alignment: .bottomLeading) {
            NotchShape(radius: 10)
                .fill(Color.black)

            // Thin progress line along the bottom edge.
            if let s, s.state != "needs_you", (s.total ?? 0) > 0 || s.state == "done" {
                Capsule()
                    .fill(color)
                    .frame(width: max(4, (width - 24) * progress), height: 2)
                    .padding(.leading, 12)
                    .padding(.bottom, 2)
                    .shadow(color: color, radius: 3)
            }

            HStack(spacing: 0) {
                HStack { PulsingDot(color: color, pulsing: s?.state == "working") }
                    .frame(width: wing)
                Spacer(minLength: notchWidth)
                trailing(s, color: color)
                    .frame(width: wing)
            }
            .frame(height: notchHeight)
            .opacity(s == nil ? 0 : 1)
        }
        .frame(width: width, height: notchHeight)
        .shadow(color: s?.state == "working" ? color.opacity(0.35) : .clear, radius: 10, y: 2)
        .opacity(s == nil ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: s)
    }

    @ViewBuilder
    private func trailing(_ s: SessionStatus?, color: Color) -> some View {
        let font = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
        switch s?.state {
        case "needs_you":
            Image(systemName: "hand.raised.fill").font(font).foregroundStyle(color)
        case "done":
            Image(systemName: "checkmark").font(font.weight(.bold)).foregroundStyle(color)
        default:
            if let t = s?.total, t > 0 {
                Text("\(s?.done ?? 0)/\(t)").font(font).foregroundStyle(.white.opacity(0.9))
            } else if let started = s?.started {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(elapsed(since: started, now: ctx.date)).font(font).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private func elapsed(since start: Double, now: Date) -> String {
        let secs = Int(now.timeIntervalSince1970 - start)
        return secs < 60 ? "\(secs)s" : secs < 3600 ? "\(secs / 60)m" : "\(secs / 3600)h\(secs % 3600 / 60)"
    }
}
