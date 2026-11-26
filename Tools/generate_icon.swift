// Rebuild with: swift Tools/generate_icon.swift; iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
let sizes = [16, 32, 128, 256, 512]
func draw(_ pixels: Int, forIPad: Bool = false) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels)/1024, y: CGFloat(pixels)/1024)
    let tile = forIPad ? NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)) : NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.23, blue: 0.37, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.10, blue: 0.20, alpha: 1))!.draw(in: tile, angle: -65)
    let page = NSBezierPath(roundedRect: NSRect(x: 235, y: 170, width: 554, height: 690), xRadius: 44, yRadius: 44)
    NSColor(srgbRed: 0.98, green: 0.96, blue: 0.90, alpha: 1).setFill(); page.fill()
    NSColor(srgbRed: 0.72, green: 0.76, blue: 0.76, alpha: 1).setStroke()
    for y in stride(from: 330, through: 610, by: 70) {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 290, y: y)); line.line(to: NSPoint(x: 734, y: y)); line.lineWidth = 9; line.stroke()
    }
    let ink = NSColor(srgbRed: 0.08, green: 0.48, blue: 0.52, alpha: 1)
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: 332, y: 324, width: 142, height: 100)).fill()
    NSBezierPath(ovalIn: NSRect(x: 560, y: 394, width: 142, height: 100)).fill()
    NSBezierPath(roundedRect: NSRect(x: 444, y: 374, width: 30, height: 331), xRadius: 12, yRadius: 12).fill()
    NSBezierPath(roundedRect: NSRect(x: 672, y: 444, width: 30, height: 331), xRadius: 12, yRadius: 12).fill()
    let beam = NSBezierPath(); beam.move(to: NSPoint(x: 444,y: 705)); beam.line(to: NSPoint(x: 702,y: 785)); beam.line(to: NSPoint(x: 702,y: 719)); beam.line(to: NSPoint(x: 444,y: 639)); beam.close(); beam.fill()
    NSGraphicsContext.restoreGraphicsState()
    if forIPad {
        let rgb = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        rgb.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return NSBitmapImageRep(cgImage: rgb.makeImage()!).representation(using: .png, properties: [:])!
    }
    return bitmap.representation(using: .png, properties: [:])!
}
for size in sizes {
    for scale in [1,2] {
        let suffix = scale == 2 ? "@2x" : ""
        try draw(size*scale).write(to: URL(fileURLWithPath: "Resources/AppIcon.iconset/icon_\(size)x\(size)\(suffix).png"))
    }
}

try draw(1024, forIPad: true).write(to: URL(fileURLWithPath: "iPad/Assets.xcassets/AppIcon.appiconset/Icon.png"))
