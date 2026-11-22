import SwiftUI

// MARK: - Buttons

/// Springy press: the whole label (glass included) squishes.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct GlassCircleButton: View {
    let symbol: String
    var size: CGFloat = 52
    var tint: Color? = nil
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

extension View {
    func glassCard(radius: CGFloat = 26, tint: Color? = nil) -> some View {
        glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: radius))
    }

    func sectionLabel() -> some View {
        font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Rings

struct ProgressRing: View {
    var fraction: Double
    var colors: [Color]
    var lineWidth: CGFloat

    var body: some View {
        let f = max(fraction, 0.0001)
        Circle()
            .trim(from: 0, to: f)
            .stroke(
                AngularGradient(colors: colors, center: .center,
                                startAngle: .degrees(0), endAngle: .degrees(max(360 * f, 1))),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }
}

/// Moves a view along a circle, interpolating the *angle* so it travels the arc
/// (not a straight chord) when animated.
struct OrbitPosition: ViewModifier, Animatable {
    var fraction: Double
    var radius: CGFloat
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    func body(content: Content) -> some View {
        let a = fraction * 2 * .pi - .pi / 2
        content.offset(x: radius * cos(a), y: radius * sin(a))
    }
}

struct PulseState { var scale: CGFloat = 1; var opacity: Double = 0 }

struct PulseRing: View {
    var trigger: Int
    var color: Color
    var body: some View {
        Circle()
            .stroke(color, lineWidth: 5)
            .keyframeAnimator(initialValue: PulseState(), trigger: trigger) { v, s in
                v.scaleEffect(s.scale).opacity(s.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(1.2, duration: 0.85)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.01)
                    CubicKeyframe(0, duration: 0.85)
                }
            }
    }
}

struct TickMarks: View, Equatable {
    var lit: Int
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            for i in 0..<60 {
                let major = i % 5 == 0
                let a = Double(i) / 60 * 2 * .pi - .pi / 2
                let len: CGFloat = major ? 11 : 5
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                p.addLine(to: CGPoint(x: c.x + cos(a) * (r - len), y: c.y + sin(a) * (r - len)))
                let on = i < lit
                let o = on ? (major ? 0.95 : 0.6) : (major ? 0.32 : 0.14)
                ctx.stroke(p, with: .color(.white.opacity(o)),
                           style: StrokeStyle(lineWidth: major ? 2.2 : 1.2, lineCap: .round))
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

// MARK: - Equalizer

struct EqualizerBars: View {
    var playing: Bool
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !playing || !AppActivity.shared.canAnimate)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let h = playing ? 0.3 + 0.7 * abs(sin(t * (3.1 + Double(i) * 1.37) + Double(i) * 0.9)) : 0.25
                    Capsule().fill(color).frame(width: 3, height: 14 * h)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

// MARK: - Ambient background

struct AmbientBackground: View {
    var mode: Mode
    var animated: Bool
    private var activity: AppActivity { .shared }

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: !activity.canAnimate)) { tl in
                    meshes(Self.points(tl.date.timeIntervalSinceReferenceDate))
                }
            } else {
                meshes(Self.points(4))
            }
        }
        .animation(.easeInOut(duration: 1.2), value: mode)
        .opacity(0.82)
        .ignoresSafeArea()
    }

    private func meshes(_ pts: [SIMD2<Float>]) -> some View {
        MeshGradient(width: 3, height: 3, points: pts, colors: mode.mesh)
    }

    static func points(_ t: Double) -> [SIMD2<Float>] {
        func f(_ v: Double) -> Float { Float(v) }
        return [
            [0, 0], [f(0.5 + 0.18 * sin(t * 0.31)), 0], [1, 0],
            [0, f(0.5 + 0.18 * sin(t * 0.43))],
            [f(0.5 + 0.22 * sin(t * 0.52)), f(0.5 + 0.22 * cos(t * 0.37))],
            [1, f(0.5 + 0.18 * cos(t * 0.47))],
            [0, 1], [f(0.5 + 0.18 * cos(t * 0.33)), 1], [1, 1],
        ]
    }
}

