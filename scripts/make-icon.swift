// Draws the app icon (a treemap on a rounded square) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1)])!.draw(in: bg, angle: -90)
    let g = s * 0.018
    let a = body.insetBy(dx: s * 0.09, dy: s * 0.09)
    let cells: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0, 0, 0.58, 1, .systemBlue),
        (0.58, 0.45, 0.42, 0.55, .systemPurple),
        (0.58, 0, 0.24, 0.45, .systemTeal),
        (0.82, 0.2, 0.18, 0.25, .systemOrange),
        (0.82, 0, 0.18, 0.2, .systemPink),
    ]
    for (x, y, w, h, c) in cells {
        let r = NSRect(x: a.minX + x * a.width + g, y: a.minY + y * a.height + g,
                       width: w * a.width - 2 * g, height: h * a.height - 2 * g)
        let p = NSBezierPath(roundedRect: r, xRadius: s * 0.03, yRadius: s * 0.03)
        NSGradient(colors: [c.highlight(withLevel: 0.25)!, c])!.draw(in: p, angle: -60)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
