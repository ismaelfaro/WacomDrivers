// Draws the app icon (a pen over a tablet) at every size macOS needs and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

func drawIcon(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: s, y: s)

    // Rounded-square background with a blue gradient (Apple's icon grid: 824pt body, 100pt margin).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.95, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.62, alpha: 1)])!
        .draw(in: bg, angle: -90)

    // Tablet: light slab, slightly tilted, with an active-area inset.
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: 512, y: 470)
    NSGraphicsContext.current?.cgContext.rotate(by: -.pi / 14)
    let tablet = NSRect(x: -330, y: -230, width: 660, height: 460)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(roundedRect: tablet, xRadius: 46, yRadius: 46).fill()
    NSColor(calibratedRed: 0.75, green: 0.8, blue: 0.9, alpha: 1).setFill()
    NSBezierPath(roundedRect: tablet.insetBy(dx: 52, dy: 62), xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.current?.cgContext.restoreGState()

    // Pen: diagonal stylus resting on the tablet, nib pointing down-left.
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: 600, y: 560)
    NSGraphicsContext.current?.cgContext.rotate(by: -.pi / 4 + .pi)
    NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: -44, y: 0, width: 88, height: 380), xRadius: 30, yRadius: 30).fill() // barrel
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: -44, y: 330, width: 88, height: 26)).fill() // band
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: -44, y: 0))
    nib.line(to: NSPoint(x: 44, y: 0))
    nib.line(to: NSPoint(x: 0, y: -110))
    nib.close()
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    nib.fill()
    NSGraphicsContext.current?.cgContext.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes: [(name: String, px: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let data = drawIcon(px).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("wrote \(sizes.count) PNGs to \(out)")
