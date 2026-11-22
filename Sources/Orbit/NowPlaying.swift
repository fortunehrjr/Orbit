import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import CoreImage

// MARK: - Types

enum SourceKind: String, CaseIterable, Identifiable {
    case spotify, music, youtube, local
    var id: String { rawValue }

    var label: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Apple Music"
        case .youtube: "YouTube"
        case .local: "On This Mac"
        }
    }

    var symbol: String {
        switch self {
        case .spotify: "dot.radiowaves.right"
        case .music: "music.note"
        case .youtube: "play.rectangle.fill"
        case .local: "laptopcomputer"
        }
    }

    var tint: Color {
        switch self {
        case .spotify: Color(hex: 0x1DB954)
        case .music: Color(hex: 0xFA2D48)
        case .youtube: Color(hex: 0xFF0033)
        case .local: Color(hex: 0x0A84FF)
        }
    }
}

enum MediaCommand { case playPause, next, previous }

enum Browser: String { case chrome = "Google Chrome", safari = "Safari" }

struct YTRef: Equatable {
    var browser: Browser
    var window: String
    var tab: String
    var jsAllowed: Bool
}

struct Track: Equatable {
    var source: SourceKind
    var title: String
    var artist: String
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    /// nil = we can't tell (e.g. YouTube without JavaScript access).
    var isPlaying: Bool? = nil
    var artworkKey = ""
    var fetchedAt = Date()
    var yt: YTRef? = nil

    func livePosition(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let p = position + (isPlaying == true ? date.timeIntervalSince(fetchedAt) : 0)
        return min(max(p, 0), duration)
    }
}

// MARK: - AppleScript bridge (runs off the main thread via osascript)

enum Scripts {
    static let sep = "|~|"
    nonisolated(unsafe) static var triedArt = Set<String>()
    /// Last result per source, for diagnostics ("ok", "not authorized", error text).
    nonisolated(unsafe) static var status: [String: String] = [:]
    nonisolated(unsafe) static var currentTag: String?

    static func run(_ source: String, tag: String) -> String? {
        currentTag = tag
        defer { currentTag = nil }
        return run(source)
    }

