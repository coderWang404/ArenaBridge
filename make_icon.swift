import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 90
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.29, green: 0.56, blue: 1.00, alpha: 1.0),
    NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.96, alpha: 1.0)
])!
gradient.draw(in: path, angle: -55)

let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(
        at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}
try! png.write(to: URL(fileURLWithPath: output))
print("icon written: \(output)")
