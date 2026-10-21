// アプリアイコン (Resources/AppIcon.icns) を生成する。
// 使い方: swift tools/make_icon.swift
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // 1024 基準の座標系で描く
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS アイコンの本体（余白 100px、角丸）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.16, green: 0.18, blue: 0.42, alpha: 1).cgColor,
            NSColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

    // トラックパッド
    let pad = CGRect(x: 232, y: 292, width: 560, height: 440)
    let padPath = CGPath(roundedRect: pad, cornerWidth: 64, cornerHeight: 64, transform: nil)
    ctx.addPath(padPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.fillPath()
    ctx.addPath(padPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
    ctx.setLineWidth(14)
    ctx.strokePath()

    // タッチ位置（指先の波紋）
    let tip = CGPoint(x: 470, y: 560)
    ctx.setFillColor(NSColor(red: 1.0, green: 0.84, blue: 0.3, alpha: 0.30).cgColor)
    ctx.fillEllipse(in: CGRect(x: tip.x - 92, y: tip.y - 92, width: 184, height: 184))
    ctx.setFillColor(NSColor(red: 1.0, green: 0.84, blue: 0.3, alpha: 0.55).cgColor)
    ctx.fillEllipse(in: CGRect(x: tip.x - 52, y: tip.y - 52, width: 104, height: 104))

    // 手の図案（メニューバーと同じ SF Symbol）。指先が波紋の中心に来るよう配置する
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let w = tinted.size.width, h = tinted.size.height
        // シンボルの左上付近が指先
        let origin = CGPoint(x: tip.x - w * 0.18, y: tip.y - h * 0.82)
        if let cg = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: CGRect(origin: origin, size: CGSize(width: w, height: h)))
        }
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset: \(iconset.path)")
