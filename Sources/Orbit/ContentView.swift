import SwiftUI

struct ContentView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NowPlayingModel.self) private var music
    @State private var bubbles = BubbleField()
    @State private var dialFrame: CGRect = .zero
    @AppStorage("animatedBackground") private var animatedBackground = false

    var body: some View {
        ZStack {
            AmbientBackground(mode: timer.mode, animated: animatedBackground)
            BubbleLayer(field: bubbles, colors: timer.mode.ring)

            GeometryReader { geo in
                let dial = max(280, min(geo.size.height - 290, geo.size.width - 480, 450))
                VStack(spacing: 0) {
                    TopBar()
                        .padding(.top, 12)
                        .padding(.horizontal, 18)

                    HStack(alignment: .center, spacing: 36) {
                        VStack(spacing: 26) {
                            DialView(size: dial)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stage")) } action: { dialFrame = $0 }
                            ControlBar()
                            PresetTray(dialFrame: dialFrame)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 16) {
                            NowPlayingCard()
                            FocusCard()
                        }
                        .frame(width: 340)
                    }
                    .padding(.horizontal, 36)
                    .frame(maxHeight: .infinity)
                }
                .padding(.bottom, 18)
            }

            IntroOverlay()
            ConfettiView(trigger: timer.celebrate, colors: timer.mode.ring + [.white, Color(hex: 0xFDE047)])
        }
        .coordinateSpace(.named("stage"))
        .frame(minWidth: 960, minHeight: 660)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: timer.phase)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NowPlayingModel.self) private var music

    var body: some View {
        ZStack {
            ModePicker()
            HStack(spacing: 10) {
                Spacer()
                GlassCircleButton(symbol: timer.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                  size: 36, help: "Sounds") {
                    timer.soundsOn.toggle()
                }
                GlassCircleButton(symbol: "pip.enter", size: 36, help: "Floating mini timer (⇧⌘M)") {
                    MiniPlayerController.shared.toggle(timer: timer, music: music)
                }
            }
        }
        .frame(height: 44)
    }
}

struct ModePicker: View {
    @Environment(TimerModel.self) private var timer
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { m in
                let selected = m == timer.mode
                Button {
                    guard !selected else { return }
                    Haptics.tick()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { timer.select(m) }
                } label: {
                    Label(m.title, systemImage: m.symbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(LinearGradient(colors: [m.accent, m.ring[1].opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                                    .shadow(color: m.accent.opacity(0.6), radius: 8)
                                    .matchedGeometryEffect(id: "selection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.94))
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Controls

struct ControlBar: View {
    @Environment(TimerModel.self) private var timer

    private var primaryTitle: String {
        switch timer.phase {
        case .idle, .finished: "Start"
        case .intro: "Skip"
        case .running: "Pause"
        case .paused: "Resume"
        }
    }
    private var primarySymbol: String {
        switch timer.phase {
        case .running: "pause.fill"
        case .intro: "forward.fill"
        default: "play.fill"
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 18) {
                GlassCircleButton(symbol: "arrow.counterclockwise", help: "Reset (⌘R)") { timer.reset() }

                Button { timer.primaryAction() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: primarySymbol)
                            .contentTransition(.symbolEffect(.replace))
                        Text(primaryTitle)
                            .contentTransition(.interpolate)
                    }
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 168, height: 56)
                    .contentShape(Capsule())
                    .glassEffect(.regular.tint(timer.mode.accent.opacity(0.85)).interactive(), in: .capsule)
                    .shadow(color: timer.mode.accent.opacity(timer.isRunning ? 0.2 : 0.55), radius: 16, y: 4)
                }
                .buttonStyle(PressableStyle(scale: 0.93))
                .help("Start / Pause (Space)")
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: timer.phase)

                GlassCircleButton(symbol: "forward.end.fill", help: "Skip to next session") { timer.skip() }
            }
        }
    }
}

// MARK: - Draggable preset chips

struct PresetTray: View {
    @Environment(TimerModel.self) private var timer
    var dialFrame: CGRect
    private let presets = [5, 15, 25, 45, 60, 90]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { m in
                    PresetChip(minutes: m, dialFrame: dialFrame)
                }
            }
            Text(timer.canEdit ? "Drag a chip onto the dial — or tap it" : "Presets unlock when the timer stops")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .contentTransition(.interpolate)
        }
        .opacity(timer.canEdit ? 1 : 0.45)
        .animation(.smooth, value: timer.canEdit)
    }
}

struct PresetChip: View {
    @Environment(TimerModel.self) private var timer
    let minutes: Int
    var dialFrame: CGRect

