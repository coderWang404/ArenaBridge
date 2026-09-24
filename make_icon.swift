import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "icon_1024.png"
let variant = args.count > 2 ? (Int(args[2]) ?? 0) : 0

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let c = NSPoint(x: size / 2, y: size / 2)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
}

func squirclePath() -> NSBezierPath {
    let inset = size * 0.088
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    return NSBezierPath(roundedRect: rect, xRadius: size * 0.205, yRadius: size * 0.205)
}

func fillGradient(_ colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)!.draw(in: squirclePath(), angle: angle)
}

func drawSymbol(
    _ name: String,
    pointSize: CGFloat,
    center: NSPoint,
    color: NSColor = .white,
    weight: NSFont.Weight = .semibold
) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("symbol not found: \(name)")
        return
    }
    let s = symbol.size
    symbol.draw(
        at: NSPoint(x: center.x - s.width / 2, y: center.y - s.height / 2),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
}

switch variant {
case 0: // A · 云 ↔ 本机
    fillGradient([rgb(0.38, 0.60, 1.00), rgb(0.20, 0.34, 0.88)], angle: -60)
    drawSymbol("cloud.fill", pointSize: size * 0.295, center: NSPoint(x: c.x, y: c.y + size * 0.180))
    drawSymbol("arrow.up.arrow.down", pointSize: size * 0.105, center: NSPoint(x: c.x, y: c.y), color: NSColor(white: 1, alpha: 0.9), weight: .bold)
    drawSymbol("laptopcomputer", pointSize: size * 0.300, center: NSPoint(x: c.x, y: c.y - size * 0.185))
case 1: // B · 网络节点
    fillGradient([rgb(0.58, 0.38, 0.98), rgb(0.34, 0.18, 0.82)], angle: -60)
    drawSymbol("point.3.connected.trianglepath.dotted", pointSize: size * 0.46, center: c)
case 2: // C · 终端代码
    fillGradient([rgb(0.20, 0.20, 0.28), rgb(0.07, 0.07, 0.12)], angle: -60)
    drawSymbol("chevron.left.forwardslash.chevron.right", pointSize: size * 0.42, center: c, color: rgb(0.19, 0.82, 0.35))
case 3: // D · 隧道门户
    fillGradient([rgb(0.44, 0.36, 0.98), rgb(0.62, 0.24, 0.86)], angle: -60)
    for (i, s) in [CGFloat(0.66), CGFloat(0.50), CGFloat(0.34)].enumerated() {
        let w = size * s
        let rect = NSRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w)
        let path = NSBezierPath(roundedRect: rect, xRadius: w * 0.30, yRadius: w * 0.30)
        NSColor(white: 1, alpha: 0.22 + CGFloat(i) * 0.24).setStroke()
        path.lineWidth = size * 0.030
        path.stroke()
    }
    drawSymbol("arrow.right", pointSize: size * 0.13, center: NSPoint(x: c.x + size * 0.012, y: c.y), weight: .bold)
default: // 旧版
    fillGradient([rgb(0.29, 0.56, 1.00), rgb(0.42, 0.30, 0.96)], angle: -55)
    drawSymbol("arrow.left.arrow.right", pointSize: size * 0.42, center: c)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}
try! png.write(to: URL(fileURLWithPath: output))
print("icon written: \(output) variant \(variant)")
