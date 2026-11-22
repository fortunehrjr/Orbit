import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var timer = TimerModel()
    @State private var music = NowPlayingModel()
    @State private var keyMonitor: Any?
    @AppStorage("animatedBackground") private var animatedBackground = false
    @AppStorage("rollingDigits") private var rollingDigits = true

    var body: some Scene {
        Window("Orbit", id: "main") {
            ContentView()
                .environment(timer)
                .environment(music)
                .preferredColorScheme(.dark)
                .containerBackground(.ultraThinMaterial, for: .window)
                .onAppear {
                    installSpaceBar()
                    AppActivity.shared.onBecameVisible = { [timer] in timer.syncDial() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Timer") {
                Button(timer.isRunning ? "Pause" : "Start") { timer.primaryAction() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Reset") { timer.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Skip to Next Session") { timer.skip() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                ForEach(Array(Mode.allCases.enumerated()), id: \.element) { i, m in
                    Button(m.title) { withAnimation(.spring) { timer.select(m) } }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button("Toggle Mini Timer") { MiniPlayerController.shared.toggle(timer: timer, music: music) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Toggle("Rolling Digits", isOn: $rollingDigits)
                Toggle("Animated Background (uses more battery)", isOn: $animatedBackground)
            }
            CommandMenu("Music") {
                Button("Play / Pause") { music.playPause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Next Track") { music.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Track") { music.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Button("Play Music from This Mac…") { music.local.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(timer)
                .environment(music)
        } label: {
            MenuBarLabel(timer: timer)
        }
        .menuBarExtraStyle(.window)
    }

    /// Space toggles the timer — unless you're typing in a text field.
    private func installSpaceBar() {
        guard keyMonitor == nil else { return }
        let timer = timer
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard e.keyCode == 49, mods.isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            MainActor.assumeIsolated { timer.primaryAction() }
            return nil
        }
    }
}
