import Cocoa
import Foundation

func click(x: CGFloat, y: CGFloat) {
    let loc = CGPoint(x: x, y: y)
    let down = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: loc,
        mouseButton: .left
    )!
    let up = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: loc,
        mouseButton: .left
    )!
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    up.post(tap: .cghidEventTap)
}

func windowInfo() -> (CGWindowID, CGRect)? {
    let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let wins = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for w in wins {
        if (w[kCGWindowOwnerName as String] as? String) == "SISR",
           (w[kCGWindowLayer as String] as? Int) == 0,
           let b = w[kCGWindowBounds as String] as? [String: Any]
        {
            let rect = CGRect(
                x: (b["X"] as? NSNumber)?.doubleValue ?? 0,
                y: (b["Y"] as? NSNumber)?.doubleValue ?? 0,
                width: (b["Width"] as? NSNumber)?.doubleValue ?? 0,
                height: (b["Height"] as? NSNumber)?.doubleValue ?? 0
            )
            if rect.width > 400 {
                let id = CGWindowID((w[kCGWindowNumber as String] as? Int) ?? 0)
                return (id, rect)
            }
        }
    }
    return nil
}

func activate() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", "tell application \"SISR\" to activate"]
    try? task.run()
    task.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.4)
}

func capture(_ wid: CGWindowID, to path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l", String(wid), "-o", path]
    try! p.run()
    p.waitUntilExit()
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: ui-click-capture <bitrate|portrait|color>\n", stderr)
    exit(2)
}
let mode = args[1]
activate()
guard let (wid, r) = windowInfo() else {
    fputs("SISR window not found\n", stderr)
    exit(1)
}
print("window \(wid) \(r)")

let shots = "/Users/daveklee/Documents/github/sisr/docs/assets/screenshots"

switch mode {
case "bitrate":
    // Disclosure chevron for Bitrate & quality in left sidebar
    for fy in [0.56, 0.58, 0.60, 0.62, 0.64] as [CGFloat] {
        click(x: r.minX + 28, y: r.minY + r.height * fy)
        Thread.sleep(forTimeInterval: 0.2)
    }
    // Also try clicking the summary label
    click(x: r.minX + 110, y: r.minY + r.height * 0.60)
    Thread.sleep(forTimeInterval: 0.5)
    capture(wid, to: "\(shots)/06-bitrate-advanced.png")
    print("saved bitrate")

case "portrait":
    for pair in [(175.0, 0.37), (190.0, 0.39), (205.0, 0.40), (160.0, 0.41)] as [(CGFloat, CGFloat)] {
        click(x: r.minX + pair.0, y: r.minY + r.height * pair.1)
        Thread.sleep(forTimeInterval: 0.25)
    }
    Thread.sleep(forTimeInterval: 0.5)
    capture(wid, to: "\(shots)/07-portrait-social.png")
    print("saved portrait")

case "color":
    // Expand Color adjustments on right inspector
    click(x: r.maxX - 200, y: r.minY + r.height * 0.55)
    Thread.sleep(forTimeInterval: 0.4)
    capture(wid, to: "\(shots)/03-advanced-controls.png")
    print("saved color")

default:
    fputs("Unknown mode\n", stderr)
    exit(2)
}
