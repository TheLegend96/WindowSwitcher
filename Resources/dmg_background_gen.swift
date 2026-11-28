#!/usr/bin/env swift
import Cocoa
import CoreGraphics

// Generates @1x (600x400) and @2x (1200x800) Finder DMG installer background artwork
// combining clean frosted target cards with a subtle curved drag-to-install arrow.

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: generate_dmg_background.swift <out_1x.png> <out_2x.png>\n", stderr)
    exit(1)
}

func renderDMGBackground(scale: CGFloat, to path: String) {
    let widthPt: CGFloat = 600
    let heightPt: CGFloat = 400
    let pxW = Int(widthPt * scale)
    let pxH = Int(heightPt * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxW,
        pixelsHigh: pxH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Failed to allocate bitmap\n", stderr)
        exit(1)
    }
    rep.size = NSSize(width: widthPt, height: heightPt)

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        fputs("Failed to create graphics context\n", stderr)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    // Work in flipped top-down Finder coordinates (0,0 top-left -> 600,400 bottom-right)
    ctx.translateBy(x: 0, y: heightPt)
    ctx.scaleBy(x: 1, y: -1)

    // 1. Calm neutral pearl studio gradient (matches app chrome)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 247/255, green: 248/255, blue: 251/255, alpha: 1.0).cgColor,
        NSColor(red: 233/255, green: 236/255, blue: 243/255, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: widthPt, y: heightPt), options: [])
    }

    // Subtle soft radial studio lift centered behind icons (startRadius: 0 for seamless blend)
    let glowColors = [
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.52).cgColor,
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: 300, y: 170),
            startRadius: 0,
            endCenter: CGPoint(x: 300, y: 170),
            endRadius: 310,
            options: []
        )
    }

    // 2. Left Source Card Plate (clean gap above "WindowSwitcher.app" label)
    let leftPlate = CGRect(x: 101, y: 106, width: 128, height: 128)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.06).cgColor)
    let leftPath = CGPath(roundedRect: leftPlate, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.70).cgColor)
    ctx.addPath(leftPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.07).cgColor)
    ctx.setLineWidth(1.0)
    ctx.addPath(leftPath)
    ctx.strokePath()

    // 3. Right Drop Target Plate
    let rightPlate = CGRect(x: 371, y: 106, width: 128, height: 128)
    let rightPath = CGPath(roundedRect: rightPlate, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.44).cgColor)
    ctx.addPath(rightPath)
    ctx.fillPath()
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.14).cgColor)
    ctx.setLineWidth(1.25)
    ctx.setLineDash(phase: 0, lengths: [5, 4])
    ctx.addPath(rightPath)
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Clean Curved Directional Arc Arrow (OpenBot-inspired, cobalt studio ink)
    let startPt = CGPoint(x: 245, y: 170)
    let endPt = CGPoint(x: 353, y: 170)
    let ctrlPt = CGPoint(x: 299, y: 138)
    let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.78)

    ctx.saveGState()
    ctx.setStrokeColor(accent.cgColor)
    ctx.setLineWidth(2.2)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: startPt)
    ctx.addQuadCurve(to: endPt, control: ctrlPt)
    ctx.strokePath()

    // Subtle origin anchor dot
    ctx.setFillColor(accent.cgColor)
    ctx.fillEllipse(in: CGRect(x: startPt.x - 3.2, y: startPt.y - 3.2, width: 6.4, height: 6.4))

    // Directional chevron aligned seamlessly with tangent at endPt
    let dx = endPt.x - ctrlPt.x
    let dy = endPt.y - ctrlPt.y
    let len = max(0.001, hypot(dx, dy))
    let ux = dx / len
    let uy = dy / len
    let px = -uy
    let py = ux
    let arm: CGFloat = 7.5
    let spread: CGFloat = 5.0

    ctx.move(to: CGPoint(x: endPt.x - ux * arm + px * spread, y: endPt.y - uy * arm + py * spread))
    ctx.addLine(to: endPt)
    ctx.addLine(to: CGPoint(x: endPt.x - ux * arm - px * spread, y: endPt.y - uy * arm - py * spread))
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Calm Plain Instruction Footer
    ctx.saveGState()
    // Temporarily flip back for NSAttributedString baseline drawing
    ctx.translateBy(x: 0, y: heightPt)
    ctx.scaleBy(x: 1, y: -1)
    let label = "Drag Window Switcher to Applications to install" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        .foregroundColor: NSColor(red: 92/255, green: 98/255, blue: 112/255, alpha: 1.0)
    ]
    let tSize = label.size(withAttributes: attrs)
    label.draw(at: NSPoint(x: (widthPt - tSize.width) * 0.5, y: 46), withAttributes: attrs)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG\n", stderr)
        exit(1)
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
    } catch {
        fputs("Failed writing \(path): \(error)\n", stderr)
        exit(1)
    }
}

renderDMGBackground(scale: 1.0, to: args[1])
renderDMGBackground(scale: 2.0, to: args[2])