    static func run(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        p.standardOutput = out
        let err = Pipe()
        p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let tag = currentTag
        guard p.terminationStatus == 0 else {
            if let tag {
                let e = String(data: errData, encoding: .utf8) ?? ""
                status[tag] = e.contains("-1743") ? "NOT AUTHORIZED (turn on in Privacy & Security › Automation)" : "error: " + e.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
        if let tag { status[tag] = "ok" }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runAsync(_ source: String) {
        Task.detached(priority: .userInitiated) { _ = Scripts.run(source) }
    }

    static func num(_ s: String) -> Double {
        let v = Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
        return v.isFinite ? v : 0
    }

    // Spotify
    static func spotify() -> Track? {
        let src = """
        with timeout of 3 seconds
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (artwork url of t) & "|~|" & (((duration of t) / 1000) as text) & "|~|" & (player position as text)
            end tell
        end timeout
        """
        guard let out = run(src, tag: "Spotify") else { return nil }
        let f = out.components(separatedBy: sep)
        guard f.count >= 7, !f[1].isEmpty else { return nil }
        return Track(source: .spotify, title: f[1], artist: f[2], album: f[3],
                     duration: num(f[5]), position: num(f[6]),
                     isPlaying: f[0] == "playing", artworkKey: f[4])
    }

    // Apple Music
    static func music() -> Track? {
        let src = """
        with timeout of 3 seconds
            tell application "Music"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (persistent ID of t) & "|~|" & ((duration of t) as text) & "|~|" & (player position as text)
            end tell
        end timeout
        """
        guard let out = run(src, tag: "Music") else { return nil }
        let f = out.components(separatedBy: sep)
        guard f.count >= 7, !f[1].isEmpty else { return nil }
        var t = Track(source: .music, title: f[1], artist: f[2], album: f[3],
                      duration: num(f[5]), position: num(f[6]),
                      isPlaying: f[0] == "playing")
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("orbit-art-\(f[4])")
        if !FileManager.default.fileExists(atPath: path), !triedArt.contains(path) {
            triedArt.insert(path)
            dumpMusicArt(to: path)
        }
        if FileManager.default.fileExists(atPath: path) { t.artworkKey = path }
        return t
    }

    static func dumpMusicArt(to path: String) {
        let src = """
        with timeout of 4 seconds
            tell application "Music"
                set t to current track
                if (count of artworks of t) is 0 then return "none"
                set d to raw data of artwork 1 of t
            end tell
        end timeout
        set f to open for access (POSIX file "\(path)") with write permission
        set eof f to 0
        write d to f
        close access f
        return "ok"
        """
        _ = run(src)
    }

    // YouTube
    static let probeJS = "(function(){var v=document.querySelector('video');if(!v)return 'novideo';var c=document.querySelector('ytd-watch-metadata #owner #channel-name a, #owner #channel-name a, ytmusic-player-bar .byline a');return (v.paused?'0':'1')+'^'+v.currentTime+'^'+v.duration+'^'+(c?c.textContent.trim():'');})()"

    static func youtubeChrome() -> [Track] {
        let src = """
        set out to ""
        with timeout of 3 seconds
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u contains "youtube.com/watch" or u contains "youtube.com/shorts/" then
                            set js to "?"
                            try
                                set js to (execute t javascript "\(probeJS)") as text
                            end try
                            set out to out & (id of w as text) & "|~|" & (id of t as text) & "|~|" & u & "|~|" & (title of t) & "|~|" & js & linefeed
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return out
        """
        return parseYT(run(src, tag: "Chrome"), browser: .chrome)
    }

    static func youtubeSafari() -> [Track] {
        let src = """
        set out to ""
        with timeout of 3 seconds
            tell application "Safari"
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set ti to 0
                    try
                        repeat with t in tabs of w
                            set ti to ti + 1
                            try
                                set u to URL of t
                                if u contains "youtube.com/watch" or u contains "youtube.com/shorts/" then
                                    set js to "?"
                                    try
                                        set js to (do JavaScript "\(probeJS)" in t) as text
                                    end try
                                    set out to out & (wi as text) & "|~|" & (ti as text) & "|~|" & u & "|~|" & (name of t) & "|~|" & js & linefeed
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            end tell
        end timeout
        return out
        """
        return parseYT(run(src, tag: "Safari"), browser: .safari)
    }

    static func parseYT(_ out: String?, browser: Browser) -> [Track] {
        guard let out, !out.isEmpty else { return [] }
        return out.split(whereSeparator: \.isNewline).compactMap { line in
            let f = String(line).components(separatedBy: sep)
            guard f.count >= 5 else { return nil }
            let url = f[2]
            var title = f[3]
            if let r = title.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { title.removeSubrange(r) }
            for suffix in [" - YouTube Music", " - YouTube"] where title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count))
            }
            var t = Track(source: .youtube, title: title.isEmpty ? "YouTube" : title,
                          artist: "YouTube · \(browser == .chrome ? "Chrome" : "Safari")")
            if let id = videoID(url) { t.artworkKey = "yt:\(id)" }
            var allowed = false
            let js = f[4]
            let parts = js.components(separatedBy: "^")
            if parts.count >= 4 {
                allowed = true
                t.isPlaying = parts[0] == "1"
                t.position = num(parts[1])
                t.duration = num(parts[2])
                if !parts[3].isEmpty { t.artist = parts[3] }
            } else if js == "novideo" {
                allowed = true
                t.isPlaying = false
            }
            t.yt = YTRef(browser: browser, window: f[0], tab: f[1], jsAllowed: allowed)
            return t
        }
    }

    static func videoID(_ url: String) -> String? {
        guard let c = URLComponents(string: url) else { return nil }
        if let v = c.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        if c.path.contains("/shorts/") { return c.path.components(separatedBy: "/shorts/").last?.components(separatedBy: "/").first }
        return nil
    }

