import AppKit
// Renders the Orbit app icon (1024px) to the path given.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
// shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()
squircle.addClip()
let bg = NSGradient(colors: [NSColor(red: 0.12, green: 0.07, blue: 0.35, alpha: 1),
                             NSColor(red: 0.43, green: 0.16, blue: 0.85, alpha: 1),
                             NSColor(red: 0.86, green: 0.15, blue: 0.47, alpha: 1)])!
bg.draw(in: rect, angle: -55)
// glow
let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), .clear])!
glow.draw(fromCenter: NSPoint(x: S*0.38, y: S*0.68), radius: 0, toCenter: NSPoint(x: S*0.38, y: S*0.68), radius: 420, options: [])
// glass disc
let c = NSPoint(x: S/2, y: S/2)
let disc = NSBezierPath(ovalIn: CGRect(x: c.x-270, y: c.y-270, width: 540, height: 540))
NSColor.white.withAlphaComponent(0.12).setFill(); disc.fill()
NSColor.white.withAlphaComponent(0.35).setStroke(); disc.lineWidth = 4; disc.stroke()
// track
let track = NSBezierPath(); track.appendArc(withCenter: c, radius: 215, startAngle: 0, endAngle: 360)
track.lineWidth = 46; NSColor.white.withAlphaComponent(0.15).setStroke(); track.stroke()
// progress arc (clockwise from 12 o'clock, ~70%)
let arc = NSBezierPath(); arc.appendArc(withCenter: c, radius: 215, startAngle: 90, endAngle: 90 - 252, clockwise: true)
arc.lineWidth = 46; arc.lineCapStyle = .round
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: NSColor(red: 1, green: 0.6, blue: 0.9, alpha: 0.9).cgColor)
NSColor.white.setStroke(); arc.stroke()
ctx.restoreGState()
// knob
let a = (90.0 - 252.0) * Double.pi / 180
let k = NSPoint(x: c.x + 215 * cos(a), y: c.y + 215 * sin(a))
let knob = NSBezierPath(ovalIn: CGRect(x: k.x-38, y: k.y-38, width: 76, height: 76))
NSColor(red: 1, green: 0.85, blue: 0.6, alpha: 1).setFill(); knob.fill()
// centre dot
NSColor.white.withAlphaComponent(0.9).setFill()
NSBezierPath(ovalIn: CGRect(x: c.x-26, y: c.y-26, width: 52, height: 52)).fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
