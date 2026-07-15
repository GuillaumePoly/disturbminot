// Focus Banner — a scrolling status marquee pinned to the top of the screen.
//
// Two modes, switchable from the menu bar:
//   • Focus     — "do not disturb" (default)
//   • Available — "feel free to interrupt", with its own message and colors
//
// All customization lives in one Settings window (menu bar icon → Settings…).
// Settings persist to ~/.config/focusbanner.json. Command-line flags override
// saved values at launch:
//   focusbanner "Focus message" [--speed px/s] [--height px] [--font-size pt]
//               [--bg RRGGBB] [--fg RRGGBB]
//
// The banner floats above all windows, shows on every Space (including
// full-screen apps), and is click-through so it never steals your mouse.

import AppKit
import ApplicationServices

// MARK: - Persisted settings

enum Mode: String { case focus, available }

struct ModeStyleData: Codable {
    var message: String?
    var fgColor: [Double]?   // sRGB r, g, b, a in 0...1
    var bgColor: [Double]?
}

struct Settings: Codable {
    // Legacy v1 keys (single-mode era) — migrated into `focus` on load.
    var message: String?
    var fgColor: [Double]?
    var bgColor: [Double]?

    var mode: String?
    var focus: ModeStyleData?
    var available: ModeStyleData?
    var speed: Double?
    var barHeight: Double?
    var fontName: String?
    var fontSize: Double?
    var screenName: String?  // nil = all displays
    var glow: Bool?
    var crt: Bool?
    var keepBelow: Bool?
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/focusbanner.json")

func loadSettings() -> Settings? {
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    return try? JSONDecoder().decode(Settings.self, from: data)
}

func writeSettings(_ s: Settings) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(s) else { return }
    try? FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try? data.write(to: configURL, options: .atomic)
}

func rgbaComponents(_ c: NSColor) -> [Double] {
    let s = c.usingColorSpace(.sRGB) ?? c
    return [Double(s.redComponent), Double(s.greenComponent),
            Double(s.blueComponent), Double(s.alphaComponent)]
}

func colorFromComponents(_ a: [Double]?) -> NSColor? {
    guard let a, a.count == 4 else { return nil }
    return NSColor(srgbRed: a[0], green: a[1], blue: a[2], alpha: a[3])
}

func hexColor(_ hex: String) -> NSColor {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return .black }
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255,
                   alpha: 1)
}

// MARK: - Runtime state (defaults < config file < command-line flags)

struct ModeStyle {
    var message: String
    var fg: NSColor
    var bg: NSColor
}

var cliMessage: String?
var cliSpeed: Double?
var cliHeight: Double?
var cliFontSize: Double?
var cliBg: String?
var cliFg: String?

do {
    let args = Array(CommandLine.arguments.dropFirst())
    var positional: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        func nextValue() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        switch a {
        case "--speed":     if let v = nextValue() { cliSpeed = Double(v) }
        case "--height":    if let v = nextValue() { cliHeight = Double(v) }
        case "--font-size": if let v = nextValue() { cliFontSize = Double(v) }
        case "--bg":        if let v = nextValue() { cliBg = v }
        case "--fg":        if let v = nextValue() { cliFg = v }
        case "--help", "-h":
            print("usage: focusbanner [focus message] [--speed px/s] [--height px] [--font-size pt] [--bg RRGGBB] [--fg RRGGBB]")
            print("settings are saved to \(configURL.path)")
            exit(0)
        default:
            positional.append(a)
        }
        i += 1
    }
    if !positional.isEmpty { cliMessage = positional.joined(separator: " ") }
}

let saved = loadSettings()

// Focus style, with migration from the legacy single-mode keys.
var focusStyle = ModeStyle(
    message: cliMessage ?? saved?.focus?.message ?? saved?.message
        ?? "🎧  Deep work in progress — please don't interrupt. Ping me on Slack instead 🙏",
    fg: cliFg.map(hexColor) ?? colorFromComponents(saved?.focus?.fgColor)
        ?? colorFromComponents(saved?.fgColor) ?? hexColor("FFD866"),
    bg: cliBg.map { hexColor($0).withAlphaComponent(0.94) }
        ?? colorFromComponents(saved?.focus?.bgColor)
        ?? colorFromComponents(saved?.bgColor) ?? hexColor("1E1E2E").withAlphaComponent(0.94))

