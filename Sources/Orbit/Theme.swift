import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Mode: String, CaseIterable, Identifiable {
    case focus, shortBreak, longBreak
    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "sofa.fill"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .focus: 25
        case .shortBreak: 5
        case .longBreak: 15
        }
    }

    var accent: Color {
        switch self {
        case .focus: Color(hex: 0x8B5CF6)
        case .shortBreak: Color(hex: 0x14B8A6)
        case .longBreak: Color(hex: 0x3B82F6)
        }
    }

    /// Colours for the progress ring / highlights.
    var ring: [Color] {
        switch self {
        case .focus: [Color(hex: 0xA78BFA), Color(hex: 0xF472B6), Color(hex: 0xFB923C)]
        case .shortBreak: [Color(hex: 0x5EEAD4), Color(hex: 0x34D399), Color(hex: 0xBEF264)]
        case .longBreak: [Color(hex: 0x60A5FA), Color(hex: 0x22D3EE), Color(hex: 0xC4B5FD)]
        }
    }

    /// 3x3 mesh gradient colours for the ambient background.
    var mesh: [Color] {
        let hex: [UInt32]
        switch self {
        case .focus:
            hex = [0x0F0A2E, 0x3B1C72, 0x1E1B4B,
                   0x6D28D9, 0xBE185D, 0x312E81,
                   0x1E3A8A, 0x7C3AED, 0x9D174D]
        case .shortBreak:
            hex = [0x042F2E, 0x0F766E, 0x064E3B,
                   0x115E59, 0x0D9488, 0x14532D,
                   0x134E4A, 0x059669, 0x0E7490]
        case .longBreak:
            hex = [0x0B1E3F, 0x1D4ED8, 0x172554,
                   0x0E7490, 0x2563EB, 0x312E81,
                   0x0C4A6E, 0x4F46E5, 0x1E40AF]
        }
        return hex.map { Color(hex: $0) }
    }
}

enum Haptics {
    /// A light detent "tick" on Force Touch trackpads.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    /// A firmer bump.
    static func bump() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

enum Sounds {
    static func play(_ name: String, volume: Float = 0.6) {
        guard let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = volume
        s.play()
    }
}

func formatClock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Tracks whether the app is frontmost / its window is on screen so animations
/// and polling can throttle down and save battery.
@MainActor
@Observable
final class AppActivity {
    static let shared = AppActivity()
    /// Starts false: if Orbit is launched in the background, no "became active"
    /// notification arrives, and assuming true kept animations running unseen.
    var isActive = false
    var windowVisible = true
    /// Low Power Mode on: decorative animations stop entirely.
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// True when it's worth spending frames on decoration.
    var canAnimate: Bool { isActive && windowVisible && !lowPower }
    @ObservationIgnored var onBecameVisible: (() -> Void)?

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = NSApp.isActive }
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = true }
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppActivity.shared.isActive = false }
        }
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppActivity.shared.windowVisible = NSApp.windows.contains {
                    $0.canBecomeMain && $0.occlusionState.contains(.visible)
                }
                if AppActivity.shared.windowVisible { AppActivity.shared.onBecameVisible?() }
            }
        }
    }
}
