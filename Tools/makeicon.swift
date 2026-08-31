#!/usr/bin/env swift

// Renders Resources/AppIcon.svg to Resources/AppIcon.icns:
//
//     swift Tools/makeicon.swift
//
// Not part of the build — the result is committed. macOS reads SVG itself
// (`_NSSVGImageRep`), so no rsvg or Inkscape needed.

import AppKit
import Foundation

/// Share of the edge length the artwork takes up. Apple's grid leaves a margin —
/// 824 of 1024 points — without which Roger looks bigger in the Dock than every
/// app beside it. Set to 1 for full bleed.
let motifScale: CGFloat = 0.82

/// One single and one double resolution per base size.
let baseSizes = [16, 32, 128, 256, 512]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appending(path: "Resources/AppIcon.svg")
let iconset = root.appending(path: "Resources/AppIcon.iconset")
let destination = root.appending(path: "Resources/AppIcon.icns")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("makeicon: \(message)\n".utf8))
    exit(1)
}

guard let artwork = NSImage(contentsOf: source) else {
    fail("\(source.path) ließ sich nicht laden.")
}

func render(edge: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: edge,
        pixelsHigh: edge,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("Bitmap für \(edge) px ließ sich nicht anlegen.")
    }
    bitmap.size = NSSize(width: edge, height: edge)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let motif = CGFloat(edge) * motifScale
    let inset = (CGFloat(edge) - motif) / 2
    artwork.draw(
        in: NSRect(x: inset, y: inset, width: motif, height: motif),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("PNG für \(edge) px ließ sich nicht erzeugen.")
    }
    return png
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in baseSizes {
    for scale in [1, 2] {
        let edge = base * scale
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(base)x\(base)\(suffix).png"
        try render(edge: edge).write(to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil endete mit \(iconutil.terminationStatus).")
}

// The iconset is an intermediate; only SVG and ICNS are committed.
try? FileManager.default.removeItem(at: iconset)

print("geschrieben: \(destination.path)")