    @State private var offset: CGSize = .zero
    @State private var dragging = false
    @State private var absorbed = false

    private var selected: Bool { timer.canEdit && Int(timer.minutes.rounded()) == minutes }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(minutes)").font(.system(size: 17, weight: .bold, design: .rounded))
            Text("m").font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .frame(width: 58, height: 38)
        .contentShape(Capsule())
        .glassEffect(.regular.tint(selected || dragging ? timer.mode.accent.opacity(0.6) : .clear).interactive(), in: .capsule)
        .scaleEffect(absorbed ? 0.15 : (dragging ? 1.18 : 1))
        .rotationEffect(.degrees(dragging ? Double(max(-14, min(14, offset.width / 10))) : 0))
        .opacity(absorbed ? 0 : 1)
        .shadow(color: .black.opacity(dragging ? 0.35 : 0), radius: 14, y: 8)
        .offset(offset)
        .zIndex(dragging ? 10 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dragging)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("stage"))
                .onChanged { v in
                    guard timer.canEdit else { return }
                    if !dragging { dragging = true; Haptics.tick() }
                    offset = v.translation
                    let over = dialFrame.insetBy(dx: 20, dy: 20).contains(v.location)
                    if over != timer.chipHovering {
                        timer.chipHovering = over
                        if over { Haptics.bump() }
                    }
                }
                .onEnded { v in
                    guard dragging else { return }
                    dragging = false
                    if timer.chipHovering {
                        let target = CGSize(width: v.translation.width + dialFrame.midX - v.location.x,
                                            height: v.translation.height + dialFrame.midY - v.location.y)
                        withAnimation(.easeIn(duration: 0.22)) {
                            offset = target
                            absorbed = true
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
                            timer.chipHovering = false
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                timer.setMinutes(Double(minutes))
                            }
                            timer.play("Pop", volume: 0.7)
                            Haptics.bump()
                            try? await Task.sleep(for: .milliseconds(250))
                            offset = .zero
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { absorbed = false }
                        }
                    } else {
                        timer.chipHovering = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { offset = .zero }
                    }
                }
        )
        .simultaneousGesture(TapGesture().onEnded {
            guard timer.canEdit else { timer.shake += 1; return }
            Haptics.tick()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { timer.setMinutes(Double(minutes)) }
        })
    }
}

// MARK: - Now Playing

struct NowPlayingCard: View {
    @Environment(NowPlayingModel.self) private var music
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("NOW PLAYING").sectionLabel()
                if let t = music.track {
                    EqualizerBars(playing: t.isPlaying == true, color: t.source.tint)
                }
                Spacer()
                SourceMenu()
            }

            if let t = music.track {
                HStack(spacing: 14) {
                    ArtworkView(image: music.artwork, source: t.source, playing: t.isPlaying != false)
                        .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .contentTransition(.interpolate)
                        Text(t.artist)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        SourceBadge(source: t.source, extra: t.source == .local ? music.local.queueLabel : "")
                    }
                    Spacer(minLength: 0)
                }
                .id(t.source.rawValue + t.title)
                .transition(.blurReplace)

                if t.duration > 0 {
                    ProgressScrubber(track: t, tint: t.source.tint) { music.seek(to: $0) }
                }

                HStack(spacing: 26) {
                    Spacer()
                    MediaButton(symbol: "backward.fill", size: 18) { music.previous() }
                    MediaButton(symbol: t.isPlaying == true ? "pause.fill" : "play.fill", size: 26) { music.playPause() }
                    MediaButton(symbol: "forward.fill", size: 18) { music.next() }
                    Spacer()
                }
                .disabled(!music.canControl)
                .opacity(music.canControl ? 1 : 0.35)

                if let hint = music.youtubeHint {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                EmptyNowPlaying()
            }
        }
        .padding(18)
        .background {
            if let bd = music.backdrop {
                Image(nsImage: bd)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .opacity(0.55)
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: 26))
        .glassCard()
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.white.opacity(dropTargeted ? 0.8 : 0), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        .scaleEffect(dropTargeted ? 1.03 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            music.local.add(urls, play: true)
            return true
        } isTargeted: { dropTargeted = $0 }
    }
}

