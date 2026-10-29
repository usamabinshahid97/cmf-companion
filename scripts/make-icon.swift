import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        NSColor(srgbRed: 0.97, green: 0.31, blue: 0.13, alpha: 1).setFill()
        let inset = CGFloat(pixels) * 0.06
        let rectangle = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
        NSBezierPath(roundedRect: rectangle, xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20).fill()
        if let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: CGFloat(pixels) * 0.52, weight: .regular)) {
            let symbolSize = symbol.size
            let width = CGFloat(pixels) * 0.53
            let height = width * symbolSize.height / symbolSize.width
            let target = NSRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2, width: width, height: height)
            let tinted = NSImage(size: symbolSize)
            tinted.lockFocus()
            let symbolRect = NSRect(origin: .zero, size: symbolSize)
            symbol.draw(in: symbolRect)
            NSColor.white.setFill()
            symbolRect.fill(using: .sourceIn)
            tinted.unlockFocus()
            tinted.draw(in: target)
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let representation = NSBitmapImageRep(data: tiff),
           let png = representation.representation(using: .png, properties: [:]) {
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
}