// MARK: - Throwable glass bubbles

@MainActor
@Observable
final class BubbleField {
    struct Bubble: Identifiable {
        let id: Int
        var pos: CGPoint
        var vel: CGVector
        let r: CGFloat
        var held = false
    }

    var bubbles: [Bubble] = []
    @ObservationIgnored private var bounds: CGSize = .zero
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var last = Date()
    @ObservationIgnored private var grabOffset: CGSize = .zero

    func setBounds(_ s: CGSize) {
        bounds = s
        guard bubbles.isEmpty, s.width > 200, s.height > 200 else { return }
        let radii: [CGFloat] = [54, 36, 68, 26, 44, 20]
        bubbles = radii.enumerated().map { i, r in
            Bubble(id: i,
                   pos: CGPoint(x: .random(in: r...(s.width - r)), y: .random(in: r...(s.height - r))),
                   vel: CGVector(dx: .random(in: -40...40), dy: .random(in: -40...40)),
                   r: r)
        }
        wake()
    }

    /// Starts the physics loop (it stops itself once everything is at rest).
    private func wake() {
        guard timer == nil else { return }
        last = Date()
        let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let now = Date()
        let dt = min(now.timeIntervalSince(last), 1 / 30)
        last = now
        guard bounds.width > 0 else { return }
        var b = bubbles
        let damp = CGFloat(pow(0.45, dt))
        for i in b.indices where !b[i].held {
            var v = b[i].vel
            v.dx *= damp; v.dy *= damp
            var p = b[i].pos
            p.x += v.dx * dt; p.y += v.dy * dt
            let r = b[i].r
            if p.x < r { p.x = r; v.dx = abs(v.dx) * 0.82 }
            else if p.x > bounds.width - r { p.x = bounds.width - r; v.dx = -abs(v.dx) * 0.82 }
            if p.y < r { p.y = r; v.dy = abs(v.dy) * 0.82 }
            else if p.y > bounds.height - r { p.y = bounds.height - r; v.dy = -abs(v.dy) * 0.82 }
            b[i].pos = p; b[i].vel = v
        }
        // Simple elastic collisions between bubbles.
        for i in b.indices {
            for j in (i + 1)..<b.count {
                let dx = b[j].pos.x - b[i].pos.x, dy = b[j].pos.y - b[i].pos.y
                let dist = hypot(dx, dy), minD = b[i].r + b[j].r
                guard dist < minD, dist > 0.01 else { continue }
                let nx = dx / dist, ny = dy / dist, overlap = minD - dist
                let wi: CGFloat = b[i].held ? 0 : (b[j].held ? 1 : 0.5)
                let wj: CGFloat = b[j].held ? 0 : (b[i].held ? 1 : 0.5)
                b[i].pos.x -= nx * overlap * wi; b[i].pos.y -= ny * overlap * wi
                b[j].pos.x += nx * overlap * wj; b[j].pos.y += ny * overlap * wj
                let vn = (b[j].vel.dx - b[i].vel.dx) * nx + (b[j].vel.dy - b[i].vel.dy) * ny
                if vn < 0 {
                    let imp = -vn * 0.95
                    b[i].vel.dx -= nx * imp * wi; b[i].vel.dy -= ny * imp * wi
                    b[j].vel.dx += nx * imp * wj; b[j].vel.dy += ny * imp * wj
                }
            }
        }
        bubbles = b
        // Go to sleep when nothing is moving: zero CPU/GPU while idle.
        if !b.contains(where: { $0.held || hypot($0.vel.dx, $0.vel.dy) > 6 }) {
            timer?.invalidate()
            timer = nil
        }
    }

