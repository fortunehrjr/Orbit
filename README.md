# Orbit

**A calm focus timer with your music built in.**

Orbit is a study timer (Pomodoro style) with a big glowing dial: focus, then take a short or long break. Your music plays alongside it, from Spotify, Apple Music, YouTube or files on your Mac.

- Needs: any Mac (Apple silicon or Intel), macOS 26 or later
- Version: 1.1

## Install

Download **`Orbit.dmg`** from this repo's **Releases** page (on the right side of the GitHub page), then:

1. Open `Orbit.dmg` and drag **Orbit** onto **Applications**.
2. Open it. First time only: if macOS says it can't verify the app, go to **System Settings › Privacy & Security** and click **Open Anyway**.
3. Allow notifications when asked, so Orbit can tell you when a session ends.

## Battery friendly

Version 1.1 was tuned for low CPU, GPU and energy use. It sits at **0% CPU when idle**, uses no timers it doesn't need, and stops decorative animations when the window is hidden, the app isn't in front, or Low Power Mode is on. It's a universal app that runs natively on Apple silicon and Intel Macs.

## Use it

1. Pick a mode: **Focus** (25 min, purple), **Short Break** (5 min, teal) or **Long Break** (15 min, blue). You can change the minutes.
2. Type what you're studying.
3. Press start. A **3 · 2 · 1** countdown plays (turn it off in settings), then the dial counts down. The last 10 seconds glow.
4. When a session ends, Orbit celebrates, counts it toward **today's sessions** and moves to the next part of the cycle.

### Music

The **Now Playing** card shows whatever's playing in Spotify, Apple Music or YouTube (in Chrome or Safari), with play/pause, next and previous. You can also choose **Play music from this Mac…** or drop audio files or a folder onto the card.

The first time Orbit reads from one of those apps, macOS asks **"Orbit wants to control …"**. Click **OK**.

### Mini timer

**Toggle Mini Timer** opens a small floating timer with the time, mode and today's count, so you can keep it in view while you work.

### Menu commands

Reset · Skip to Next Session · Toggle Mini Timer · Play / Pause · Next / Previous Track · Play Music from This Mac…

## Update

Quit Orbit, open the new `Orbit.dmg`, drag it to Applications and choose **Replace**.

## Rebuild from source

```bash
./build.sh
```

The app appears at `dist/Orbit.app`. It's a Swift Package, so you can also open `Package.swift` in Xcode.

## Built with

Swift 6.2 toolchain (Swift 5 mode) · SwiftUI · Swift Package Manager · Liquid Glass · UserNotifications · AVFoundation for local music · AppleScript bridge to Spotify, Music, Chrome and Safari (YouTube)
