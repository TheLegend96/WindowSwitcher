import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - Native macOS Desktop Wallpaper Discovery & Caching

@MainActor
public final class MacWallpaperStore: ObservableObject {
    public static let shared = MacWallpaperStore()

    @Published public private(set) var presets: [MacWallpaperPreset] = []
    @Published public private(set) var thumbnails: [String: NSImage] = [:]

    private let renderImageCache = NSCache<NSString, NSImage>()
    private var hasStartedPreload = false

    private init() {
        renderImageCache.countLimit = 12
        loadCatalog()
    }

    private func loadCatalog() {
        var discovered: [MacWallpaperPreset] = []
        var seenPaths: Set<String> = []

        if let activeURL = NSScreen.main.flatMap({ NSWorkspace.shared.desktopImageURL(for: $0) }),
           FileManager.default.isReadableFile(atPath: activeURL.path),
           ["heic", "jpg", "jpeg", "png", "tiff"].contains(activeURL.pathExtension.lowercased()) {
            let resolved = activeURL.resolvingSymlinksInPath()
            seenPaths.insert(resolved.path)
            discovered.append(MacWallpaperPreset(id: "current_desktop", name: "Current Desktop", fileURL: activeURL))
        }

        let priorityNames: [(filename: String, label: String)] = [
            ("Sonoma.heic", "Sonoma"),
            ("Radial Sky Blue.heic", "Radial Sky"),
            ("Mac Blue.heic", "Mac Blue"),
            ("Mac Purple.heic", "Mac Purple"),
            ("Mac Pink.heic", "Mac Pink"),
            ("Mac Yellow.heic", "Mac Yellow"),
            ("iMac Blue.heic", "iMac Blue"),
            ("iMac Green.heic", "iMac Green"),
            ("iMac Orange.heic", "iMac Orange"),
            ("iMac Purple.heic", "iMac Purple"),
            ("iMac Pink.heic", "iMac Pink"),
            ("iMac Silver.heic", "iMac Silver"),
            ("iMac Yellow.heic", "iMac Yellow")
        ]

        let sysDir = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        for item in priorityNames {
            let url = sysDir.appendingPathComponent(item.filename)
            let resolved = url.resolvingSymlinksInPath().path
            guard !seenPaths.contains(resolved),
                  FileManager.default.isReadableFile(atPath: url.path) else { continue }
            seenPaths.insert(resolved)
            let id = "sys_" + item.filename.replacingOccurrences(of: ".heic", with: "").lowercased().replacingOccurrences(of: " ", with: "_")
            discovered.append(MacWallpaperPreset(id: id, name: item.label, fileURL: url))
        }

        // Also include any additional full-resolution wallpapers present in /System/Library/Desktop Pictures or /Library/Desktop Pictures
        for dir in [sysDir, URL(fileURLWithPath: "/Library/Desktop Pictures")] {
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = url.pathExtension.lowercased()
                guard ["heic", "jpg", "jpeg", "png"].contains(ext) else { continue }
                let resolved = url.resolvingSymlinksInPath().path
                guard !seenPaths.contains(resolved),
                      FileManager.default.isReadableFile(atPath: url.path) else { continue }
                seenPaths.insert(resolved)
                let label = url.deletingPathExtension().lastPathComponent
                let id = "sys_" + label.lowercased().replacingOccurrences(of: " ", with: "_")
                discovered.append(MacWallpaperPreset(id: id, name: label, fileURL: url))
            }
        }

