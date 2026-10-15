import AppKit

// Renders a 1024×1024 app icon: dark squircle with a notch motif + accent widgets.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background squircle (macOS icon shape, ~10% inset).
let inset: CGFloat = 90
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
let grad = NSGradient(colors: [NSColor(calibratedWhite: 0.10, alpha: 1),
                               NSColor(calibratedWhite: 0.03, alpha: 1)])!
bg.addClip()
grad.draw(in: rect, angle: -90)

// Accent.
let accent = NSColor(srgbRed: 0.46, green: 0.51, blue: 0.97, alpha: 1)

// The notch cap near the top-center (rounded-bottom black bar with accent edge).
let capW: CGFloat = 360, capH: CGFloat = 120
let capX = (S - capW) / 2
let capY = rect.maxY - capH        // top
let cap = NSBezierPath()
cap.move(to: CGPoint(x: capX, y: capY + capH))
cap.line(to: CGPoint(x: capX, y: capY + 40))
cap.curve(to: CGPoint(x: capX + 40, y: capY),
          controlPoint1: CGPoint(x: capX, y: capY + 12),
          controlPoint2: CGPoint(x: capX + 12, y: capY))
cap.line(to: CGPoint(x: capX + capW - 40, y: capY))
cap.curve(to: CGPoint(x: capX + capW, y: capY + 40),
          controlPoint1: CGPoint(x: capX + capW - 12, y: capY),
          controlPoint2: CGPoint(x: capX + capW, y: capY + 12))
cap.line(to: CGPoint(x: capX + capW, y: capY + capH))
cap.close()
NSColor.black.setFill(); cap.fill()

// Accent "panel" dropping below the notch (the app's signature morph).
let panelW: CGFloat = 300, panelH: CGFloat = 250
let panel = NSBezierPath(roundedRect:
    CGRect(x: (S - panelW) / 2, y: capY - panelH - 30, width: panelW, height: panelH),
    xRadius: 56, yRadius: 56)
accent.withAlphaComponent(0.16).setFill(); panel.fill()
accent.withAlphaComponent(0.9).setStroke(); panel.lineWidth = 8; panel.stroke()

// Three widget dots inside the panel.
for i in 0..<3 {
    let d: CGFloat = 46
    let x = (S - panelW) / 2 + 60 + CGFloat(i) * 90
    let dot = NSBezierPath(ovalIn: CGRect(x: x, y: capY - panelH + 90, width: d, height: d))
    (i == 1 ? accent : accent.withAlphaComponent(0.5)).setFill(); dot.fill()
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try? png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
