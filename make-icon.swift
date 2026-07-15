// Generates AppIcon.icns for FocusBanner.
// Usage: swift make-icon.swift   (writes AppIcon.icns next to this file)

import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-square background with macOS-style margins
let margin: CGFloat = 100
let bgRect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1).setFill()
bg.fill()

// Banner strip across the middle
let strip = NSRect(x: bgRect.minX, y: size / 2 - 110, width: bgRect.width, height: 220)
NSColor(srgbRed: 0.08, green: 0.08, blue: 0.13, alpha: 1).setFill()
strip.fill()

// Yellow "scrolling text" bars, the last one running off the right edge
let yellow = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.4, alpha: 1)
yellow.setFill()
let barY = size / 2 - 45
for (x, w) in [(bgRect.minX + 80, CGFloat(200)), (bgRect.minX + 330, 120), (bgRect.minX + 500, 260)] {
    NSBezierPath(roundedRect: NSRect(x: x, y: barY, width: w, height: 90), xRadius: 45, yRadius: 45).fill()
}
// Partial bar exiting right — clip to the background shape so it stays inside
NSGraphicsContext.saveGraphicsState()
bg.addClip()
NSBezierPath(roundedRect: NSRect(x: bgRect.maxX - 120, y: barY, width: 300, height: 90),
             xRadius: 45, yRadius: 45).fill()
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let pngURL = dir.appendingPathComponent("icon-1024.png")
try! png.write(to: pngURL)
print("wrote \(pngURL.path)")
