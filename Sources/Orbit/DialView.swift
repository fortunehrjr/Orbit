import SwiftUI

/// The big glass dial. Spin the ring to set time (with trackpad haptics),
/// tap it while running to pause.
struct DialView: View {
    @Environment(TimerModel.self) private var timer
    var size: CGFloat

    @State private var dragging = false
    @State private var lastAngle: Double?
    @State private var travel: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("rollingDigits") private var rollingDigits = true

    /// Full animation normally; lighter automatically in Low Power Mode or when
    /// the system "Reduce motion" setting is on.
    private var lightweight: Bool {
        reduceMotion || lowPower || !rollingDigits
    }

    private var inset: CGFloat { size * 0.065 }
    private var lineWidth: CGFloat { size * 0.045 }
    private var ringRadius: CGFloat { size / 2 - inset }

    private var fraction: Double {
        switch timer.phase {
        case .idle, .finished: return min(timer.minutes, 60) / 60
        case .intro: return 1
        case .running, .paused: return timer.dialProgress
        }
    }

    private var lapFraction: Double {
        timer.canEdit && timer.minutes > 60 ? (timer.minutes - 60) / 60 : 0
    }

    var body: some View {
        let accent = timer.mode.accent
        ZStack {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(accent.opacity(timer.chipHovering ? 0.35 : 0.07)), in: Circle())

            // Everything on the dial face is rendered as ONE Metal layer: the glow,
            // tick marks, ring, countdown pulse and the rolling digits. Their
            // blurs/gradients then run on the GPU instead of being repainted on
            // the CPU every second.
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.35), .clear], center: .center,
                                         startRadius: 0, endRadius: size * 0.42))
                    .padding(inset * 1.5)
                    .blendMode(.plusLighter)
                    .opacity(timer.isRunning ? 1 : 0.45)
                    .animation(.easeInOut(duration: 0.8), value: timer.isRunning)

                // Only re-evaluated when a tick actually lights up.
                TickMarks(lit: Int((fraction * 60).rounded(.up)))
                    .equatable()
                    .padding(inset + lineWidth + 10)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: lineWidth)
                    ProgressRing(fraction: fraction, colors: timer.mode.ring, lineWidth: lineWidth)
                        .shadow(color: accent.opacity(0.8), radius: dragging ? 18 : 9)
                    if lapFraction > 0 {
                        ProgressRing(fraction: lapFraction, colors: [.white.opacity(0.95), .white.opacity(0.6)], lineWidth: lineWidth * 0.32)
                            .padding(lineWidth * 0.34)
                            .transition(.opacity)
                    }
                }
                .padding(inset)

                if timer.dialFinal {
                    PulseRing(trigger: timer.dialSeconds, color: accent)
                        .padding(inset)
                        .transition(.opacity)
                }

            }
            .drawingGroup()

            center

            knob
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .scaleEffect(timer.chipHovering ? 1.045 : (dragging ? 1.015 : 1))
        .modifier(ShakeEffect(animatableData: CGFloat(timer.shake)))
        .animation(.linear(duration: 0.45), value: timer.shake)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: timer.chipHovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        .animation(dragging || timer.isRunning ? nil : .spring(response: 0.7, dampingFraction: 0.78), value: fraction)
        .gesture(drag)
        .help(timer.canEdit ? "Spin the ring to set the time" : "Click to pause / resume")
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: Knob

    private var knob: some View {
        let editable = timer.canEdit
        let d: CGFloat = editable ? lineWidth * 2.1 : lineWidth * 0.8
        return ZStack {
            if editable {
                Circle()
                    .fill(.white.opacity(0.15))
                    .glassEffect(.regular.interactive(), in: Circle())
                Circle().fill(.white).frame(width: d * 0.32, height: d * 0.32)
            } else {
                // Glow drawn as a gradient instead of stacked blur shadows.
                Circle()
                    .fill(RadialGradient(colors: [timer.mode.accent.opacity(0.9), timer.mode.accent.opacity(0)],
                                         center: .center, startRadius: d * 0.3, endRadius: d * 1.8))
                    .frame(width: d * 3.6, height: d * 3.6)
                Circle().fill(.white)
            }
        }
        .frame(width: d, height: d)
        .scaleEffect(dragging ? 1.3 : 1)
        .modifier(OrbitPosition(fraction: fraction, radius: ringRadius))
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: editable)
    }

    // MARK: Center

    private var center: some View {
        VStack(spacing: 2) {
            Label(timer.mode.title, systemImage: timer.mode.symbol)
                .font(.system(size: max(13, size * 0.038), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .contentTransition(.interpolate)

            ZStack {
                if timer.dialFinal {
                    Text("\(timer.dialSeconds)")
                        .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: timer.mode.ring, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .id(timer.dialSeconds)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.9).combined(with: .opacity),
                            removal: .scale(scale: 0.5).combined(with: .opacity)))
                } else {
                    Text(timer.dialTimeString)
                        .font(.system(size: size * 0.2, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(lightweight ? .identity : .numericText(countsDown: timer.isRunning))
                        .transition(.blurReplace)
                }
            }
            .frame(height: size * 0.3)
            // Digits get their own small GPU layer (with headroom so the big
            // final-countdown numbers aren't clipped) so their per-second roll
            // never re-renders the ring.
            .padding(size * 0.12)
            .drawingGroup()
            .padding(-size * 0.12)
            // Crisp, quickly-settling roll (an underdamped spring would keep the
            // dial animating almost continuously).
            .animation(lightweight && !timer.dialFinal ? nil
                       : (timer.dialFinal ? .spring(response: 0.38, dampingFraction: 0.72) : .smooth(duration: 0.35)),
                       value: timer.dialSeconds)
            .animation(.spring(response: 0.42, dampingFraction: 0.62), value: timer.dialFinal)

            Text(statusLine)
                .font(.system(size: max(12, size * 0.034), weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.interpolate)
                .animation(.smooth, value: statusLine)
        }
        .allowsHitTesting(false)
    }

    private var statusLine: String {
        switch timer.phase {
        case .idle: return dragging ? "\(Int(timer.minutes.rounded())) minutes" : "Spin the ring · or drop a chip"
        case .intro: return "Get ready…"
        case .running: return "Ends at \(timer.dialEndsAt)"
        case .paused: return "Paused — click to resume"
        case .finished: return timer.mode == .focus ? "Session complete ✨" : "Break's over"
        }
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                travel = hypot(v.translation.width, v.translation.height)
                guard timer.canEdit else { return }
                let c = CGPoint(x: size / 2, y: size / 2)
                let a = atan2(Double(v.location.x - c.x), Double(-(v.location.y - c.y)))
                guard travel > 2 else { return }
                if !dragging {
                    dragging = true
                    lastAngle = a
                    Haptics.tick()
                    return
                }
                guard let la = lastAngle else { return }
                var d = a - la
                if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                lastAngle = a
                let before = Int(timer.minutes.rounded())
                timer.setMinutes(timer.minutes + d / (2 * .pi) * 60)
                let after = Int(timer.minutes.rounded())
                if after != before {
                    if after % 5 == 0 { Haptics.bump() } else { Haptics.tick() }
                }
            }
            .onEnded { _ in
                defer { travel = 0 }
                if dragging {
                    dragging = false
                    lastAngle = nil
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        timer.setMinutes(timer.minutes.rounded())
                    }
                    return
                }
                if travel < 4 {
                    if timer.isActive { timer.primaryAction() }
                } else if !timer.canEdit {
                    timer.shake += 1
                    Haptics.bump()
                }
            }
    }
}
