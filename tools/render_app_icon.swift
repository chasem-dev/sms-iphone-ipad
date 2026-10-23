import AppKit

guard CommandLine.arguments.count == 3,
      let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: render_app_icon.swift SOURCE_IMAGE OUTPUT_DIRECTORY")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for pixels in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024] {
    guard let graphics = CGContext(data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Cannot allocate app icon")
    }
    let context = NSGraphicsContext(cgContext: graphics, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(pixels)
    NSColor(srgbRed: 0.025, green: 0.35, blue: 0.58, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    let scale = side * 0.88 / max(artwork.size.width, artwork.size.height)
    let width = artwork.size.width * scale
    let height = artwork.size.height * scale
    artwork.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2,
        width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = graphics.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode app icon")
    }
    try data.write(to: destination.appendingPathComponent("Icon-\(pixels).png"))
}
