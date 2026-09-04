import SwiftUI

struct MascotView: View {
    var kind: MascotKind
    var state: MascotState
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointerInside = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let effective = effectiveState
            let bounce = bounceOffset(t: t, state: effective)
            let eyeOpen = eyeOpenAmount(t: t, state: effective)
            let workPhase = workPhaseAmount(t: t, state: effective)
            let waitAngle = waitRotation(t: t, state: effective)
            let glance = waitGlance(t: t, state: effective)
            let waitPaw = waitPawLift(t: t, state: effective)

            ZStack(alignment: .bottomTrailing) {
                MascotArt(
                    kind: kind,
                    eyeOpen: eyeOpen,
                    glance: glance,
                    workPhase: workPhase,
                    waitPaw: waitPaw,
                    alert: state == .needsApproval
                )
                .rotationEffect(.degrees(waitAngle))
                .offset(y: bounce)

                if reduceMotion {
                    statusPip(for: state)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .onHover { pointerInside = $0 }
        .accessibilityElement()
        .accessibilityLabel(kind.accessibilityName)
        .accessibilityValue(state.rawValue)
    }

    private var effectiveState: MascotState {
        if pointerInside, state == .idle { return .hover }
        return state
    }

    private func bounceOffset(t: TimeInterval, state: MascotState) -> CGFloat {
        guard state == .idle, !reduceMotion else { return 0 }
        return CGFloat(sin(t * 2 * .pi / 1.6)) * max(1.5, size * 0.05)
    }

    private func eyeOpenAmount(t: TimeInterval, state: MascotState) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch state {
        case .hover:
            let cycle = t.truncatingRemainder(dividingBy: 1.15)
            return cycle < 0.12 ? 0.08 : 1
        case .idle:
            let cycle = t.truncatingRemainder(dividingBy: 3.4)
            return cycle < 0.1 ? 0.08 : 1
        case .needsApproval:
            return 1
        default:
            return 1
        }
    }

    private func workPhaseAmount(t: TimeInterval, state: MascotState) -> CGFloat {
        guard state == .working else { return 0 }
        if reduceMotion { return 0.4 }
        return CGFloat(sin(t * 10))
    }

    private func waitRotation(t: TimeInterval, state: MascotState) -> Double {
        guard state == .waiting else { return 0 }
        if reduceMotion { return 4 }
        return sin(t * 2 * .pi / 2.0) * 6
    }

    private func waitGlance(t: TimeInterval, state: MascotState) -> CGFloat {
        guard state == .waiting else { return 0 }
        if reduceMotion { return 0.7 }
        let cycle = t.truncatingRemainder(dividingBy: 2.0)
        if cycle < 0.55 { return 0 }
        if cycle < 0.75 { return CGFloat((cycle - 0.55) / 0.2) }
        if cycle < 1.15 { return 1 }
        if cycle < 1.35 { return CGFloat(1 - (cycle - 1.15) / 0.2) }
        return 0
    }

    private func waitPawLift(t: TimeInterval, state: MascotState) -> CGFloat {
        guard state == .waiting, !reduceMotion else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: 2.0)
        if cycle < 1.35 { return 0 }
        let local = cycle - 1.35
        if local < 0.12 { return CGFloat(local / 0.12) }
        if local < 0.28 { return 1 }
        if local < 0.5 { return CGFloat(1 - (local - 0.28) / 0.22) }
        return 0
    }

    private func statusPip(for state: MascotState) -> some View {
        Circle()
            .fill(state.pipColor)
            .frame(width: max(6, size * 0.18), height: max(6, size * 0.18))
            .overlay(
                Circle()
                    .stroke(Tokens.canvas, lineWidth: 1.5)
            )
            .offset(x: 1, y: 1)
            .accessibilityHidden(true)
    }
}

