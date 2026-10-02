// Run from the project root: swift scripts/generate-icon.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    throw CocoaError(.coderInvalidValue)
}
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let base = NSColor(srgbRed: 0.063, green: 0.082, blue: 0.075, alpha: 1)
let top = NSColor(srgbRed: 0.12, green: 0.19, blue: 0.15, alpha: 1)
NSGradient(starting: base, ending: top)!.draw(in: bounds, angle: 70)

// Three rising blocks form a compact, legible mark at home-screen size.
let mint = NSColor(srgbRed: 0.60, green: 0.88, blue: 0.70, alpha: 1)
let blocks: [(CGFloat, CGFloat, CGFloat)] = [(232, 260, 228), (444, 260, 374), (656, 260, 520)]
for (index, block) in blocks.enumerated() {
    mint.withAlphaComponent([0.55, 0.76, 1][index]).setFill()
    NSBezierPath(roundedRect: NSRect(x: block.0, y: block.1, width: 136, height: block.2), xRadius: 50, yRadius: 50).fill()
}
NSGraphicsContext.restoreGraphicsState()
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("BorsaApp/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
guard let icon = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent("AppIcon.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw CocoaError(.fileWriteUnknown)
}
CGImageDestinationAddImage(destination, icon, nil)
guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
let manifest = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try Data(manifest.utf8).write(to: directory.appendingPathComponent("Contents.json"))
print("AppIcon.png generated (1024 × 1024, opaque)")