struct EmptyNowPlaying: View {
    @Environment(NowPlayingModel.self) private var music
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.08))
                    .frame(width: 76, height: 76)
                    .overlay { Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Play something in Spotify, Apple Music or YouTube — it shows up here.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { music.local.openPanel() } label: {
                Label("Play music from this Mac…", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .contentShape(Capsule())
                    .glassEffect(.regular.tint(SourceKind.local.tint.opacity(0.5)).interactive(), in: .capsule)
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            Text("Tip: drop audio files or a folder onto this card")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct SourceMenu: View {
    @Environment(NowPlayingModel.self) private var music
    var body: some View {
        Menu {
            Picker("Source", selection: Binding(get: { music.pinned }, set: { music.pinned = $0 })) {
                Label("Automatic", systemImage: "sparkles").tag(SourceKind?.none)
                Divider()
                ForEach(SourceKind.allCases) { s in
                    Label(s.label, systemImage: s.symbol).tag(SourceKind?.some(s))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Play Music from This Mac…", systemImage: "folder.badge.plus") { music.local.openPanel() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SourceBadge: View {
    let source: SourceKind
    var extra: String = ""
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: source.symbol).font(.system(size: 9, weight: .bold))
            Text(source.label + (extra.isEmpty ? "" : " · \(extra)"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(source.tint.opacity(0.75)))
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let source: SourceKind
    let playing: Bool
    @State private var hover = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                LinearGradient(colors: [source.tint, source.tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: source.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(playing ? 0.45 : 0.2), radius: playing ? 14 : 6, y: playing ? 8 : 3)
        .scaleEffect(playing ? (hover ? 1.06 : 1) : 0.86)
        .rotation3DEffect(.degrees(hover ? 8 : 0), axis: (x: -0.4, y: 1, z: 0))
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: playing)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
    }
}

struct MediaButton: View {
    let symbol: String
    var size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(.white.opacity(hover ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.82))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Apple-Music-style scrubber: grows while you drag it.
struct ProgressScrubber: View {
    let track: Track
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?
    @State private var hover = false

    var body: some View {
        TimelineView(.animation(minimumInterval: AppActivity.shared.isActive ? 0.5 : 1, paused: track.isPlaying != true || !AppActivity.shared.windowVisible)) { tl in
            let live = track.livePosition(at: tl.date)
            let f = dragFraction ?? (track.duration > 0 ? live / track.duration : 0)
            let active = dragFraction != nil || hover
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(active ? 0.95 : 0.75))
                            .frame(width: max(0, geo.size.width * f))
                    }
                    .frame(height: active ? 9 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFraction = max(0, min(1, v.location.x / geo.size.width)) }
                            .onEnded { _ in
                                if let d = dragFraction { onSeek(d * track.duration) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                HStack {
                    Text(formatClock(f * track.duration))
                    Spacer()
                    Text("-" + formatClock(track.duration - f * track.duration))
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        }
        .onHover { hover = $0 }
    }
}

// MARK: - Focus card

struct FocusCard: View {
    @Environment(TimerModel.self) private var timer

    var body: some View {
        @Bindable var timer = timer
        VStack(alignment: .leading, spacing: 14) {
            Text("STUDYING").sectionLabel()
            TextField("What are you working on?", text: $timer.taskName)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

            HStack(alignment: .top) {
                stat("SESSIONS", "\(timer.sessionsToday)")
                Spacer()
                stat("FOCUSED", timer.focusedString)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("CYCLE").sectionLabel()
                    HStack(spacing: 6) {
                        ForEach(1...4, id: \.self) { i in
                            Circle()
                                .fill(i <= timer.cyclePosition ? AnyShapeStyle(LinearGradient(colors: Mode.focus.ring, startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.white.opacity(0.15)))
                                .frame(width: 12, height: 12)
                                .scaleEffect(i == timer.cyclePosition ? 1.2 : 1)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: timer.cyclePosition)
                }
            }

            Toggle(isOn: $timer.introOn) {
                Text("3 · 2 · 1 countdown before starting")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(timer.mode.accent)
        }
        .padding(18)
        .glassCard()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sectionLabel()
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring, value: value)
        }
    }
}

// MARK: - 3·2·1 intro

struct IntroOverlay: View {
    @Environment(TimerModel.self) private var timer

    var body: some View {
        if case .intro(let n) = timer.phase {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { timer.skipIntro() }

                ZStack {
                    Text(n > 0 ? "\(n)" : (timer.mode == .focus ? "Focus" : "Relax"))
                        .font(.system(size: n > 0 ? 190 : 84, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: timer.mode.ring, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: timer.mode.accent.opacity(0.9), radius: 30)
                        .id(n)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 2.4).combined(with: .opacity),
                            removal: .scale(scale: 0.3).combined(with: .opacity)))
                }
                .frame(width: 320, height: 320)
                .glassEffect(.regular.tint(timer.mode.accent.opacity(0.25)), in: Circle())
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("Click anywhere to skip")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 30)
                }
                .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }
}