        self.presets = discovered
    }

    public func preloadThumbnailsIfNeeded() {
        guard !hasStartedPreload, !presets.isEmpty else { return }
        hasStartedPreload = true
        let items = presets
        Task.detached(priority: .userInitiated) {
            for preset in items {
                guard let thumb = Self.decodeDownsampledImage(url: preset.fileURL, maxPixelSize: 160, preferEmbedded: true) else {
                    continue
                }
                await MainActor.run {
                    MacWallpaperStore.shared.thumbnails[preset.id] = thumb
                }
            }
        }
    }

    public func loadFullImage(for preset: MacWallpaperPreset) -> NSImage? {
        let key = preset.fileURL.path as NSString
        if let cached = renderImageCache.object(forKey: key) {
            return cached
        }
        guard let decoded = Self.decodeDownsampledImage(url: preset.fileURL, maxPixelSize: 2560, preferEmbedded: false)
                ?? NSImage(contentsOf: preset.fileURL) else {
            return nil
        }
        renderImageCache.setObject(decoded, forKey: key)
        return decoded
    }

    public func defaultWallpaperImageAndId() -> (id: String, image: NSImage)? {
        // Prefer Sonoma as crisp iconic default, else Current Desktop or first preset
        let preferred = presets.first(where: { $0.id == "sys_sonoma" }) ?? presets.first
        guard let preset = preferred, let img = loadFullImage(for: preset) else { return nil }
        return (preset.id, img)
    }

    private nonisolated static func decodeDownsampledImage(url: URL, maxPixelSize: Int, preferEmbedded: Bool) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if preferEmbedded {
            let fastOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, fastOpts as CFDictionary) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        let fullOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, fullOpts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - Background, Cutout, Window Framing & GIF Engine

