// Renders docs/preview.png for the README: the two banner modes, stacked.
// Usage: swift make-preview.swift

import AppKit

let width: CGFloat = 1800
let barHeight: CGFloat = 64
let gap: CGFloat = 36
let height = barHeight * 2 + gap

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

func drawBar(y: CGFloat, bg: NSColor, fg: NSColor, message: String) {
    let bar = NSRect(x: 0, y: y, width: width, height: barHeight)
    bg.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()

    let font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let unit = message + "      ✦      "
    var text = unit
    while (text as NSString).size(withAttributes: [.font: font]).width < width {
        text += unit
    }
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
    let textHeight = (text as NSString).size(withAttributes: attrs).height
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).addClip()
    (text as NSString).draw(at: NSPoint(x: 24, y: y + (barHeight - textHeight) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
}

// Focus mode (top)
drawBar(y: barHeight + gap,
        bg: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1),
        fg: NSColor(srgbRed: 1.0, green: 0.84, blue: 0.4, alpha: 1),
        message: "🎧  Deep work in progress — please don't interrupt. Ping me on Slack instead 🙏")

// Available mode (bottom)
drawBar(y: 0,
        bg: NSColor(srgbRed: 0.09, green: 0.28, blue: 0.15, alpha: 1),
        fg: NSColor(srgbRed: 0.87, green: 0.97, blue: 0.89, alpha: 1),
        message: "🙂  Feel free to interrupt — I'm available!")

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render preview\n", stderr)
    exit(1)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("docs")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let out = dir.appendingPathComponent("preview.png")
try! png.write(to: out)
print("wrote \(out.path)")