var availableStyle = ModeStyle(
    message: saved?.available?.message
        ?? "🙂  Feel free to interrupt — I'm available!",
    fg: colorFromComponents(saved?.available?.fgColor)
        ?? NSColor(srgbRed: 0.87, green: 0.97, blue: 0.89, alpha: 1),
    bg: colorFromComponents(saved?.available?.bgColor)
        ?? NSColor(srgbRed: 0.09, green: 0.28, blue: 0.15, alpha: 0.94))

var currentMode: Mode = Mode(rawValue: saved?.mode ?? "") ?? .focus
var speed = cliSpeed ?? saved?.speed ?? 100                       // pixels per second
var barHeight = CGFloat(cliHeight ?? saved?.barHeight ?? 30)
let initialFontSize = CGFloat(cliFontSize ?? saved?.fontSize ?? 16)
var bannerFont = saved?.fontName.flatMap { NSFont(name: $0, size: initialFontSize) }
    ?? NSFont.systemFont(ofSize: initialFontSize, weight: .semibold)

// MARK: - Views

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Horizontal scanlines drawn over the banner for the CRT effect.
final class ScanlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        var y: CGFloat = 0
        while y < bounds.height {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            y += 3
        }
    }
}

// MARK: - App

final class BannerApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTextFieldDelegate {
    var windows: [NSWindow] = []
    var labels: [[NSTextField]] = []   // two leapfrogging labels per window
    var overlays: [NSView] = []        // CRT scanline overlays, one per window
    var timer: Timer?
    var sweepTimer: Timer?
    var statusItem: NSStatusItem?
    var focusModeItem: NSMenuItem?
    var availableModeItem: NSMenuItem?
    var selectedDisplayID: CGDirectDisplayID?           // nil = all displays
    var selectedScreenName: String? = saved?.screenName // persisted by name (IDs change across reboots)
    var paused = false
    var glowEnabled = saved?.glow ?? false
    var crtEnabled = saved?.crt ?? false
    var keepBelowEnabled = saved?.keepBelow ?? false

    var style: ModeStyle { currentMode == .focus ? focusStyle : availableStyle }