private struct MascotArt: View {
    var kind: MascotKind
    var eyeOpen: CGFloat
    var glance: CGFloat
    var workPhase: CGFloat
    var waitPaw: CGFloat
    var alert: Bool

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                artwork(size: s)
                if workPhase != 0 {
                    paws(size: s)
                }
                if waitPaw != 0 {
                    tappingPaw(size: s)
                }
                if alert {
                    alertMark(size: s)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func artwork(size s: CGFloat) -> some View {
        let k = s / 48
        switch kind {
        case .bear: bear(k)
        case .cat: cat(k)
        case .owl: owl(k)
        case .fox: fox(k)
        case .rabbit: rabbit(k)
        case .frog: frog(k)
        case .penguin: penguin(k)
        case .corgi: corgi(k)
        }
    }

    private func bear(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            Circle().fill(p.furDark).frame(width: 15 * k, height: 15 * k).position(x: 12 * k, y: 12 * k)
            Circle().fill(p.furDark).frame(width: 15 * k, height: 15 * k).position(x: 36 * k, y: 12 * k)
            Circle().fill(p.inner).frame(width: 7 * k, height: 7 * k).position(x: 13 * k, y: 13 * k)
            Circle().fill(p.inner).frame(width: 7 * k, height: 7 * k).position(x: 35 * k, y: 13 * k)
            Circle().fill(p.fur).frame(width: 34 * k, height: 34 * k).position(x: 24 * k, y: 28 * k)
            Ellipse().fill(p.belly).frame(width: 18 * k, height: 13 * k).position(x: 24 * k, y: 35 * k)
            eyes(left: CGPoint(x: 17 * k, y: 25 * k), right: CGPoint(x: 31 * k, y: 25 * k), r: 3.4 * k)
            Ellipse().fill(p.accent).frame(width: 6 * k, height: 4.2 * k).position(x: 24 * k, y: 32 * k)
            mouth(at: CGPoint(x: 24 * k, y: 37 * k), width: 6 * k, k: k)
        }
    }