    static func youtube(_ ref: YTRef, js: String) {
        let src: String
        switch ref.browser {
        case .chrome:
            src = "tell application \"Google Chrome\" to execute (tab id \(ref.tab) of window id \(ref.window)) javascript \"\(js)\""
        case .safari:
            src = "tell application \"Safari\" to do JavaScript \"\(js)\" in tab \(ref.tab) of window \(ref.window)"
        }
        runAsync(src)
    }

    // Artwork loading
    static func loadImage(_ key: String) async -> NSImage? {
        if key.hasPrefix("yt:") {
            let id = String(key.dropFirst(3))
            for name in ["maxresdefault", "hqdefault", "mqdefault"] {
                if let img = await fetch("https://i.ytimg.com/vi/\(id)/\(name).jpg") { return img }
            }
            return nil
        }
        if key.hasPrefix("http") { return await fetch(key) }
        return NSImage(contentsOfFile: key)
    }

    private static func fetch(_ s: String) async -> NSImage? {
        guard let url = URL(string: s),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Local music player ("On This Mac")

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.onFinish?() }
    }
}

@MainActor
final class LocalPlayer {
    struct Meta { var title: String; var artist: String; var album: String; var art: NSImage? }

    private(set) var queue: [URL] = []
    private(set) var index = 0
    private var meta: [URL: Meta] = [:]
    private var player: AVAudioPlayer?
    private let delegate = PlayerDelegate()
    var onChange: (() -> Void)?

    init() {
        delegate.onFinish = { [weak self] in
            MainActor.assumeIsolated { self?.advance(by: 1) }
        }
    }

    var hasQueue: Bool { !queue.isEmpty }

    var currentTrack: Track? {
        guard let p = player, queue.indices.contains(index) else { return nil }
        let u = queue[index]
        let m = meta[u]
        return Track(source: .local,
                     title: m?.title ?? u.deletingPathExtension().lastPathComponent,
                     artist: m?.artist ?? "On This Mac",
                     album: m?.album ?? "",
                     duration: p.duration,
                     position: p.currentTime,
                     isPlaying: p.isPlaying,
                     artworkKey: "local:" + u.path)
    }

    var queueLabel: String { queue.isEmpty ? "" : "\(index + 1) of \(queue.count)" }

    func artwork(for key: String) -> NSImage? {
        let path = String(key.dropFirst("local:".count))
        return meta[URL(fileURLWithPath: path)]?.art
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.audio]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.message = "Choose songs, or a whole folder of music"
        p.prompt = "Play"
        NSApp.activate()
        if p.runModal() == .OK { add(p.urls, play: true) }
    }

    private func isAudio(_ u: URL) -> Bool {
        if let t = try? u.resourceValues(forKeys: [.contentTypeKey]).contentType, t.conforms(to: .audio) { return true }
        return ["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac", "caf", "alac"].contains(u.pathExtension.lowercased())
    }

    func add(_ urls: [URL], play: Bool) {
        var files: [URL] = []
        for u in urls {
            if u.hasDirectoryPath {
                let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL { if isAudio(f) { files.append(f) } }
            } else if isAudio(u) {
                files.append(u)
            }
        }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !files.isEmpty else { return }
        let start = queue.count
        queue += files
        files.forEach(loadMeta)
        if play { playIndex(start) }
        onChange?()
    }

    func playIndex(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: queue[i])
        player?.delegate = delegate
        player?.prepareToPlay()
        player?.play()
        onChange?()
    }

    func handle(_ c: MediaCommand) {
        switch c {
        case .playPause:
            guard let p = player else { if hasQueue { playIndex(index) }; return }
            if p.isPlaying { p.pause() } else { p.play() }
        case .next:
            advance(by: 1)
        case .previous:
            if let p = player, p.currentTime > 3 { p.currentTime = 0 } else { advance(by: -1) }
        }
        onChange?()
    }

    private func advance(by d: Int) {
        guard hasQueue else { return }
        let n = index + d
        if n >= queue.count {
            player?.stop()
            player?.currentTime = 0
            onChange?()
        } else {
            playIndex(max(0, n))
        }
    }

    func seek(_ t: Double) {
        player?.currentTime = t
        onChange?()
    }

    private func loadMeta(_ u: URL) {
        Task {
            let asset = AVURLAsset(url: u)
            var m = Meta(title: u.deletingPathExtension().lastPathComponent, artist: "On This Mac", album: "", art: nil)
            if let items = try? await asset.load(.commonMetadata) {
                for item in items {
                    guard let key = item.commonKey else { continue }
                    switch key {
                    case .commonKeyTitle:
                        if let s = try? await item.load(.stringValue), !s.isEmpty { m.title = s }
                    case .commonKeyArtist:
                        if let s = try? await item.load(.stringValue), !s.isEmpty { m.artist = s }
                    case .commonKeyAlbumName:
                        if let s = try? await item.load(.stringValue) { m.album = s }
                    case .commonKeyArtwork:
                        if let d = try? await item.load(.dataValue), let img = NSImage(data: d) { m.art = ArtProcessing.thumbnail(img) }
                    default: break
                    }
                }
            }
            meta[u] = m
            onChange?()
        }
    }
}