    // Settings window and its controls
    var settingsWindow: NSWindow?
    var modeSeg: NSSegmentedControl!
    var focusMsgField: NSTextField!
    var availMsgField: NSTextField!
    var focusFgWell: NSColorWell!
    var focusBgWell: NSColorWell!
    var availFgWell: NSColorWell!
    var availBgWell: NSColorWell!
    var fontLabel: NSTextField!
    var fontSizeSlider: NSSlider!
    var fontSizeValue: NSTextField!
    var heightSlider: NSSlider!
    var heightValue: NSTextField!
    var speedSlider: NSSlider!
    var speedValue: NSTextField!
    var screenPopup: NSPopUpButton!
    var glowCheck: NSButton!
    var crtCheck: NSButton!
    var keepBelowCheck: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSColorPanel.shared.showsAlpha = true
        if let name = selectedScreenName {
            selectedDisplayID = NSScreen.screens.first { $0.localizedName == name }?.displayID
        }
        rebuildWindows()
        setUpStatusItem()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let sweep = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.enforceWindowsBelow() }
        RunLoop.main.add(sweep, forMode: .common)
        sweepTimer = sweep

        // Reposition banners when displays are plugged in, removed, or rearranged.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    func saveSettings() {
        var s = Settings()
        s.mode = currentMode.rawValue
        s.focus = ModeStyleData(message: focusStyle.message,
                                fgColor: rgbaComponents(focusStyle.fg),
                                bgColor: rgbaComponents(focusStyle.bg))
        s.available = ModeStyleData(message: availableStyle.message,
                                    fgColor: rgbaComponents(availableStyle.fg),
                                    bgColor: rgbaComponents(availableStyle.bg))
        s.speed = speed
        s.barHeight = Double(barHeight)
        s.fontName = bannerFont.fontName
        s.fontSize = Double(bannerFont.pointSize)
        s.screenName = selectedScreenName
        s.glow = glowEnabled
        s.crt = crtEnabled
        s.keepBelow = keepBelowEnabled
        writeSettings(s)
    }

    // MARK: Banner windows

    private func rebuildWindows() {
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        labels.removeAll()
        var screens = NSScreen.screens
        if let id = selectedDisplayID {
            let matching = screens.filter { $0.displayID == id }
            // Fall back to all displays if the chosen one was unplugged.
            if !matching.isEmpty { screens = matching }
        }
        for screen in screens {
            setUpBanner(on: screen)
        }
        rebuildAllLabels()
    }

    private func setUpBanner(on screen: NSScreen) {
        // visibleFrame excludes the menu bar, so the banner sits just below it.
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.minX, y: vf.maxY - barHeight, width: vf.width, height: barHeight)

        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.backgroundColor = style.bg
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.orderFrontRegardless()
        windows.append(window)
    }

    private func rebuildAllLabels() {
        for pair in labels {
            for l in pair { l.removeFromSuperview() }
        }
        labels.removeAll()

        let unit = style.message + "      ✦      "
        let unitWidth = (unit as NSString).size(withAttributes: [.font: bannerFont]).width
        guard unitWidth > 0 else { return }

        for window in windows {
            let width = window.frame.width
            // Each label must be wider than the window so two of them always cover it.
            let copies = max(1, Int(ceil(width / unitWidth)) + 1)
            let text = String(repeating: unit, count: copies)

            var pair: [NSTextField] = []
            for j in 0..<2 {
                let label = NSTextField(labelWithString: text)
                label.font = bannerFont
                label.textColor = style.fg
                label.shadow = glowEnabled ? glowShadow() : nil
                label.sizeToFit()
                let y = (barHeight - label.frame.height) / 2
                label.setFrameOrigin(NSPoint(x: CGFloat(j) * label.frame.width, y: y))
                window.contentView?.addSubview(label)
                pair.append(label)
            }
            labels.append(pair)
        }
        applyCRTOverlays()
    }

    /// Re-applies the current mode's colors and message to live windows.
    private func applyStyle() {
        for w in windows { w.backgroundColor = style.bg }
        rebuildAllLabels()
    }

    private func glowShadow() -> NSShadow {
        let s = NSShadow()
        s.shadowColor = style.fg.withAlphaComponent(0.9)
        s.shadowBlurRadius = 10
        s.shadowOffset = .zero
        return s
    }

    private func applyGlowToLabels() {
        for pair in labels {
            for l in pair { l.shadow = glowEnabled ? glowShadow() : nil }
        }
    }

    /// Scanline overlays sit above the labels, so re-add them whenever the
    /// label stack is rebuilt.
    private func applyCRTOverlays() {
        for o in overlays { o.removeFromSuperview() }
        overlays.removeAll()
        if crtEnabled {
            for w in windows {
                guard let cv = w.contentView else { continue }
                let v = ScanlineView(frame: cv.bounds)
                v.autoresizingMask = [.width, .height]
                cv.addSubview(v)
                overlays.append(v)
            }
        }
    }

    /// Grow the bar if the current font no longer fits, then rebuild.
    private func refreshAfterAppearanceChange() {
        let needed = ceil(bannerFont.boundingRectForFont.height) + 8
        if barHeight < needed {
            barHeight = needed
            rebuildWindows()
            syncSettingsControls()
        } else {
            rebuildAllLabels()
        }
    }

    // MARK: Keep other windows below the banner

    /// Banner strips in top-left (Accessibility/CoreGraphics) coordinates.
    private func bannerStripsTopLeft() -> [CGRect] {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return [] }
        return windows.map { w in
            CGRect(x: w.frame.minX, y: primaryMaxY - w.frame.maxY,
                   width: w.frame.width, height: w.frame.height)
        }
    }

    /// Every 0.5s: push any normal window overlapping a banner strip down
    /// below it. Requires the Accessibility permission.
    private func enforceWindowsBelow() {
        guard keepBelowEnabled, AXIsProcessTrusted() else { return }
        let strips = bannerStripsTopLeft()
        guard !strips.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return }

        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return }
        let screenFramesTL = NSScreen.screens.map { s in
            CGRect(x: s.frame.minX, y: primaryMaxY - s.frame.maxY,
                   width: s.frame.width, height: s.frame.height)
        }

        let myPid = getpid()
        var pids: Set<pid_t> = []
        for w in info {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if strips.contains(where: { $0.intersects(rect) }) { pids.insert(pid) }
        }

        for pid in pids {
            let appEl = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
                  let winList = value as? [AXUIElement] else { continue }
            for win in winList {
                guard let pos = axPoint(win), let size = axSize(win) else { continue }
                let frame = CGRect(origin: pos, size: size)
                // Leave full-screen windows alone.
                if screenFramesTL.contains(where: { abs($0.minX - frame.minX) < 2 && abs($0.minY - frame.minY) < 2
                                                    && abs($0.width - frame.width) < 2 && abs($0.height - frame.height) < 2 }) {
                    continue
                }
                for strip in strips where frame.intersects(strip) && pos.y < strip.maxY {
                    var p = CGPoint(x: pos.x, y: strip.maxY)
                    if let v = AXValueCreate(.cgPoint, &p) {
                        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
                    }
                }
            }
        }
    }

    private func axPoint(_ el: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var out = CGPoint.zero
        guard AXValueGetValue(ref as! AXValue, .cgPoint, &out) else { return nil }
        return out
    }

    private func axSize(_ el: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var out = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &out) else { return nil }
        return out
    }

    // MARK: Animation

    private func tick() {
        guard !paused else { return }
        let dx = CGFloat(speed) / 60.0
        for pair in labels {
            for l in pair {
                l.setFrameOrigin(NSPoint(x: l.frame.origin.x - dx, y: l.frame.origin.y))
            }
            for l in pair where l.frame.maxX <= 0 {
                let rightmost = pair.map { $0.frame.maxX }.max() ?? 0
                l.setFrameOrigin(NSPoint(x: rightmost, y: l.frame.origin.y))
            }
        }
    }

    // MARK: Menu bar item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "Focus Banner")
            ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Focus Banner") {
            icon.isTemplate = true   // adapts to light/dark menu bar
            item.button?.image = icon
        } else {
            item.button?.title = "🎧"
        }
        item.button?.toolTip = "Focus Banner"

        let menu = NSMenu()

        let focus = NSMenuItem(title: "Focus — Do Not Disturb", action: #selector(activateFocusMode), keyEquivalent: "1")
        focus.target = self
        menu.addItem(focus)
        focusModeItem = focus

        let avail = NSMenuItem(title: "Available — Interruptions Welcome", action: #selector(activateAvailableMode), keyEquivalent: "2")
        avail.target = self
        menu.addItem(avail)
        availableModeItem = avail

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Scrolling", action: #selector(togglePause(_:)), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Focus Banner", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        syncModeChecks()
    }

    private func syncModeChecks() {
        focusModeItem?.state = (currentMode == .focus) ? .on : .off
        availableModeItem?.state = (currentMode == .available) ? .on : .off
        modeSeg?.selectedSegment = (currentMode == .focus) ? 0 : 1
    }

    private func setMode(_ mode: Mode) {
        guard mode != currentMode else { return }
        currentMode = mode
        applyStyle()
        syncModeChecks()
        saveSettings()
    }

    @objc private func activateFocusMode() { setMode(.focus) }
    @objc private func activateAvailableMode() { setMode(.available) }

    @objc private func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        sender.title = paused ? "Resume Scrolling" : "Pause Scrolling"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Settings window

    @objc private func openSettings() {
        if settingsWindow == nil { buildSettingsWindow() }
        syncSettingsControls()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func formLabel(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func smallLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    private func colorWell(_ color: NSColor) -> NSColorWell {
        let w = NSColorWell()
        w.color = color
        w.target = self
        w.action = #selector(wellChanged(_:))
        w.translatesAutoresizingMaskIntoConstraints = false
        w.widthAnchor.constraint(equalToConstant: 44).isActive = true
        w.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return w
    }

    private func buildSettingsWindow() {
        modeSeg = NSSegmentedControl(labels: ["Focus", "Available"], trackingMode: .selectOne,
                                     target: self, action: #selector(modeSegChanged))

        focusMsgField = NSTextField(string: focusStyle.message)
        focusMsgField.delegate = self
        availMsgField = NSTextField(string: availableStyle.message)
        availMsgField.delegate = self
        for f in [focusMsgField!, availMsgField!] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }

        focusFgWell = colorWell(focusStyle.fg)
        focusBgWell = colorWell(focusStyle.bg)
        availFgWell = colorWell(availableStyle.fg)
        availBgWell = colorWell(availableStyle.bg)

        fontLabel = formLabel("")
        let fontButton = NSButton(title: "Change…", target: self, action: #selector(chooseFont))

        fontSizeSlider = NSSlider(value: Double(bannerFont.pointSize), minValue: 10, maxValue: 48,
                                  target: self, action: #selector(fontSizeSliderChanged))
        fontSizeValue = formLabel("")
        heightSlider = NSSlider(value: Double(barHeight), minValue: 20, maxValue: 80,
                                target: self, action: #selector(heightSliderChanged))
        heightValue = formLabel("")
        speedSlider = NSSlider(value: speed, minValue: 30, maxValue: 300,
                               target: self, action: #selector(speedSliderChanged))
        speedValue = formLabel("")
        for s in [fontSizeSlider!, heightSlider!, speedSlider!] {
            s.translatesAutoresizingMaskIntoConstraints = false
            s.widthAnchor.constraint(equalToConstant: 240).isActive = true
        }

        screenPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        screenPopup.target = self
        screenPopup.action = #selector(screenPopupChanged)

        glowCheck = NSButton(checkboxWithTitle: "Glow — neon halo around the text",
                             target: self, action: #selector(glowCheckChanged))
        crtCheck = NSButton(checkboxWithTitle: "CRT effect — scanlines over the banner",
                            target: self, action: #selector(crtCheckChanged))
        keepBelowCheck = NSButton(checkboxWithTitle: "Keep other windows below the banner",
                                  target: self, action: #selector(keepBelowCheckChanged))

        let axNote = smallLabel("Requires the Accessibility permission (System Settings → Privacy & Security).")

        let grid = NSGridView(views: [
            [formLabel("Current mode:"), modeSeg],
            [formLabel("Focus message:"), focusMsgField],
            [formLabel("Focus colors:"), hstack([focusFgWell, smallLabel("Text"), focusBgWell, smallLabel("Background")])],
            [formLabel("Available message:"), availMsgField],
            [formLabel("Available colors:"), hstack([availFgWell, smallLabel("Text"), availBgWell, smallLabel("Background")])],
            [formLabel("Font:"), hstack([fontLabel, fontButton])],
            [formLabel("Font size:"), hstack([fontSizeSlider, fontSizeValue])],
            [formLabel("Bar height:"), hstack([heightSlider, heightValue])],
            [formLabel("Scroll speed:"), hstack([speedSlider, speedValue])],
            [formLabel("Screen:"), screenPopup],
            [NSGridCell.emptyContentView, glowCheck],
            [NSGridCell.emptyContentView, crtCheck],
            [NSGridCell.emptyContentView, keepBelowCheck],
            [NSGridCell.emptyContentView, axNote],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        let win = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Focus Banner Settings"
        win.isReleasedWhenClosed = false
        win.contentView = container
        win.setContentSize(container.fittingSize)
        settingsWindow = win
    }

    /// Pushes current state into the settings controls (values + labels).
    private func syncSettingsControls() {
        guard settingsWindow != nil else { return }
        syncModeChecks()
        focusMsgField.stringValue = focusStyle.message
        availMsgField.stringValue = availableStyle.message
        focusFgWell.color = focusStyle.fg
        focusBgWell.color = focusStyle.bg
        availFgWell.color = availableStyle.fg
        availBgWell.color = availableStyle.bg
        fontLabel.stringValue = "\(bannerFont.displayName ?? bannerFont.fontName)  \(Int(bannerFont.pointSize)) pt"
        fontSizeSlider.doubleValue = Double(bannerFont.pointSize)
        fontSizeValue.stringValue = "\(Int(bannerFont.pointSize)) pt"
        heightSlider.doubleValue = Double(barHeight)
        heightValue.stringValue = "\(Int(barHeight)) px"
        speedSlider.doubleValue = speed
        speedValue.stringValue = "\(Int(speed)) px/s"
        glowCheck.state = glowEnabled ? .on : .off
        crtCheck.state = crtEnabled ? .on : .off
        keepBelowCheck.state = keepBelowEnabled ? .on : .off

        screenPopup.removeAllItems()
        screenPopup.addItem(withTitle: "All Displays")
        for screen in NSScreen.screens {
            screenPopup.addItem(withTitle: screen.localizedName)
        }
        if let name = selectedScreenName, screenPopup.itemTitles.contains(name) {
            screenPopup.selectItem(withTitle: name)
        } else {
            screenPopup.selectItem(at: 0)
        }
    }

    // MARK: Settings actions

    @objc private func modeSegChanged() {
        setMode(modeSeg.selectedSegment == 0 ? .focus : .available)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === focusMsgField {
            focusStyle.message = field.stringValue
            if currentMode == .focus { rebuildAllLabels() }
        } else if field === availMsgField {
            availableStyle.message = field.stringValue
            if currentMode == .available { rebuildAllLabels() }
        }
        saveSettings()
    }

    @objc private func wellChanged(_ sender: NSColorWell) {
        switch sender {
        case focusFgWell:  focusStyle.fg = sender.color
        case focusBgWell:  focusStyle.bg = sender.color
        case availFgWell:  availableStyle.fg = sender.color
        case availBgWell:  availableStyle.bg = sender.color
        default: return
        }
        // Live-update only what's visible; the other mode picks it up on switch.
        for w in windows { w.backgroundColor = style.bg }
        for pair in labels {
            for l in pair { l.textColor = style.fg }
        }
        applyGlowToLabels()   // glow tint follows the text color
        saveSettings()
    }

    @objc private func chooseFont() {
        NSApp.activate(ignoringOtherApps: true)
        let fm = NSFontManager.shared
        fm.target = self
        fm.setSelectedFont(bannerFont, isMultiple: false)
        fm.orderFrontFontPanel(nil)
    }

    /// Called continuously by the font panel as the user picks family/style/size.
    @objc func changeFont(_ sender: Any?) {
        bannerFont = NSFontManager.shared.convert(bannerFont)
        refreshAfterAppearanceChange()
        syncSettingsControls()
        saveSettings()
    }

    @objc private func fontSizeSliderChanged() {
        let size = CGFloat(round(fontSizeSlider.doubleValue))
        bannerFont = NSFont(descriptor: bannerFont.fontDescriptor, size: size) ?? bannerFont
        fontSizeValue.stringValue = "\(Int(size)) pt"
        fontLabel.stringValue = "\(bannerFont.displayName ?? bannerFont.fontName)  \(Int(size)) pt"
        refreshAfterAppearanceChange()
        saveSettings()
    }

    @objc private func heightSliderChanged() {
        barHeight = CGFloat(round(heightSlider.doubleValue))
        heightValue.stringValue = "\(Int(barHeight)) px"
        rebuildWindows()
        saveSettings()
    }

    @objc private func speedSliderChanged() {
        speed = round(speedSlider.doubleValue)
        speedValue.stringValue = "\(Int(speed)) px/s"
        saveSettings()
    }

    @objc private func screenPopupChanged() {
        if screenPopup.indexOfSelectedItem == 0 {
            selectedDisplayID = nil
            selectedScreenName = nil
        } else if let title = screenPopup.titleOfSelectedItem {
            selectedScreenName = title
            selectedDisplayID = NSScreen.screens.first { $0.localizedName == title }?.displayID
        }
        rebuildWindows()
        saveSettings()
    }

    @objc private func glowCheckChanged() {
        glowEnabled = glowCheck.state == .on
        applyGlowToLabels()
        saveSettings()
    }

    @objc private func crtCheckChanged() {
        crtEnabled = crtCheck.state == .on
        applyCRTOverlays()
        saveSettings()
    }

    @objc private func keepBelowCheckChanged() {
        keepBelowEnabled = keepBelowCheck.state == .on
        if keepBelowEnabled && !AXIsProcessTrusted() {
            // Triggers the system dialog pointing to
            // System Settings → Privacy & Security → Accessibility.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        saveSettings()
    }
}

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = BannerApp()
app.delegate = delegate
app.run()
