import Cocoa

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // Gradient background
        let gradient = NSGradient(colors: [
            NSColor(red: 0.18, green: 0.50, blue: 0.92, alpha: 1.0),
            NSColor(red: 0.10, green: 0.30, blue: 0.70, alpha: 1.0)
        ])!
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
        gradient.draw(in: path, angle: -45)

        // SF Symbol
        let symbolSize = size * 0.55
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let symbolRect = symbol.size
            let x = (size - symbolRect.width) / 2
            let y = (size - symbolRect.height) / 2
            NSColor.white.setFill()
            symbol.draw(in: NSRect(x: x, y: y, width: symbolRect.width, height: symbolRect.height),
                       from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        return true
    }

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(name)\n", stderr)
        continue
    }
    try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

print("Iconset generated at \(iconsetPath)")
