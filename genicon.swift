import Cocoa

let image = NSImage(size: CGSize(width: 1024, height: 1024))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// Background gradient - fills entire 1024x1024
let bgColors = [
    NSColor(red: 1, green: 0.97, blue: 0.72, alpha: 1).cgColor,
    NSColor(red: 0.95, green: 0.87, blue: 0.45, alpha: 1).cgColor,
] as CFArray
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])

// Fold corner
let fold = CGMutablePath()
fold.move(to: CGPoint(x: 856, y: 1024))
fold.addLine(to: CGPoint(x: 1024, y: 856))
fold.addLine(to: CGPoint(x: 1024, y: 1024))
fold.closeSubpath()
ctx.addPath(fold)
ctx.setFillColor(NSColor(red: 0.82, green: 0.78, blue: 0.42, alpha: 1).cgColor)
ctx.fillPath()

// Fold edge line
ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.1).cgColor)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
let edge = CGMutablePath()
edge.move(to: CGPoint(x: 856, y: 1024))
edge.addLine(to: CGPoint(x: 1024, y: 856))
ctx.addPath(edge)
ctx.strokePath()

// Text lines
ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.1).cgColor)
ctx.setLineWidth(10)
ctx.setLineCap(.round)
for i in 0..<5 {
    let y = 780.0 - CGFloat(i) * 110.0
    let toX: CGFloat = i == 4 ? 140 + (884 - 140) * 0.6 : 884
    let line = CGMutablePath()
    line.move(to: CGPoint(x: 140, y: y))
    line.addLine(to: CGPoint(x: toX, y: y))
    ctx.addPath(line)
    ctx.strokePath()
}

// Pin
ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.2).cgColor)
ctx.setLineWidth(10)
ctx.setLineCap(.round)
let pin = CGMutablePath()
pin.move(to: CGPoint(x: 170, y: 868))
pin.addLine(to: CGPoint(x: 170, y: 848))
pin.addArc(center: CGPoint(x: 170, y: 838), radius: 10, startAngle: 0, endAngle: .pi * 2, clockwise: true)
ctx.addPath(pin)
ctx.strokePath()

// Top-left highlight
ctx.saveGState()
let hlColors = [
    NSColor.white.withAlphaComponent(0.3).cgColor,
    NSColor.white.withAlphaComponent(0).cgColor,
] as CFArray
let hlGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: hlColors, locations: [0, 1])!
ctx.clip(to: CGRect(x: 0, y: 860, width: 450, height: 164))
ctx.drawLinearGradient(hlGradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 860), options: [])
ctx.restoreGState()

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:])
else {
    print("Failed to create PNG data")
    exit(1)
}

let appBundlePath = CommandLine.arguments.dropFirst().first ?? "Sticky Notes.app"
let iconPath = URL(fileURLWithPath: appBundlePath)
    .appendingPathComponent("Contents")
    .appendingPathComponent("Resources")
    .appendingPathComponent("icon.png")

try pngData.write(to: iconPath)
print("Icon saved")