    private func cat(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            triangle(CGPoint(x: 7 * k, y: 22 * k), CGPoint(x: 13 * k, y: 3 * k), CGPoint(x: 22 * k, y: 16 * k), p.fur)
            triangle(CGPoint(x: 41 * k, y: 22 * k), CGPoint(x: 35 * k, y: 3 * k), CGPoint(x: 26 * k, y: 16 * k), p.fur)
            triangle(CGPoint(x: 11 * k, y: 20 * k), CGPoint(x: 14 * k, y: 8 * k), CGPoint(x: 20 * k, y: 16 * k), p.inner)
            triangle(CGPoint(x: 37 * k, y: 20 * k), CGPoint(x: 34 * k, y: 8 * k), CGPoint(x: 28 * k, y: 16 * k), p.inner)
            Circle().fill(p.fur).frame(width: 32 * k, height: 32 * k).position(x: 24 * k, y: 29 * k)
            whisker(from: CGPoint(x: 10 * k, y: 32 * k), to: CGPoint(x: 1 * k, y: 29 * k), k: k)
            whisker(from: CGPoint(x: 10 * k, y: 35 * k), to: CGPoint(x: 1 * k, y: 36 * k), k: k)
            whisker(from: CGPoint(x: 38 * k, y: 32 * k), to: CGPoint(x: 47 * k, y: 29 * k), k: k)
            whisker(from: CGPoint(x: 38 * k, y: 35 * k), to: CGPoint(x: 47 * k, y: 36 * k), k: k)
            eyes(left: CGPoint(x: 17 * k, y: 27 * k), right: CGPoint(x: 31 * k, y: 27 * k), r: 3.2 * k, pupilScale: 0.45)
            triangle(CGPoint(x: 21 * k, y: 32 * k), CGPoint(x: 27 * k, y: 32 * k), CGPoint(x: 24 * k, y: 35.5 * k), p.accent)
            mouth(at: CGPoint(x: 24 * k, y: 38 * k), width: 5 * k, k: k)
        }
    }

    private func owl(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            triangle(CGPoint(x: 8 * k, y: 16 * k), CGPoint(x: 12 * k, y: 2 * k), CGPoint(x: 18 * k, y: 12 * k), p.furDark)
            triangle(CGPoint(x: 40 * k, y: 16 * k), CGPoint(x: 36 * k, y: 2 * k), CGPoint(x: 30 * k, y: 12 * k), p.furDark)
            Circle().fill(p.fur).frame(width: 36 * k, height: 36 * k).position(x: 24 * k, y: 27 * k)
            Circle().fill(p.belly).frame(width: 16 * k, height: 16 * k).position(x: 16 * k, y: 25 * k)
            Circle().fill(p.belly).frame(width: 16 * k, height: 16 * k).position(x: 32 * k, y: 25 * k)
            eyes(left: CGPoint(x: 16 * k, y: 25 * k), right: CGPoint(x: 32 * k, y: 25 * k), r: 5.2 * k, pupilScale: 0.5)
            triangle(CGPoint(x: 20 * k, y: 31 * k), CGPoint(x: 28 * k, y: 31 * k), CGPoint(x: 24 * k, y: 38 * k), p.beak)
        }
    }

    private func fox(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            triangle(CGPoint(x: 6 * k, y: 22 * k), CGPoint(x: 12 * k, y: 2 * k), CGPoint(x: 21 * k, y: 16 * k), p.fur)
            triangle(CGPoint(x: 42 * k, y: 22 * k), CGPoint(x: 36 * k, y: 2 * k), CGPoint(x: 27 * k, y: 16 * k), p.fur)
            triangle(CGPoint(x: 11 * k, y: 20 * k), CGPoint(x: 14 * k, y: 8 * k), CGPoint(x: 19 * k, y: 16 * k), p.inner)
            triangle(CGPoint(x: 37 * k, y: 20 * k), CGPoint(x: 34 * k, y: 8 * k), CGPoint(x: 29 * k, y: 16 * k), p.inner)
            Circle().fill(p.fur).frame(width: 32 * k, height: 30 * k).position(x: 24 * k, y: 29 * k)
            triangle(CGPoint(x: 14 * k, y: 32 * k), CGPoint(x: 34 * k, y: 32 * k), CGPoint(x: 24 * k, y: 45 * k), p.belly)
            eyes(left: CGPoint(x: 17 * k, y: 26 * k), right: CGPoint(x: 31 * k, y: 26 * k), r: 3.1 * k)
            Ellipse().fill(p.accent).frame(width: 5 * k, height: 4 * k).position(x: 24 * k, y: 36 * k)
        }
    }

    private func rabbit(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            Capsule().fill(p.fur).frame(width: 9 * k, height: 24 * k)
                .rotationEffect(.degrees(-12))
                .position(x: 16 * k, y: 13 * k)
            Capsule().fill(p.fur).frame(width: 9 * k, height: 24 * k)
                .rotationEffect(.degrees(12))
                .position(x: 32 * k, y: 13 * k)
            Capsule().fill(p.inner).frame(width: 4 * k, height: 16 * k)
                .rotationEffect(.degrees(-12))
                .position(x: 16.5 * k, y: 14 * k)
            Capsule().fill(p.inner).frame(width: 4 * k, height: 16 * k)
                .rotationEffect(.degrees(12))
                .position(x: 31.5 * k, y: 14 * k)
            Circle().fill(p.fur).frame(width: 30 * k, height: 30 * k).position(x: 24 * k, y: 32 * k)
            eyes(left: CGPoint(x: 17 * k, y: 30 * k), right: CGPoint(x: 31 * k, y: 30 * k), r: 3.0 * k)
            Ellipse().fill(p.accent).frame(width: 5.5 * k, height: 4 * k).position(x: 24 * k, y: 36 * k)
            Circle().fill(p.inner.opacity(0.85)).frame(width: 6 * k, height: 6 * k).position(x: 14 * k, y: 36 * k)
            Circle().fill(p.inner.opacity(0.85)).frame(width: 6 * k, height: 6 * k).position(x: 34 * k, y: 36 * k)
        }
    }

    private func penguin(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            Ellipse().fill(p.fur).frame(width: 30 * k, height: 38 * k).position(x: 24 * k, y: 26 * k)
            Ellipse()
                .stroke(p.outline, lineWidth: max(1, 1.25 * k))
                .frame(width: 30 * k, height: 38 * k)
                .position(x: 24 * k, y: 26 * k)
            Ellipse().fill(p.belly).frame(width: 20 * k, height: 26 * k).position(x: 24 * k, y: 30 * k)
            Ellipse().fill(p.belly).frame(width: 22 * k, height: 16 * k).position(x: 24 * k, y: 18 * k)
            eyes(left: CGPoint(x: 18 * k, y: 18 * k), right: CGPoint(x: 30 * k, y: 18 * k), r: 2.8 * k)
            triangle(CGPoint(x: 19 * k, y: 22 * k), CGPoint(x: 29 * k, y: 22 * k), CGPoint(x: 24 * k, y: 28 * k), p.beak)
            Ellipse().fill(p.beak).frame(width: 7 * k, height: 3.2 * k).position(x: 16 * k, y: 44 * k)
            Ellipse().fill(p.beak).frame(width: 7 * k, height: 3.2 * k).position(x: 32 * k, y: 44 * k)
        }
    }

    private func frog(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            Circle().fill(p.fur).frame(width: 14 * k, height: 14 * k).position(x: 14 * k, y: 16 * k)
            Circle().fill(p.fur).frame(width: 14 * k, height: 14 * k).position(x: 34 * k, y: 16 * k)
            Ellipse().fill(p.fur).frame(width: 38 * k, height: 26 * k).position(x: 24 * k, y: 30 * k)
            Ellipse().fill(p.belly).frame(width: 22 * k, height: 12 * k).position(x: 24 * k, y: 34 * k)
            eyes(left: CGPoint(x: 14 * k, y: 16 * k), right: CGPoint(x: 34 * k, y: 16 * k), r: 4.4 * k, pupilScale: 0.42)
            mouth(at: CGPoint(x: 24 * k, y: 34 * k), width: 14 * k, k: k, heavy: true)
        }
    }

    private func corgi(_ k: CGFloat) -> some View {
        let p = palette
        return ZStack {
            triangle(CGPoint(x: 6 * k, y: 24 * k), CGPoint(x: 11 * k, y: 4 * k), CGPoint(x: 22 * k, y: 18 * k), p.fur)
            triangle(CGPoint(x: 42 * k, y: 24 * k), CGPoint(x: 37 * k, y: 4 * k), CGPoint(x: 26 * k, y: 18 * k), p.fur)
            triangle(CGPoint(x: 10 * k, y: 22 * k), CGPoint(x: 13 * k, y: 10 * k), CGPoint(x: 19 * k, y: 18 * k), p.inner)
            triangle(CGPoint(x: 38 * k, y: 22 * k), CGPoint(x: 35 * k, y: 10 * k), CGPoint(x: 29 * k, y: 18 * k), p.inner)
            Ellipse().fill(p.fur).frame(width: 32 * k, height: 28 * k).position(x: 24 * k, y: 30 * k)
            Ellipse().fill(p.belly).frame(width: 10 * k, height: 22 * k).position(x: 24 * k, y: 30 * k)
            Ellipse().fill(p.belly).frame(width: 16 * k, height: 12 * k).position(x: 24 * k, y: 38 * k)
            eyes(left: CGPoint(x: 16 * k, y: 27 * k), right: CGPoint(x: 32 * k, y: 27 * k), r: 3.0 * k)
            Ellipse().fill(p.accent).frame(width: 6.5 * k, height: 4.5 * k).position(x: 24 * k, y: 36 * k)
            mouth(at: CGPoint(x: 24 * k, y: 40 * k), width: 7 * k, k: k)
        }
    }

    private func eyes(left: CGPoint, right: CGPoint, r: CGFloat, pupilScale: CGFloat = 0.52) -> some View {
        ZStack {
            eye(at: left, r: r, pupilScale: pupilScale)
            eye(at: right, r: r, pupilScale: pupilScale)
        }
    }

    private func eye(at point: CGPoint, r: CGFloat, pupilScale: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white)
            Circle()
                .fill(Color.black)
                .frame(width: r * 2 * pupilScale, height: r * 2 * pupilScale)
                .offset(x: glance * r * 0.45)
        }
        .frame(width: r * 2, height: r * 2)
        .scaleEffect(x: 1, y: max(0.06, eyeOpen))
        .position(point)
    }

    private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ color: Color) -> some View {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.closeSubpath()
        }
        .fill(color)
    }

    private func whisker(from: CGPoint, to: CGPoint, k: CGFloat) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(palette.accent.opacity(0.65), style: StrokeStyle(lineWidth: max(0.8 * k, 0.6), lineCap: .round))
    }

    private func mouth(at point: CGPoint, width: CGFloat, k: CGFloat, heavy: Bool = false) -> some View {
        Path { path in
            path.addArc(
                center: point,
                radius: width / 2,
                startAngle: .degrees(20),
                endAngle: .degrees(160),
                clockwise: false
            )
        }
        .stroke(palette.accent, style: StrokeStyle(lineWidth: (heavy ? 1.8 : 1.2) * k, lineCap: .round))
    }

    private func paws(size s: CGFloat) -> some View {
        let k = s / 48
        let lift = workPhase * 2.4 * k
        return ZStack {
            Capsule()
                .fill(palette.furDark)
                .frame(width: 8 * k, height: 5 * k)
                .offset(x: -8 * k, y: 18 * k - lift)
            Capsule()
                .fill(palette.furDark)
                .frame(width: 8 * k, height: 5 * k)
                .offset(x: 8 * k, y: 18 * k + lift)
        }
    }

    private func tappingPaw(size s: CGFloat) -> some View {
        let k = s / 48
        return Capsule()
            .fill(palette.furDark)
            .frame(width: 8 * k, height: 5 * k)
            .offset(x: 8 * k, y: 18 * k - waitPaw * 4.5 * k)
    }

    private func alertMark(size s: CGFloat) -> some View {
        let k = s / 48
        return ZStack {
            Circle().fill(Tokens.danger)
            Text("!")
                .font(.system(size: 8 * k, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 12 * k, height: 12 * k)
        .position(x: 40 * k, y: 8 * k)
    }

    private var palette: Palette {
        kind.palette
    }
}

private struct Palette {
    var fur: Color
    var furDark: Color
    var belly: Color
    var inner: Color
    var accent: Color
    var beak: Color
    var outline: Color
}

private extension MascotKind {
    var palette: Palette {
        switch self {
        case .bear:
            return Palette(
                fur: Color(hex: "#A36B3E"),
                furDark: Color(hex: "#7A4A28"),
                belly: Color(hex: "#E2C09A"),
                inner: Color(hex: "#C48A5A"),
                accent: Color(hex: "#3B2A1A"),
                beak: Color(hex: "#3B2A1A"),
                outline: Color(hex: "#A36B3E")
            )
        case .cat:
            return Palette(
                fur: Color(hex: "#E8A54B"),
                furDark: Color(hex: "#C47C22"),
                belly: Color(hex: "#FFF3D6"),
                inner: Color(hex: "#F3D19A"),
                accent: Color(hex: "#C45A6A"),
                beak: Color(hex: "#C45A6A"),
                outline: Color(hex: "#E8A54B")
            )
        case .owl:
            return Palette(
                fur: Color(hex: "#7A5A32"),
                furDark: Color(hex: "#4E391E"),
                belly: Color(hex: "#E6D3A3"),
                inner: Color(hex: "#C4A36A"),
                accent: Color(hex: "#3B2A1A"),
                beak: Color(hex: "#E0A020"),
                outline: Color(hex: "#7A5A32")
            )
        case .fox:
            return Palette(
                fur: Color(hex: "#E06A1A"),
                furDark: Color(hex: "#B44A0C"),
                belly: Color(hex: "#F7E6D0"),
                inner: Color(hex: "#F2C7A0"),
                accent: Color(hex: "#2B2B2B"),
                beak: Color(hex: "#2B2B2B"),
                outline: Color(hex: "#E06A1A")
            )
        case .rabbit:
            return Palette(
                fur: Color(hex: "#F0D6C8"),
                furDark: Color(hex: "#D4B0A2"),
                belly: Color(hex: "#FFF8F4"),
                inner: Color(hex: "#F0B8C6"),
                accent: Color(hex: "#E08AA0"),
                beak: Color(hex: "#E08AA0"),
                outline: Color(hex: "#F0D6C8")
            )
        case .penguin:
            return Palette(
                fur: Color(lightHex: "#2B3137", darkHex: "#8B949E"),
                furDark: Color(lightHex: "#161B22", darkHex: "#6E7681"),
                belly: Color(hex: "#F6F8FA"),
                inner: Color(hex: "#E6EDF3"),
                accent: Color(hex: "#1f2328"),
                beak: Color(hex: "#E09B3D"),
                outline: Color(lightHex: "#656D76", darkHex: "#C9D1D9")
            )
        case .frog:
            return Palette(
                fur: Color(hex: "#4FA64A"),
                furDark: Color(hex: "#2E7A32"),
                belly: Color(hex: "#D7F0A3"),
                inner: Color(hex: "#A5D96A"),
                accent: Color(hex: "#1f4d20"),
                beak: Color(hex: "#1f4d20"),
                outline: Color(hex: "#4FA64A")
            )
        case .corgi:
            return Palette(
                fur: Color(hex: "#E0A04A"),
                furDark: Color(hex: "#B06A28"),
                belly: Color(hex: "#FFF8EE"),
                inner: Color(hex: "#F3E2C4"),
                accent: Color(hex: "#3B2A1A"),
                beak: Color(hex: "#3B2A1A"),
                outline: Color(hex: "#E0A04A")
            )
        }
    }
}

private struct MascotCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MascotKind.allCases) { kind in
                HStack(spacing: 12) {
                    Text(kind.accessibilityName)
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                        .frame(width: 64, alignment: .leading)
                    ForEach([MascotState.idle, .hover, .waiting, .working], id: \.self) { state in
                        MascotView(kind: kind, state: state, size: 48)
                    }
                }
            }
        }
        .padding(16)
        .background(Tokens.canvas)
    }
}

#Preview("Mascots Light") {
    MascotCatalog()
        .preferredColorScheme(.light)
}

#Preview("Mascots Dark") {
    MascotCatalog()
        .preferredColorScheme(.dark)
}

#Preview("Waiting") {
    HStack(spacing: 16) {
        ForEach(MascotKind.allCases) { kind in
            MascotView(kind: kind, state: .waiting, size: 48)
        }
    }
    .padding(16)
    .background(Tokens.canvas)
}
