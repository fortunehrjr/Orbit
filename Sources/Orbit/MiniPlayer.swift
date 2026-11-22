import SwiftUI
import AppKit

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A floating, always-on-top glass pill you can fling around the screen.
/// It snaps to screen edges / centre when you let go.
@MainActor
final class MiniPlayerController {
    static let shared = MiniPlayerController()
    private var panel: NSPanel?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(timer: TimerModel, music: NowPlayingModel) {
        if isVisible { hide() } else { show(timer: timer, music: music) }
    }

    func show(timer: TimerModel, music: NowPlayingModel) {
        if panel == nil {
            let size = NSSize(width: 380, height: 72)
            let host = FirstMouseHostingView(rootView: MiniPill().environment(timer).environment(music))
            host.frame = NSRect(origin: .zero, size: size)
            host.autoresizingMask = [.width, .height]

            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = size.height / 2
            glass.contentView = host

            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = glass

            if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 14))
            }
            panel = p
        }
        guard let p = panel else { return }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    func dragChanged() {
        guard let p = panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, p.frame.origin) }
        guard let s = dragStart else { return }
        p.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x, y: s.origin.y + mouse.y - s.mouse.y))
    }

    func dragEnded() {
        dragStart = nil
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame.insetBy(dx: 14, dy: 14)
        var f = p.frame
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        let snap: CGFloat = 90
        if f.minX - vf.minX < snap { f.origin.x = vf.minX }
        else if vf.maxX - f.maxX < snap { f.origin.x = vf.maxX - f.width }
        else if abs(f.midX - vf.midX) < snap { f.origin.x = vf.midX - f.width / 2 }
        if vf.maxY - f.maxY < snap { f.origin.y = vf.maxY - f.height }
        else if f.minY - vf.minY < snap { f.origin.y = vf.minY }
        Haptics.tick()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            p.animator().setFrame(f, display: true)
        }
    }
}

struct MiniPill: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NowPlayingModel.self) private var music
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                ProgressRing(fraction: timer.canEdit ? min(timer.minutes, 60) / 60 : timer.progress,
                             colors: timer.mode.ring, lineWidth: 4)
                Image(systemName: timer.mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .scaleEffect(timer.isFinalCountdown ? 1.1 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.4), value: timer.displaySeconds)

            VStack(alignment: .leading, spacing: 0) {
                Text(timer.timeString)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isFinalCountdown ? AnyShapeStyle(LinearGradient(colors: timer.mode.ring, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(.white))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.displaySeconds)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let t = music.track {
                Button { music.playPause() } label: {
                    ZStack {
                        if let img = music.artwork {
                            Image(nsImage: img).resizable().scaledToFill()
                        } else {
                            t.source.tint
                        }
                        Image(systemName: t.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .opacity(hover ? 1 : 0)
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(PressableStyle())
                .disabled(!music.canControl)
            }

            Button { timer.primaryAction() } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(timer.mode.accent.gradient))
            }
            .buttonStyle(PressableStyle())

            if hover {
                Button { MiniPlayerController.shared.hide() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(PressableStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(timer.mode.accent.opacity(0.12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in MiniPlayerController.shared.dragChanged() }
                .onEnded { _ in MiniPlayerController.shared.dragEnded() }
        )
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hover = h } }
        .environment(\.colorScheme, .dark)
    }

    private var subtitle: String {
        if let t = music.track { return "\(t.title) — \(t.artist)" }
        if !timer.taskName.isEmpty { return timer.taskName }
        return timer.mode.title
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    let timer: TimerModel
    var body: some View {
        if timer.isActive {
            Text("\(Image(systemName: timer.mode.symbol)) \(timer.timeString)")
                .monospacedDigit()
        } else {
            Image(systemName: "timer")
        }
    }
}

struct MenuBarPanel: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NowPlayingModel.self) private var music
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(timer.mode.title, systemImage: timer.mode.symbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(timer.sessionsToday) today")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .center) {
                Text(timer.timeString)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.displaySeconds)
                Spacer()
                Button { timer.reset() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 30, height: 30) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Button { timer.primaryAction() } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill").frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(timer.mode.accent)
            }
            if let t = music.track {
                HStack(spacing: 10) {
                    Group {
                        if let img = music.artwork { Image(nsImage: img).resizable().scaledToFill() } else { t.source.tint }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(t.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { music.playPause() } label: { Image(systemName: t.isPlaying == true ? "pause.fill" : "play.fill") }
                        .buttonStyle(.plain)
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                        .buttonStyle(.plain)
                }
                .disabled(!music.canControl)
            }
            Divider()
            HStack {
                Button("Open Orbit") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Button("Mini Timer") { MiniPlayerController.shared.toggle(timer: timer, music: music) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
    }
}
