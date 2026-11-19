// 生成 AppIcon.icns：swift tools/make_icon.swift && iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
import AppKit

let out = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    NSGradient(starting: NSColor(red: 0.30, green: 0.14, blue: 0.14, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.08, blue: 0.09, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
    let str = NSAttributedString(string: "🍅", attributes: [.font: NSFont.systemFont(ofSize: s * 0.46)])
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
print("✅ \(out)")