public final class ImageBackdropCompositor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - 1. On-Device Background Removal (Apple Vision macOS 14+)

    public static func removeBackground(from image: NSImage) async -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            if #available(macOS 14.0, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first, !result.allInstances.isEmpty else {
                        return nil
                    }
                    let maskPixelBuffer = try result.generateScaledMaskForImage(
                        forInstances: result.allInstances,
                        from: handler
                    )
                    let foregroundCI = CIImage(cgImage: cg)
                    let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
                    let transparentBG = CIImage.empty()

                    guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
                    blendFilter.setValue(foregroundCI, forKey: kCIInputImageKey)
                    blendFilter.setValue(transparentBG, forKey: kCIInputBackgroundImageKey)
                    blendFilter.setValue(maskCI, forKey: kCIInputMaskImageKey)

                    guard let outputCI = blendFilter.outputImage?.cropped(to: foregroundCI.extent),
                          let outputCG = ciContext.createCGImage(outputCI, from: foregroundCI.extent) else {
                        return nil
                    }
                    return NSImage(cgImage: outputCG, size: image.size)
                } catch {
                    print("⚠️ Subject background removal failed: \(error.localizedDescription)")
                    return nil
                }
            }
            return nil
        }.value
    }

    // MARK: - 2. Animated GIF Loading & Procedural Loop Synthesis

    public struct AnimatedGIFFrame {
        public let cgImage: CGImage
        public let duration: TimeInterval

        public init(cgImage: CGImage, duration: TimeInterval) {
            self.cgImage = cgImage
            self.duration = duration
        }
    }

    public static func loadGIFFrames(url: URL) -> [AnimatedGIFFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        var frames: [AnimatedGIFFrame] = []
        frames.reserveCapacity(count)

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            var delay: TimeInterval = 0.08
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, unclamped > 0.01 {
                    delay = unclamped
                } else if let clamped = gifDict[kCGImagePropertyGIFDelayTime as String] as? Double, clamped > 0.01 {
                    delay = clamped
                }
            }
            frames.append(AnimatedGIFFrame(cgImage: cg, duration: max(0.03, delay)))
        }
        return frames
    }

    public static func generateBuiltInGIFFrames(presetId: String) -> [AnimatedGIFFrame] {
        let preset = GIFLoopPreset.all.first(where: { $0.id == presetId }) ?? GIFLoopPreset.all[0]
        let frameCount = 18
        let width = 480
        let height = 300
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var result: [AnimatedGIFFrame] = []
        result.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let phase = CGFloat(index) / CGFloat(frameCount) * .pi * 2.0
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            let c0 = preset.colorA
            let c1 = preset.colorB
            let c2 = preset.colorC

            if let baseGrad = CGGradient(
                colorsSpace: colorSpace,
                colors: [c0.cgColor, c1.cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                let dx = cos(phase) * CGFloat(width) * 0.25
                let dy = sin(phase) * CGFloat(height) * 0.25
                ctx.drawLinearGradient(
                    baseGrad,
                    start: CGPoint(x: CGFloat(width) * 0.1 + dx, y: CGFloat(height) * 0.9 - dy),
                    end: CGPoint(x: CGFloat(width) * 0.9 - dx, y: CGFloat(height) * 0.1 + dy),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Moving luminous radial orb wave for silky loop motion
            let cx1 = CGFloat(width) * (0.5 + 0.30 * cos(phase))
            let cy1 = CGFloat(height) * (0.5 + 0.28 * sin(phase))
            if let orbGrad = CGGradient(
                colorsSpace: colorSpace,
                colors: [c2.withAlphaComponent(0.65).cgColor, c2.withAlphaComponent(0.0).cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                ctx.drawRadialGradient(
                    orbGrad,
                    startCenter: CGPoint(x: cx1, y: cy1),
                    startRadius: 10,
                    endCenter: CGPoint(x: cx1, y: cy1),
                    endRadius: CGFloat(width) * 0.65,
                    options: []
                )
            }

            if let cg = ctx.makeImage() {
                result.append(AnimatedGIFFrame(cgImage: cg, duration: 0.08))
            }
        }
        return result
    }

    // MARK: - 3. Composite Layout Math (Supports Raw, Card, macOS Window & Aspect Ratios)

    public struct CompositeLayout {
        public let canvasSize: CGSize        // Full output canvas in points (bottom-left Y-up CG coords)
        public let windowCardRect: CGRect    // Framed window/card rect inside canvasSize
        public let titlebarRect: CGRect      // macOS header bar (zero height if not .macOSWindow)
        public let subjectRect: CGRect       // Exact rect where base/cutout screenshot + annotations sit
    }

    public static func hasTransparentPerimeter(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width >= 12, cg.height >= 12 else {
            return false
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        let pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
        for (px, py) in pts {
            if let c = rep.colorAt(x: px, y: py), c.alphaComponent > 0.05 {
                return false
            }
        }
        return true
    }

    public static func layout(forSubjectSize subjectSize: CGSize, config: BackdropConfig, hasEmbeddedShadow: Bool = false) -> CompositeLayout {
        let safeW = max(1, subjectSize.width)
        let safeH = max(1, subjectSize.height)

        let hasFrame = config.frameStyle != .none
        let hasBackdrop = config.backdropType != .none || config.aspectRatio != .auto
        // Captured macOS windows already carry ~50pt transparent shadow padding on each edge; avoid doubling it in Raw mode
        let embeddedComp: CGFloat = (hasEmbeddedShadow && !hasFrame && config.backdropType != .none) ? 36 : 0
        let pad: CGFloat = hasBackdrop ? max(0, config.padding - embeddedComp) : (hasFrame ? 16 : 0)
        let titleH: CGFloat = (config.frameStyle == .macOSWindow) ? 30 : 0

        let cardW = safeW
        let cardH = safeH + titleH

        var canvasW = cardW + pad * 2
        var canvasH = cardH + pad * 2

        if let targetRatio = config.aspectRatio.ratioValue {
            let currentRatio = canvasW / max(1, canvasH)
            if currentRatio < targetRatio {
                canvasW = ceil(canvasH * targetRatio)
            } else if currentRatio > targetRatio {
                canvasH = ceil(canvasW / targetRatio)
            }
        }

        let cardOriginX = (canvasW - cardW) * 0.5
        let cardOriginY = (canvasH - cardH) * 0.5
        let windowCardRect = CGRect(x: cardOriginX, y: cardOriginY, width: cardW, height: cardH)
        let subjectRect = CGRect(x: cardOriginX, y: cardOriginY, width: safeW, height: safeH)
        let titlebarRect = CGRect(x: cardOriginX, y: cardOriginY + safeH, width: cardW, height: titleH)

        return CompositeLayout(
            canvasSize: CGSize(width: canvasW, height: canvasH),
            windowCardRect: windowCardRect,
            titlebarRect: titlebarRect,
            subjectRect: subjectRect
        )
    }

    // MARK: - 4. Shared Renderer (Live Stage & High-DPI PNG / GIF Export)

    public static func renderCompositeContent(
        layout: CompositeLayout,
        subjectImage: NSImage,
        config: BackdropConfig,
        annotations: [CanvasAnnotation],
        blurredSubjectImage: NSImage?,
        gifFrameImage: CGImage?,
        auditUnit: Int,
        hasEmbeddedShadow: Bool = false,
        scaleToView: CGFloat = 1.0,
        canvasOriginInView: CGPoint = .zero,
        in ctx: CGContext
    ) {
        let canvasRect = CGRect(
            x: canvasOriginInView.x,
            y: canvasOriginInView.y,
            width: layout.canvasSize.width * scaleToView,
            height: layout.canvasSize.height * scaleToView
        )

        func mapRect(_ r: CGRect) -> CGRect {
            CGRect(
                x: canvasOriginInView.x + r.origin.x * scaleToView,
                y: canvasOriginInView.y + r.origin.y * scaleToView,
                width: r.width * scaleToView,
                height: r.height * scaleToView
            )
        }

        let cardRect = mapRect(layout.windowCardRect)
        let subjectViewRect = mapRect(layout.subjectRect)
        let titleViewRect = mapRect(layout.titlebarRect)

        // A. Backdrop Background Layer
        ctx.saveGState()
        ctx.clip(to: canvasRect)
        switch config.backdropType {
        case .none:
            break

        case .solid:
            config.solidColor.setFill()
            ctx.fill(canvasRect)

        case .gradient:
            let preset = BackdropGradientPreset.all.first(where: { $0.id == config.gradientId }) ?? BackdropGradientPreset.all[0]
            if let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [preset.startColor.cgColor, preset.endColor.cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: canvasRect.minX, y: canvasRect.maxY),
                    end: CGPoint(x: canvasRect.maxX, y: canvasRect.minY),
                    options: []
                )
            }

        case .photo:
            if let bgImg = config.customPhoto {
                drawAspectFillImage(bgImg, in: canvasRect, blurAmount: config.blurPhotoBackdrop ? 18 : 0, ctx: ctx)
            } else {
                NSColor(white: 0.90, alpha: 1.0).setFill()
                ctx.fill(canvasRect)
            }

        case .gif:
            if let frameCG = gifFrameImage {
                drawAspectFillCGImage(frameCG, in: canvasRect, ctx: ctx)
            } else {
                NSColor(red: 0.14, green: 0.16, blue: 0.24, alpha: 1.0).setFill()
                ctx.fill(canvasRect)
            }
        }
        ctx.restoreGState()

        // B. Window / Card Drop Shadow + Surface
        let isFloatingSubject = hasEmbeddedShadow || config.removeSubjectBackground || (config.backdropType != .none && hasTransparentPerimeter(subjectImage))
        let needsSyntheticCardDecor = (config.frameStyle != .none) || (config.backdropType != .none && !isFloatingSubject)

        let effectiveRadius: CGFloat = needsSyntheticCardDecor ? (config.cornerRadius * scaleToView) : 0
        let shouldCastCardShadow = needsSyntheticCardDecor && config.shadowIntensity > 0.02

        if shouldCastCardShadow {
            ctx.saveGState()
            let blurR = (14 + 26 * config.shadowIntensity) * scaleToView
            let yOff = -(6 + 10 * config.shadowIntensity) * scaleToView
            ctx.setShadow(
                offset: CGSize(width: 0, height: yOff),
                blur: blurR,
                color: NSColor.black.withAlphaComponent(0.16 + 0.24 * config.shadowIntensity).cgColor
            )
            let shadowPath = NSBezierPath(roundedRect: cardRect, xRadius: effectiveRadius, yRadius: effectiveRadius)
            NSColor.black.withAlphaComponent(0.01).setFill()
            shadowPath.fill()
            ctx.restoreGState()
        }

        // C. Clipped Window / Framed Subject + Optional macOS Titlebar
        ctx.saveGState()
        if effectiveRadius > 0 {
            let clipPath = NSBezierPath(roundedRect: cardRect, xRadius: effectiveRadius, yRadius: effectiveRadius)
            clipPath.addClip()
        } else if needsSyntheticCardDecor {
            ctx.clip(to: cardRect)
        }

        // If converting into a macOS Window & subject was cut out, give clean window backing; otherwise keep subject transparent over backdrop
        if config.frameStyle == .macOSWindow {
            let titleBg = config.useDarkWindowChrome
                ? NSColor(red: 36/255, green: 36/255, blue: 40/255, alpha: 1.0)
                : NSColor(red: 244/255, green: 244/255, blue: 246/255, alpha: 1.0)
            titleBg.setFill()
            ctx.fill(titleViewRect)

            let divColor = config.useDarkWindowChrome
                ? NSColor.white.withAlphaComponent(0.09)
                : NSColor.black.withAlphaComponent(0.08)
            divColor.setFill()
            ctx.fill(CGRect(x: titleViewRect.minX, y: titleViewRect.minY, width: titleViewRect.width, height: max(0.5, 1.0 * scaleToView)))

            // Classic macOS Red / Yellow / Green traffic lights
            let dotR = 5.5 * scaleToView
            let dotY = titleViewRect.midY
            let firstDotX = titleViewRect.minX + 16 * scaleToView
            let dotGap = 19 * scaleToView
            let dotColors: [NSColor] = [
                NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1.0),
                NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0),
                NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1.0)
            ]
            for (idx, c) in dotColors.enumerated() {
                let cx = firstDotX + CGFloat(idx) * dotGap
                let dotRect = CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)
                c.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            if !config.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let titleStr = config.windowTitle as NSString
                let fontSize = max(9, 12 * scaleToView)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: config.useDarkWindowChrome ? NSColor.white.withAlphaComponent(0.82) : NSColor.black.withAlphaComponent(0.75)
                ]
                let tSize = titleStr.size(withAttributes: attrs)
                titleStr.draw(
                    at: NSPoint(x: titleViewRect.midX - tSize.width / 2, y: titleViewRect.midY - tSize.height / 2),
                    withAttributes: attrs
                )
            }
        }

        // For raw isolated cutouts without pre-baked window shadow, cast true silhouette shadow directly from alpha channel
        if config.frameStyle == .none && config.removeSubjectBackground && !hasEmbeddedShadow && config.backdropType != .none && config.shadowIntensity > 0.02 {
            let blurR = (12 + 22 * config.shadowIntensity) * scaleToView
            let yOff = -(5 + 9 * config.shadowIntensity) * scaleToView
            ctx.setShadow(
                offset: CGSize(width: 0, height: yOff),
                blur: blurR,
                color: NSColor.black.withAlphaComponent(0.18 + 0.22 * config.shadowIntensity).cgColor
            )
        }

        ctx.interpolationQuality = scaleToView >= 3.0 ? .none : .high
        subjectImage.draw(in: subjectViewRect)
        ctx.restoreGState()

        // Crisp hairline rim ONLY around synthetic Card/Window frames or rectangular Area captures — NEVER around Window screenshots or Cutouts
        if needsSyntheticCardDecor {
            ctx.saveGState()
            let strokePath = NSBezierPath(roundedRect: cardRect.insetBy(dx: 0.4, dy: 0.4), xRadius: effectiveRadius, yRadius: effectiveRadius)
            let rim = config.useDarkWindowChrome
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.black.withAlphaComponent(0.10)
            rim.setStroke()
            strokePath.lineWidth = max(0.6, 0.8 * scaleToView)
            strokePath.stroke()
            ctx.restoreGState()
        }

        // D. Annotations Mapped Directly onto Subject Coordinates
        let mapper = AnnotationRenderer.Mapper(
            toCanvasPoint: { pt in
                CGPoint(
                    x: subjectViewRect.origin.x + pt.x * scaleToView,
                    y: subjectViewRect.origin.y + (layout.subjectRect.height - pt.y) * scaleToView
                )
            },
            scale: scaleToView,
            imageCanvasRect: subjectViewRect
        )

        let spotlights = annotations.filter { $0.tool == .spotlight }
        if !spotlights.isEmpty {
            AnnotationRenderer.drawSpotlights(spotlights, mapper: mapper, in: ctx)
        }

        for ann in annotations where ann.tool != .spotlight {
            AnnotationRenderer.draw(ann, mapper: mapper, blurredImage: blurredSubjectImage, auditUnit: auditUnit, in: ctx)
        }
    }

    // MARK: - 5. Image Export (Flattened PNG & Multi-Frame Animated GIF)

    public static func renderFlattenedPNGImage(
        subjectImage: NSImage,
        pixelSize: CGSize,
        config: BackdropConfig,
        annotations: [CanvasAnnotation],
        blurredSubjectImage: NSImage?,
        gifFrameImage: CGImage?,
        auditUnit: Int,
        hasEmbeddedShadow: Bool = false
    ) -> NSImage {
        let layout = Self.layout(forSubjectSize: subjectImage.size, config: config, hasEmbeddedShadow: hasEmbeddedShadow)
        let ratio = subjectImage.size.width > 0 ? (pixelSize.width / subjectImage.size.width) : 2.0
        let exportScale = max(1.0, min(2.5, ratio))

        let outW = max(1, Int(round(layout.canvasSize.width * exportScale)))
        let outH = max(1, Int(round(layout.canvasSize.height * exportScale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return subjectImage }

        let gCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gCtx

        renderCompositeContent(
            layout: layout,
            subjectImage: subjectImage,
            config: config,
            annotations: annotations,
            blurredSubjectImage: blurredSubjectImage,
            gifFrameImage: gifFrameImage,
            auditUnit: auditUnit,
            hasEmbeddedShadow: hasEmbeddedShadow,
            scaleToView: exportScale,
            canvasOriginInView: .zero,
            in: ctx
        )

        NSGraphicsContext.restoreGraphicsState()

        guard let cgOut = ctx.makeImage() else { return subjectImage }
        return NSImage(cgImage: cgOut, size: layout.canvasSize)
    }

    public static func exportAnimatedGIF(
        subjectImage: NSImage,
        config: BackdropConfig,
        annotations: [CanvasAnnotation],
        blurredSubjectImage: NSImage?,
        frames: [AnimatedGIFFrame],
        auditUnit: Int,
        hasEmbeddedShadow: Bool = false,
        to url: URL
    ) -> Bool {
        guard !frames.isEmpty else { return false }
        let layout = Self.layout(forSubjectSize: subjectImage.size, config: config, hasEmbeddedShadow: hasEmbeddedShadow)

        // Cap GIF frame resolution cleanly (~1080px max edge) so GIF exports stay fast and crisp
        let maxDim = max(layout.canvasSize.width, layout.canvasSize.height)
        let scale: CGFloat = maxDim > 1080 ? (1080.0 / maxDim) : 1.0
        let outW = max(2, Int(round(layout.canvasSize.width * scale)))
        let outH = max(2, Int(round(layout.canvasSize.height * scale)))

        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else { return false }
        CGImageDestinationSetProperties(dest, fileProperties as CFDictionary)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frame in frames {
            guard let ctx = CGContext(
                data: nil,
                width: outW,
                height: outH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            let gCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gCtx

            renderCompositeContent(
                layout: layout,
                subjectImage: subjectImage,
                config: config,
                annotations: annotations,
                blurredSubjectImage: blurredSubjectImage,
                gifFrameImage: frame.cgImage,
                auditUnit: auditUnit,
                hasEmbeddedShadow: hasEmbeddedShadow,
                scaleToView: scale,
                canvasOriginInView: .zero,
                in: ctx
            )

            NSGraphicsContext.restoreGraphicsState()

            if let composedCG = ctx.makeImage() {
                let frameProps: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: frame.duration
                    ]
                ]
                CGImageDestinationAddImage(dest, composedCG, frameProps as CFDictionary)
            }
        }

        return CGImageDestinationFinalize(dest)
    }

    // MARK: - Helpers

    private static func drawAspectFillImage(_ image: NSImage, in targetRect: CGRect, blurAmount: Double, ctx: CGContext) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        if blurAmount > 0 {
            let ciImg = CIImage(cgImage: cg)
            let clamped = ciImg.clampedToExtent()
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(clamped, forKey: kCIInputImageKey)
                blur.setValue(blurAmount, forKey: kCIInputRadiusKey)
                if let out = blur.outputImage?.cropped(to: ciImg.extent),
                   let blurredCG = ciContext.createCGImage(out, from: ciImg.extent) {
                    drawAspectFillCGImage(blurredCG, in: targetRect, ctx: ctx)
                    return
                }
            }
        }
        drawAspectFillCGImage(cg, in: targetRect, ctx: ctx)
    }

    private static func drawAspectFillCGImage(_ cg: CGImage, in targetRect: CGRect, ctx: CGContext) {
        let imgW = CGFloat(cg.width)
        let imgH = CGFloat(cg.height)
        guard imgW > 0, imgH > 0 else { return }
        let scale = max(targetRect.width / imgW, targetRect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(
            x: targetRect.midX - drawW * 0.5,
            y: targetRect.midY - drawH * 0.5,
            width: drawW,
            height: drawH
        )
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: drawRect)
    }
}
