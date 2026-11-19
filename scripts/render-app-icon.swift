import AppKit
// Usage: swift scripts/render-app-icon.swift App/Assets.xcassets/AppIcon.appiconset
// Renders the Zeigarnik icon (same geometry as docs/assets/app-icon.svg, 1024 grid) at every macOS icon size, transparent outside the squircle.
let out = CommandLine.arguments[1]
let blue = CGColor(srgbRed: 0x0a/255, green: 0x84/255, blue: 0xff/255, alpha: 1)
let orange = CGColor(srgbRed: 0xfb/255, green: 0x92/255, blue: 0x3c/255, alpha: 1)
let base = CGColor(srgbRed: 0x1c/255, green: 0x1c/255, blue: 0x1e/255, alpha: 1)
let top: [CGPoint] = [.init(x: 273.8, y: 319.7), .init(x: 548.5, y: 319.7), .init(x: 370.6, y: 604.3)]
let bottom: [CGPoint] = [.init(x: 653.4, y: 419.7), .init(x: 475.5, y: 704.3), .init(x: 750.2, y: 704.3)]
func render(_ px: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: s, y: -s)   // SVG coordinates, y down
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle); ctx.setFillColor(base); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100.5, y: 100.5, width: 823, height: 823), cornerWidth: 184.5, cornerHeight: 184.5, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08)); ctx.setLineWidth(1); ctx.strokePath()
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(123.6)
    for (points, color) in [(top, blue), (bottom, orange)] {
        ctx.beginPath(); ctx.addLines(between: points); ctx.setStrokeColor(color); ctx.strokePath()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}
var images: [[String: String]] = []
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: URL(fileURLWithPath: out + "/" + name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: out + "/Contents.json"))