// MARK: - Artwork processing

enum ArtProcessing {
    /// Downscale so we never keep a full-resolution bitmap in memory.
    static func thumbnail(_ img: NSImage, maxSide: CGFloat = 360) -> NSImage {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let s = min(1, maxSide / max(w, h))
        let nw = max(1, Int(w * s)), nh = max(1, Int(h * s))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage() else { return img }
        return NSImage(cgImage: out, size: NSSize(width: nw, height: nh))
    }

    /// A tiny, pre-blurred, saturated copy for the card backdrop. Drawing this
    /// costs almost nothing compared with a live `.blur(radius: 50)`.
    static func backdrop(_ img: NSImage) -> NSImage? {
        let small = thumbnail(img, maxSide: 48)
        guard let cg = small.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        let out = ci.clampedToExtent()
            .applyingGaussianBlur(sigma: 4)
            .cropped(to: ci.extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
        guard let result = CIContext().createCGImage(out, from: ci.extent) else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - Now Playing model

@MainActor
@Observable
final class NowPlayingModel {
    var track: Track?
    var artwork: NSImage?
    var backdrop: NSImage?
    var pinned: SourceKind? {
        didSet { UserDefaults.standard.set(pinned?.rawValue, forKey: "pinnedSource"); choose() }
    }

    @ObservationIgnored let local = LocalPlayer()
    @ObservationIgnored private var spotifyTrack: Track?
    @ObservationIgnored private var musicTrack: Track?
    @ObservationIgnored private var ytTracks: [Track] = []
    @ObservationIgnored private var artCache: [String: (art: NSImage, backdrop: NSImage?)] = [:]
    @ObservationIgnored private var artOrder: [String] = []
    @ObservationIgnored private var currentArtKey = ""
    @ObservationIgnored private var loadingKey = ""
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var ytPolling = false
    @ObservationIgnored private var lastFullSync = Date.distantPast
    @ObservationIgnored private var lastStatus = ""

    init() {
        pinned = UserDefaults.standard.string(forKey: "pinnedSource").flatMap(SourceKind.init(rawValue:))
        local.onChange = { [weak self] in self?.choose() }

        // Spotify and Music announce every play/pause/track change, so we
        // listen instead of polling them.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh(.spotify) }
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh(.music) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                switch id {
                case "com.spotify.client": self.spotifyTrack = nil
                case "com.apple.Music": self.musicTrack = nil
                case "com.google.Chrome": self.ytTracks.removeAll { $0.yt?.browser == .chrome }
                case "com.apple.Safari": self.ytTracks.removeAll { $0.yt?.browser == .safari }
                default: return
                }
                self.choose()
            }
        }

        pollTask = Task { [weak self] in
            await self?.syncAll()
            while !Task.isCancelled {
                let wait = self?.youTubeInterval ?? 8
                try? await Task.sleep(for: .seconds(wait))
                guard let self else { return }
                await self.pollYouTube()
                // Safety net for anything a notification missed (e.g. seeking).
                if Date().timeIntervalSince(self.lastFullSync) > 60 { await self.syncAll() }
            }
        }
    }

    /// YouTube has no "now playing" notifications, so it is polled — gently.
    private var youTubeInterval: Double {
        let somethingElsePlaying = spotifyTrack?.isPlaying == true || musicTrack?.isPlaying == true || local.currentTrack?.isPlaying == true
        if somethingElsePlaying && pinned != .youtube { return 20 }
        return AppActivity.shared.isActive ? 4 : 8
    }

    private func runningApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func syncAll() async {
        lastFullSync = Date()
        await refresh(.spotify)
        await refresh(.music)
        await pollYouTube()
    }

    func refresh(_ source: SourceKind) async {
        let running = runningApps()
        switch source {
        case .spotify:
            spotifyTrack = running.contains("com.spotify.client")
                ? await Task.detached(priority: .utility) { Scripts.spotify() }.value : nil
        case .music:
            musicTrack = running.contains("com.apple.Music")
                ? await Task.detached(priority: .utility) { Scripts.music() }.value : nil
        case .youtube:
            await pollYouTube()
            return
        case .local:
            break
        }
        choose()
        writeStatus(running)
    }

    func pollYouTube() async {
        guard !ytPolling else { return }
        ytPolling = true
        defer { ytPolling = false }
        let running = runningApps()
        let chrome = running.contains("com.google.Chrome")
        let safari = running.contains("com.apple.Safari")
        if chrome || safari {
            ytTracks = await Task.detached(priority: .utility) {
                var r: [Track] = []
                if chrome { r += Scripts.youtubeChrome() }
                if safari { r += Scripts.youtubeSafari() }
                return r
            }.value
        } else {
            ytTracks = []
        }
        choose()
        writeStatus(running)
    }

    private func writeStatus(_ running: Set<String>) {
        let ids = ["Spotify": "com.spotify.client", "Music": "com.apple.Music", "Chrome": "com.google.Chrome", "Safari": "com.apple.Safari"]
        var lines: [String] = []
        for name in ["Spotify", "Music", "Chrome", "Safari"] {
            let state = running.contains(ids[name]!) ? (Scripts.status[name] ?? "pending") : "not running"
            lines.append("\(name): \(state)")
        }
        lines.append("YouTube tabs found: \(ytTracks.count)" + (ytTracks.first.map { " — \"\($0.title)\" (controls \($0.yt?.jsAllowed == true ? "on" : "off: enable Allow JavaScript from Apple Events"))" } ?? ""))
        lines.append("Showing: " + (track.map { "\($0.source.label) — \($0.title)" } ?? "nothing"))
        let text = lines.joined(separator: "\n")
        guard text != lastStatus else { return }
        lastStatus = text
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("app.orbit.studytimer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: dir.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    }

    private func choose() {
        var all = [spotifyTrack, musicTrack].compactMap { $0 } + ytTracks
        if let l = local.currentTrack { all.append(l) }
        let pick: Track?
        if let p = pinned {
            pick = all.first { $0.source == p && $0.isPlaying == true } ?? all.first { $0.source == p }
        } else {
            pick = all.first { $0.source == .local && $0.isPlaying == true }
                ?? all.first { $0.isPlaying == true }
                ?? all.first { t in t.source == track?.source && t.title == track?.title }
                ?? all.first { $0.isPlaying == nil }
                ?? all.first
        }
        if let pick, let cur = track, cur.source == pick.source, cur.title == pick.title, cur.artist == pick.artist {
            // Same song: only touch observed state when something visible changed,
            // so the card isn't redrawn on every check.
            let now = Date()
            let drift = abs(cur.livePosition(at: now) - pick.livePosition(at: now))
            if cur.isPlaying != pick.isPlaying || cur.artworkKey != pick.artworkKey
                || abs(cur.duration - pick.duration) > 1 || drift > 2 || cur.yt != pick.yt {
                track = pick
            }
        } else if pick != track {
            withAnimation(.smooth(duration: 0.35)) { track = pick }
        }
        updateArtwork()
    }

    private func setArt(_ art: NSImage?, _ bd: NSImage?) {
        withAnimation(.smooth(duration: 0.5)) {
            artwork = art
            backdrop = bd
        }
    }

    private func updateArtwork() {
        guard let t = track else {
            if artwork != nil { setArt(nil, nil) }
            currentArtKey = ""
            return
        }
        let key = t.artworkKey
        if t.source == .local {
            let img = local.artwork(for: key)
            if currentArtKey != key || (artwork == nil) != (img == nil) {
                setArt(img, img.flatMap(ArtProcessing.backdrop))
            }
            currentArtKey = key
            return
        }
        guard key != currentArtKey else { return }
        if key.isEmpty {
            currentArtKey = key
            setArt(nil, nil)
            return
        }
        if let c = artCache[key] {
            currentArtKey = key
            setArt(c.art, c.backdrop)
            return
        }
        guard key != loadingKey else { return }
        loadingKey = key
        Task { [weak self] in
            let processed: (NSImage, NSImage?)? = await Task.detached(priority: .utility) {
                guard let raw = await Scripts.loadImage(key) else { return nil }
                let thumb = ArtProcessing.thumbnail(raw)
                return (thumb, ArtProcessing.backdrop(thumb))
            }.value
            guard let self else { return }
            self.loadingKey = ""
            if let processed {
                self.artCache[key] = processed
                self.artOrder.append(key)
                if self.artOrder.count > 12 { self.artCache[self.artOrder.removeFirst()] = nil }
            }
            if self.track?.artworkKey == key {
                self.currentArtKey = key
                self.setArt(processed?.0, processed?.1)
            }
        }
    }

    // MARK: Controls

    var canControl: Bool {
        guard let t = track else { return false }
        if t.source == .youtube { return t.yt?.jsAllowed == true }
        return true
    }

    func playPause() { send(.playPause) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    private func send(_ c: MediaCommand) {
        guard let t = track else {
            if c == .playPause && local.hasQueue { local.handle(.playPause) }
            return
        }
        switch t.source {
        case .local:
            local.handle(c)
        case .spotify, .music:
            let app = t.source == .spotify ? "Spotify" : "Music"
            let verb = switch c { case .playPause: "playpause"; case .next: "next track"; case .previous: "previous track" }
            Scripts.runAsync("tell application \"\(app)\" to \(verb)")
        case .youtube:
            guard let ref = t.yt, ref.jsAllowed else { return }
            let js = switch c {
            case .playPause: "(function(){var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}})()"
            case .next: "(function(){var b=document.querySelector('.ytp-next-button, ytmusic-player-bar .next-button');if(b)b.click();})()"
            case .previous: "(function(){var v=document.querySelector('video');if(v&&v.currentTime>3){v.currentTime=0}else{history.back()}})()"
            }
            Scripts.youtube(ref, js: js)
        }
        if c == .playPause, track?.isPlaying != nil {
            let pos = track?.livePosition(at: .now) ?? 0
            track?.isPlaying?.toggle()
            track?.position = pos
            track?.fetchedAt = .now
        }
        repollSoon()
    }

    func seek(to seconds: Double) {
        guard let t = track else { return }
        switch t.source {
        case .local: local.seek(seconds)
        case .spotify: Scripts.runAsync("tell application \"Spotify\" to set player position to \(seconds)")
        case .music: Scripts.runAsync("tell application \"Music\" to set player position to \(seconds)")
        case .youtube:
            if let r = t.yt, r.jsAllowed { Scripts.youtube(r, js: "document.querySelector('video').currentTime=\(seconds)") }
        }
        track?.position = seconds
        track?.fetchedAt = .now
        repollSoon()
    }

    private func repollSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, let source = self.track?.source else { return }
            await self.refresh(source)
        }
    }

    var youtubeHint: String? {
        guard let t = track, t.source == .youtube, let r = t.yt, !r.jsAllowed else { return nil }
        switch r.browser {
        case .chrome: return "To control YouTube, turn on View › Developer › Allow JavaScript from Apple Events in Chrome."
        case .safari: return "To control YouTube, enable Develop › Allow JavaScript from Apple Events in Safari."
        }
    }
}