    func drag(_ id: Int, location: CGPoint, start: CGPoint, velocity: CGSize) {
        guard let i = bubbles.firstIndex(where: { $0.id == id }) else { return }
        wake()
        if !bubbles[i].held {
            bubbles[i].held = true
            grabOffset = CGSize(width: bubbles[i].pos.x - start.x, height: bubbles[i].pos.y - start.y)
            Haptics.tick()
        }
        let r = bubbles[i].r
        bubbles[i].pos = CGPoint(x: min(max(location.x + grabOffset.width, r), bounds.width - r),
                                 y: min(max(location.y + grabOffset.height, r), bounds.height - r))
        bubbles[i].vel = CGVector(dx: velocity.width, dy: velocity.height)
    }

    func release(_ id: Int, velocity: CGSize) {
        guard let i = bubbles.firstIndex(where: { $0.id == id }) else { return }
        bubbles[i].held = false
        wake()
        let cap: CGFloat = 2600
        bubbles[i].vel = CGVector(dx: min(max(velocity.width, -cap), cap), dy: min(max(velocity.height, -cap), cap))
    }
}

struct BubbleLayer: View {
    let field: BubbleField
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(field.bubbles) { b in
                    BubbleView(r: b.r, color: colors[b.id % colors.count], held: b.held)
                        .position(b.pos)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("bubbles"))
                                .onChanged { v in field.drag(b.id, location: v.location, start: v.startLocation, velocity: v.velocity) }
                                .onEnded { v in field.release(b.id, velocity: v.velocity) }
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named("bubbles"))
            .onAppear { field.setBounds(geo.size) }
            .onChange(of: geo.size) { _, s in field.setBounds(s) }
        }
    }
}

struct BubbleView: View {
    let r: CGFloat
    let color: Color
    let held: Bool
    var body: some View {
        Circle()
            .fill(color.opacity(0.18))
            .frame(width: r * 2, height: r * 2)
            .glassEffect(.regular.tint(color.opacity(0.3)).interactive(), in: Circle())
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(.white.opacity(0.4))
                    .frame(width: r * 0.55, height: r * 0.28)
                    .blur(radius: 2.5)
                    .rotationEffect(.degrees(-30))
                    .offset(x: r * 0.32, y: r * 0.3)
            }
            .scaleEffect(held ? 1.15 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: held)
            .contentShape(Circle())
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    var trigger: Int
    var colors: [Color]

    struct Particle {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var spin: Double, sway: Double, w: CGFloat, h: CGFloat, color: Int, circle: Bool
    }
    struct Burst { let start: Date; let particles: [Particle] }

    @State private var burst: Burst?

    var body: some View {
        TimelineView(.animation(paused: burst == nil)) { tl in
            Canvas { ctx, size in
                guard let b = burst else { return }
                let t = tl.date.timeIntervalSince(b.start)
                let fade = max(0, min(1, (3.6 - t) / 0.8))
                for p in b.particles {
                    let x = p.x * size.width + p.vx * t + sin(t * p.sway) * 14
                    let y = p.y * size.height + p.vy * t + 0.5 * 1100 * t * t
                    guard y < size.height + 40 else { continue }
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t))
                    let rect = CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)
                    let path = p.circle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    c.fill(path, with: .color(colors[p.color % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            var ps: [Particle] = []
            let palette = colors.count + 2
            for side in [0.0, 1.0] {
                for _ in 0..<90 {
                    let dir: CGFloat = side == 0 ? 1 : -1
                    ps.append(Particle(x: side, y: 1.0,
                                       vx: dir * .random(in: 150...820),
                                       vy: -.random(in: 700...1350),
                                       spin: .random(in: -12...12), sway: .random(in: 2...6),
                                       w: .random(in: 6...11), h: .random(in: 9...16),
                                       color: .random(in: 0..<palette), circle: .random(in: 0...1) < 0.25))
                }
            }
            burst = Burst(start: .now, particles: ps)
            let mine = trigger
            Task {
                try? await Task.sleep(for: .seconds(4))
                if trigger == mine { burst = nil }
            }
        }
    }
}
