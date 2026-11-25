import AppKit
import SwiftUI
import CoreImage

// MARK: - Annotation Tool Types
public enum AnnotationTool: String, CaseIterable, Identifiable {
    case pointer = "Pointer"
    case distance = "Dimension"
    case arrow = "Arrow"
    case text = "Text"
    case numberedPin = "Numbered Pin"
    case rectangle = "Rectangle"
    case pencil = "Highlighter"
    case blur = "Blur"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .pointer: return "arrow.up.left"
        case .distance: return "ruler"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .numberedPin: return "1.circle"
        case .rectangle: return "rectangle"
        case .pencil: return "pencil.tip"
        case .blur: return "circle.lefthalf.filled"
        }
    }

    public var tooltip: String {
        switch self {
        case .pointer: return "Select, Move & Resize (V)"
        case .distance: return "Smart Dimension Ruler — Horizontal & Vertical Edge Snap (D)"
        case .arrow: return "Arrow Callout (A)"
        case .text: return "Text & Speech Quote (T)"
        case .numberedPin: return "Numbered QA Pin (N)"
        case .rectangle: return "Rectangle / Card (R or C)"
        case .pencil: return "Highlighter (P)"
        case .blur: return "Mosaic Redaction Blur (B)"
        }
    }
}

// MARK: - Tool-Specific Styles
public enum ArrowStyle: String, CaseIterable, Identifiable {
    case tapered = "Tapered Callout"
    case filledSingle = "Solid Arrow"
    case openChevron = "Thin Chevron"
    case doubleEnded = "Two-Way Arrow"

    public var id: String { rawValue }
}

public enum TextStyle: String, CaseIterable, Identifiable {
    case plain = "Plain Text"
    case card = "Badge Pill"
    case quoteBubble = "Speech Quote"

    public var id: String { rawValue }
}

public enum RectFillMode: String, CaseIterable, Identifiable {
    case stroke = "Stroke"
    case tinted = "Tinted"
    case solid = "Solid"

    public var id: String { rawValue }
}

// MARK: - Curated Palette Presets
public struct DesignerColorPreset: Identifiable {
    public let id: String
    public let name: String
    public let hex: String
    public let nsColor: NSColor
    public let color: Color

    public init(name: String, hex: String) {
        self.id = hex
        self.name = name
        self.hex = hex
        self.nsColor = NSColor(hex: hex) ?? .white
        self.color = Color(self.nsColor)
    }

    public static let curated: [DesignerColorPreset] = [
        DesignerColorPreset(name: "White", hex: "#FFFFFF"),
        DesignerColorPreset(name: "Charcoal", hex: "#1C1C1E"),
        DesignerColorPreset(name: "Cobalt Blue", hex: "#0A84FF"),
        DesignerColorPreset(name: "Coral Red", hex: "#FF453A"),
        DesignerColorPreset(name: "Amber", hex: "#FF9F0A"),
        DesignerColorPreset(name: "Emerald", hex: "#30D158"),
        DesignerColorPreset(name: "Violet", hex: "#BF5AF2"),
        DesignerColorPreset(name: "Pink", hex: "#FF375F")
    ]
}

// MARK: - Vector Annotation Model
public struct CanvasAnnotation: Identifiable, Equatable {
    public let id = UUID()
    public var tool: AnnotationTool
    public var startPoint: CGPoint             // In image point coords (0,0 = top-left)
    public var endPoint: CGPoint
    public var controlPoint: CGPoint? = nil    // Optional curve handle for arrows
    public var pathPoints: [CGPoint] = []
    public var text: String = ""
    public var number: Int = 1
    public var color: NSColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)

    // Customization Properties
    public var strokeWidth: CGFloat = 4.0      // Line thickness for arrow/rect/pencil, or font size for text
    public var arrowStyle: ArrowStyle = .tapered
    public var textStyle: TextStyle = .plain
    public var rectFillMode: RectFillMode = .stroke
    public var cornerRadius: CGFloat = 0.0
    public var showSizeTag: Bool = false

    public static func == (lhs: CanvasAnnotation, rhs: CanvasAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.tool == rhs.tool &&
        lhs.startPoint == rhs.startPoint &&
        lhs.endPoint == rhs.endPoint &&
        lhs.controlPoint == rhs.controlPoint &&
        lhs.pathPoints == rhs.pathPoints &&
        lhs.text == rhs.text &&
        lhs.number == rhs.number &&
        lhs.strokeWidth == rhs.strokeWidth &&
        lhs.arrowStyle == rhs.arrowStyle &&
        lhs.textStyle == rhs.textStyle &&
        lhs.rectFillMode == rhs.rectFillMode &&
        lhs.cornerRadius == rhs.cornerRadius &&
        lhs.showSizeTag == rhs.showSizeTag &&
        lhs.color.hexString == rhs.color.hexString
    }
}

public extension NSColor {
    var hexString: String {
        let converted = usingColorSpace(.sRGB) ?? self
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    var relativeLuminance: Double {
        let c = usingColorSpace(.sRGB) ?? self
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
}

// MARK: - Fast sRGB Pixel & UI Edge Inspection Buffer
public final class PixelInspectBuffer {
    public let pixelsWide: Int
    public let pixelsHigh: Int
    public let imagePointSize: CGSize
    private let bytesPerRow: Int
    private let rgba: [UInt8]

    public init?(image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = max(1, cg.width)
        let h = max(1, cg.height)
        let bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: h * bpr)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.pixelsWide = w
        self.pixelsHigh = h
        self.imagePointSize = image.size
        self.bytesPerRow = bpr
        self.rgba = buffer
    }

    private var scaleX: CGFloat {
        imagePointSize.width > 0 ? CGFloat(pixelsWide) / imagePointSize.width : 1.0
    }
    private var scaleY: CGFloat {
        imagePointSize.height > 0 ? CGFloat(pixelsHigh) / imagePointSize.height : 1.0
    }

    @inline(__always)
    public func pixelRGBA(bx: Int, by: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let cx = max(0, min(pixelsWide - 1, bx))
        let cy = max(0, min(pixelsHigh - 1, by))
        let offset = cy * bytesPerRow + cx * 4
        let r = Int(rgba[offset])
        let g = Int(rgba[offset + 1])
        let b = Int(rgba[offset + 2])
        let a = Int(rgba[offset + 3])
        if a > 0 && a < 255 {
            return (min(255, (r * 255) / a), min(255, (g * 255) / a), min(255, (b * 255) / a), a)
        }
        return (r, g, b, a)
    }

    public func sampleColor(at imagePt: CGPoint) -> (r: Int, g: Int, b: Int, hex: String)? {
        let bx = Int(round(imagePt.x * scaleX))
        let by = Int(round(imagePt.y * scaleY))
        guard bx >= 0 && bx < pixelsWide && by >= 0 && by < pixelsHigh else { return nil }
        let (r, g, b, _) = pixelRGBA(bx: bx, by: by)
        return (r, g, b, String(format: "#%02X%02X%02X", r, g, b))
    }

    public static func contrastRatio(hex1: String, hex2: String) -> Double? {
        guard let c1 = parseHex(hex1), let c2 = parseHex(hex2) else { return nil }
        let l1 = relativeLuminance(r: c1.r, g: c1.g, b: c1.b)
        let l2 = relativeLuminance(r: c2.r, g: c2.g, b: c2.b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let val = Int(cleaned, radix: 16) else { return nil }
        return ((val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF)
    }

    private static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        func lin(_ ch: Int) -> Double {
            let v = Double(ch) / 255.0
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func snapCoordinate(near imagePt: CGPoint, horizontal: Bool, searchRadiusPt: CGFloat = 9.0) -> CGFloat? {
        let sy = scaleY
        let sx = scaleX
        let fixedCoord = horizontal ? Int(round(imagePt.y * sy)) : Int(round(imagePt.x * sx))
        let centerCoord = horizontal ? Int(round(imagePt.x * sx)) : Int(round(imagePt.y * sy))
        let radiusPx = Int(round(searchRadiusPt * (horizontal ? sx : sy)))
        let maxBound = horizontal ? pixelsWide - 2 : pixelsHigh - 2

        var bestSignedOffset = Int.max
        var minDist = Int.max
        var maxDiff = 0

        for offset in -radiusPx...radiusPx {
            let pos = centerCoord + offset
            guard pos >= 1 && pos < maxBound else { continue }
            let cPrev = horizontal ? pixelRGBA(bx: pos - 1, by: fixedCoord) : pixelRGBA(bx: fixedCoord, by: pos - 1)
            let cCurr = horizontal ? pixelRGBA(bx: pos, by: fixedCoord) : pixelRGBA(bx: fixedCoord, by: pos)
            let diff = abs(cCurr.r - cPrev.r) + abs(cCurr.g - cPrev.g) + abs(cCurr.b - cPrev.b) + abs(cCurr.a - cPrev.a)
            if diff >= 32 {
                let d = abs(offset)
                if d < minDist || (d == minDist && diff > maxDiff) {
                    minDist = d
                    maxDiff = diff
                    bestSignedOffset = offset
                }
            }
        }

        guard bestSignedOffset != Int.max else { return nil }
        return CGFloat(centerCoord + bestSignedOffset) / (horizontal ? sx : sy)
    }

    public struct SmartSpan {
        public let originPt: CGPoint
        public let leftX: CGFloat
        public let rightX: CGFloat
        public let topY: CGFloat
        public let bottomY: CGFloat

        public var horizontalDistance: Int { Int(round(abs(rightX - leftX))) }
        public var verticalDistance: Int { Int(round(abs(bottomY - topY))) }
    }

    public func raycastSpan(at imagePt: CGPoint, maxScanPt: CGFloat = 650.0) -> SmartSpan? {
        let cx = Int(round(imagePt.x * scaleX))
        let cy = Int(round(imagePt.y * scaleY))
        guard cx >= 1 && cx < pixelsWide - 1 && cy >= 1 && cy < pixelsHigh - 1 else { return nil }

        let base = pixelRGBA(bx: cx, by: cy)
        let maxPxH = Int(maxScanPt * scaleX)
        let maxPxV = Int(maxScanPt * scaleY)
        let edgeThresh = 30

        func deviates(_ c: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
            abs(c.r - base.r) + abs(c.g - base.g) + abs(c.b - base.b) + abs(c.a - base.a) >= edgeThresh
        }

        var leftPx = cx
        for step in 1...maxPxH {
            let tx = cx - step
            if tx <= 0 { leftPx = 0; break }
            if deviates(pixelRGBA(bx: tx, by: cy)) { leftPx = tx + 1; break }
            leftPx = tx
        }

        var rightPx = cx
        for step in 1...maxPxH {
            let tx = cx + step
            if tx >= pixelsWide - 1 { rightPx = pixelsWide - 1; break }
            if deviates(pixelRGBA(bx: tx, by: cy)) { rightPx = tx; break }
            rightPx = tx
        }

        var topPx = cy
        for step in 1...maxPxV {
            let ty = cy - step
            if ty <= 0 { topPx = 0; break }
            if deviates(pixelRGBA(bx: cx, by: ty)) { topPx = ty + 1; break }
            topPx = ty
        }

        var bottomPx = cy
        for step in 1...maxPxV {
            let ty = cy + step
            if ty >= pixelsHigh - 1 { bottomPx = pixelsHigh - 1; break }
            if deviates(pixelRGBA(bx: cx, by: ty)) { bottomPx = ty; break }
            bottomPx = ty
        }

        return SmartSpan(
            originPt: imagePt,
            leftX: CGFloat(leftPx) / scaleX,
            rightX: CGFloat(rightPx) / scaleX,
            topY: CGFloat(topPx) / scaleY,
            bottomY: CGFloat(bottomPx) / scaleY
        )
    }
}

// MARK: - Unified CoreGraphics Vector Renderer (Shared between Live Canvas & PNG Export)
public enum AnnotationRenderer {
    public struct Mapper {
        public let toCanvasPoint: (CGPoint) -> CGPoint
        public let scale: CGFloat
        public let imageCanvasRect: NSRect
    }

    /// Computes exact image-space bounding rect for text callouts (used uniformly for draw & hit-test).
    public static func textImageBounds(for ann: CanvasAnnotation) -> CGRect {
        let fontSize = max(10, min(48, ann.strokeWidth > 8 ? ann.strokeWidth : 16))
        let displayText = (ann.text.isEmpty ? "Text" : ann.text) as NSString
        let font = NSFont.systemFont(ofSize: fontSize, weight: ann.textStyle == .plain ? .semibold : .medium)
        let maxSize = CGSize(width: 560, height: 800)
        let measured = displayText.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let padX: CGFloat = ann.textStyle == .plain ? 4 : 12
        let padY: CGFloat = ann.textStyle == .plain ? 2 : 7
        return CGRect(
            x: ann.startPoint.x,
            y: ann.startPoint.y,
            width: ceil(measured.width) + padX * 2,
            height: ceil(measured.height) + padY * 2
        )
    }

    public static func draw(
        _ ann: CanvasAnnotation,
        mapper: Mapper,
        blurredImage: NSImage?,
        auditUnit: Int,
        in ctx: CGContext
    ) {
        let vStart = mapper.toCanvasPoint(ann.startPoint)
        let vEnd = mapper.toCanvasPoint(ann.endPoint)
        let vCtrl = ann.controlPoint.map { mapper.toCanvasPoint($0) }
        let s = mapper.scale
        let ink = ann.color

        switch ann.tool {
        case .arrow:
            drawArrow(start: vStart, end: vEnd, control: vCtrl, width: max(1.5, ann.strokeWidth * s), style: ann.arrowStyle, color: ink, in: ctx)

        case .distance:
            drawDimensionRuler(ann: ann, vStart: vStart, vEnd: vEnd, scale: s, auditUnit: auditUnit, in: ctx)

        case .rectangle:
            drawRectangle(ann: ann, vStart: vStart, vEnd: vEnd, scale: s, in: ctx)

        case .text:
            drawTextCallout(ann: ann, mapper: mapper, in: ctx)

        case .numberedPin:
            drawNumberedPin(number: ann.number, center: vStart, diameter: max(18, ann.strokeWidth * 4.5 * s), color: ink, scale: s, in: ctx)

        case .pencil:
            drawHighlighter(points: ann.pathPoints.map(mapper.toCanvasPoint), width: max(4, ann.strokeWidth * s), color: ink)

        case .blur:
            let r = normalizedRect(from: vStart, to: vEnd)
            let path = NSBezierPath(roundedRect: r, xRadius: 6 * s, yRadius: 6 * s)
            if let mosaic = blurredImage {
                ctx.saveGState()
                path.addClip()
                ctx.interpolationQuality = .none
                mosaic.draw(in: mapper.imageCanvasRect)
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                path.fill()
                ctx.restoreGState()
                NSColor.labelColor.withAlphaComponent(0.14).setStroke()
                path.lineWidth = 0.8
                path.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.75).setFill()
                path.fill()
            }

        case .pointer:
            break
        }
    }

    // MARK: - Arrow Rendering (4 Styles + Quadratic Curve Support)
    private static func drawArrow(
        start: CGPoint,
        end: CGPoint,
        control: CGPoint?,
        width: CGFloat,
        style: ArrowStyle,
        color: NSColor,
        in ctx: CGContext
    ) {
        let len = hypot(end.x - start.x, end.y - start.y)
        guard len >= 4 else { return }

        ctx.saveGState()
        // Subtle contrast shadow makes white or colored arrows legible over any UI
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 4.0, color: NSColor.black.withAlphaComponent(0.28).cgColor)

        switch style {
        case .tapered:
            // Huge pointed tip + narrow rounded tail (matching Figma / Shottr style)
            let refEnd = control ?? start
            let rawDir = CGPoint(x: end.x - refEnd.x, y: end.y - refEnd.y)
            let dLen = max(0.001, hypot(rawDir.x, rawDir.y))
            let dir = CGPoint(x: rawDir.x / dLen, y: rawDir.y / dLen)
            let perp = CGPoint(x: -dir.y, y: dir.x)

            let headLen = min(len * 0.62, max(15.0, width * 3.4))
            let neckDist = headLen * 0.76
            let neckPt = CGPoint(x: end.x - dir.x * neckDist, y: end.y - dir.y * neckDist)
            let wingBackPt = CGPoint(x: end.x - dir.x * headLen, y: end.y - dir.y * headLen)

            let wTail = max(1.1, width * 0.22)
            let wNeck = max(2.4, width * 0.85)
            let wHead = max(7.5, width * 2.45)

            // Tail direction at start
            let refStart = control ?? end
            let sVec = CGPoint(x: refStart.x - start.x, y: refStart.y - start.y)
            let sLen = max(0.001, hypot(sVec.x, sVec.y))
            let sDir = CGPoint(x: sVec.x / sLen, y: sVec.y / sLen)
            let sPerp = CGPoint(x: -sDir.y, y: sDir.x)

            let tailLeft = CGPoint(x: start.x + sPerp.x * wTail, y: start.y + sPerp.y * wTail)
            let tailRight = CGPoint(x: start.x - sPerp.x * wTail, y: start.y - sPerp.y * wTail)
            let tailBack = CGPoint(x: start.x - sDir.x * wTail * 1.4, y: start.y - sDir.y * wTail * 1.4)

            let neckLeft = CGPoint(x: neckPt.x + perp.x * wNeck, y: neckPt.y + perp.y * wNeck)
            let neckRight = CGPoint(x: neckPt.x - perp.x * wNeck, y: neckPt.y - perp.y * wNeck)
            let wingLeft = CGPoint(x: wingBackPt.x + perp.x * wHead, y: wingBackPt.y + perp.y * wHead)
            let wingRight = CGPoint(x: wingBackPt.x - perp.x * wHead, y: wingBackPt.y - perp.y * wHead)

            let path = CGMutablePath()
            path.move(to: tailLeft)
            if let c = control {
                let midW = (wTail + wNeck) * 0.5
                let mPerp = CGPoint(x: (sPerp.x + perp.x) * 0.5, y: (sPerp.y + perp.y) * 0.5)
                path.addQuadCurve(to: neckLeft, control: CGPoint(x: c.x + mPerp.x * midW, y: c.y + mPerp.y * midW))
            } else {
                path.addLine(to: neckLeft)
            }
            path.addLine(to: wingLeft)
            path.addLine(to: end)
            path.addLine(to: wingRight)
            path.addLine(to: neckRight)
            if let c = control {
                let midW = (wTail + wNeck) * 0.5
                let mPerp = CGPoint(x: (sPerp.x + perp.x) * 0.5, y: (sPerp.y + perp.y) * 0.5)
                path.addQuadCurve(to: tailRight, control: CGPoint(x: c.x - mPerp.x * midW, y: c.y - mPerp.y * midW))
            } else {
                path.addLine(to: tailRight)
            }
            path.addQuadCurve(to: tailLeft, control: tailBack)
            path.closeSubpath()

            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()

        case .filledSingle:
            let headLen = min(len * 0.48, max(11.0, width * 2.8))
            let headHalfW = max(5.5, width * 1.45)
            let endDir = unitDir(from: control ?? start, to: end)
            let shaftEnd = CGPoint(x: end.x - endDir.x * headLen * 0.72, y: end.y - endDir.y * headLen * 0.72)

            strokeShaft(start: start, end: shaftEnd, control: control, width: width, color: color, in: ctx)
            fillTriangleHead(tip: end, dir: endDir, length: headLen, halfWidth: headHalfW, color: color, in: ctx)

        case .openChevron:
            let headLen = min(len * 0.45, max(10.0, width * 2.6))
            let endDir = unitDir(from: control ?? start, to: end)
            let endPerp = CGPoint(x: -endDir.y, y: endDir.x)

            strokeShaft(start: start, end: end, control: control, width: max(1.8, width * 0.75), color: color, in: ctx)

            let wingL = CGPoint(x: end.x - endDir.x * headLen + endPerp.x * headLen * 0.65, y: end.y - endDir.y * headLen + endPerp.y * headLen * 0.65)
            let wingR = CGPoint(x: end.x - endDir.x * headLen - endPerp.x * headLen * 0.65, y: end.y - endDir.y * headLen - endPerp.y * headLen * 0.65)

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(1.8, width * 0.75))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: wingL)
            ctx.addLine(to: end)
            ctx.addLine(to: wingR)
            ctx.strokePath()

        case .doubleEnded:
            let headLen = min(len * 0.36, max(10.0, width * 2.6))
            let headHalfW = max(5.0, width * 1.4)
            let endDir = unitDir(from: control ?? start, to: end)
            let startDir = unitDir(from: control ?? end, to: start)

            let shaftStart = CGPoint(x: start.x - startDir.x * headLen * 0.72, y: start.y - startDir.y * headLen * 0.72)
            let shaftEnd = CGPoint(x: end.x - endDir.x * headLen * 0.72, y: end.y - endDir.y * headLen * 0.72)

            strokeShaft(start: shaftStart, end: shaftEnd, control: control, width: width, color: color, in: ctx)
            fillTriangleHead(tip: end, dir: endDir, length: headLen, halfWidth: headHalfW, color: color, in: ctx)
            fillTriangleHead(tip: start, dir: startDir, length: headLen, halfWidth: headHalfW, color: color, in: ctx)
        }

        ctx.restoreGState()
    }

    private static func unitDir(from p1: CGPoint, to p2: CGPoint) -> CGPoint {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let l = max(0.001, hypot(dx, dy))
        return CGPoint(x: dx / l, y: dy / l)
    }

    private static func strokeShaft(start: CGPoint, end: CGPoint, control: CGPoint?, width: CGFloat, color: NSColor, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: start)
        if let c = control {
            ctx.addQuadCurve(to: end, control: c)
        } else {
            ctx.addLine(to: end)
        }
        ctx.strokePath()
    }

    private static func fillTriangleHead(tip: CGPoint, dir: CGPoint, length: CGFloat, halfWidth: CGFloat, color: NSColor, in ctx: CGContext) {
        let perp = CGPoint(x: -dir.y, y: dir.x)
        let base = CGPoint(x: tip.x - dir.x * length, y: tip.y - dir.y * length)
        let p1 = CGPoint(x: base.x + perp.x * halfWidth, y: base.y + perp.y * halfWidth)
        let p2 = CGPoint(x: base.x - perp.x * halfWidth, y: base.y - perp.y * halfWidth)

        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: tip)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Dimension Ruler Rendering (Strictly Vertical or Horizontal, Crisp Pill)
    private static func drawDimensionRuler(ann: CanvasAnnotation, vStart: CGPoint, vEnd: CGPoint, scale: CGFloat, auditUnit: Int, in ctx: CGContext) {
        let dx = abs(ann.endPoint.x - ann.startPoint.x)
        let dy = abs(ann.endPoint.y - ann.startPoint.y)
        let dist = Int(round(max(dx, dy)))
        let ink = ann.color
        let isOffGrid = (auditUnit > 1) && (dist > 0) && (dist <= 96) && (dist % auditUnit != 0)

        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(max(1.4, 1.6 * min(1.5, scale)))
        ctx.strokeLineSegments(between: [vStart, vEnd])

        let tickLen: CGFloat = 6.5 * min(1.5, scale)
        let angle = atan2(vEnd.y - vStart.y, vEnd.x - vStart.x)
        let perp = angle + .pi / 2

        ctx.strokeLineSegments(between: [
            CGPoint(x: vStart.x + cos(perp) * tickLen, y: vStart.y + sin(perp) * tickLen),
            CGPoint(x: vStart.x - cos(perp) * tickLen, y: vStart.y - sin(perp) * tickLen),
            CGPoint(x: vEnd.x + cos(perp) * tickLen, y: vEnd.y + sin(perp) * tickLen),
            CGPoint(x: vEnd.x - cos(perp) * tickLen, y: vEnd.y - sin(perp) * tickLen)
        ])

        let mid = CGPoint(x: (vStart.x + vEnd.x) / 2, y: (vStart.y + vEnd.y) / 2)
        drawMeasurementPill(text: "\(dist)px", at: mid, fill: ink, showOffGridDot: isOffGrid)
    }

    public static func drawMeasurementPill(text: String, at center: CGPoint, fill: NSColor, showOffGridDot: Bool = false) {
        let str = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: fill.relativeLuminance > 0.65 ? NSColor.black : NSColor.white
        ]
        let s = str.size(withAttributes: attrs)
        let extraDotW: CGFloat = showOffGridDot ? 8 : 0
        let w = s.width + 12 + extraDotW
        let h: CGFloat = 19
        let r = NSRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)

        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 4.5, yRadius: 4.5).fill()
        str.draw(at: NSPoint(x: r.origin.x + 6, y: r.origin.y + 3), withAttributes: attrs)

        if showOffGridDot {
            let dotR = NSRect(x: r.maxX - 9, y: r.midY - 2.5, width: 5, height: 5)
            NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: dotR).fill()
        }
    }

    // MARK: - Rectangle / Card Rendering (Stroke Default, Tinted, Solid Fill, Width, Corner Radius)
    private static func drawRectangle(ann: CanvasAnnotation, vStart: CGPoint, vEnd: CGPoint, scale: CGFloat, in ctx: CGContext) {
        let r = normalizedRect(from: vStart, to: vEnd)
        let cr = ann.cornerRadius * scale
        let strokeW = max(1.0, ann.strokeWidth * scale)
        let ink = ann.color
        let path = NSBezierPath(roundedRect: r, xRadius: cr, yRadius: cr)

        ctx.saveGState()
        switch ann.rectFillMode {
        case .stroke:
            ink.setStroke()
            path.lineWidth = strokeW
            path.stroke()

        case .tinted:
            ink.withAlphaComponent(0.18).setFill()
            path.fill()
            ink.setStroke()
            path.lineWidth = strokeW
            path.stroke()

        case .solid:
            ink.setFill()
            path.fill()
        }
        ctx.restoreGState()

        if ann.showSizeTag {
            let imgW = Int(round(abs(ann.endPoint.x - ann.startPoint.x)))
            let imgH = Int(round(abs(ann.endPoint.y - ann.startPoint.y)))
            let tagText = "\(imgW) × \(imgH) px" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = tagText.size(withAttributes: attrs)
            let tagRect = NSRect(x: r.minX, y: r.maxY + 4, width: size.width + 10, height: 16)
            NSColor.black.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: tagRect, xRadius: 3.5, yRadius: 3.5).fill()
            tagText.draw(at: NSPoint(x: tagRect.origin.x + 5, y: tagRect.origin.y + 2), withAttributes: attrs)
        }
    }

    // MARK: - Text Callout Rendering (Plain Text | Pill Card | Speech Quote Bubble)
    private static func drawTextCallout(ann: CanvasAnnotation, mapper: Mapper, in ctx: CGContext) {
        let s = mapper.scale
        let imgBox = textImageBounds(for: ann)
        let vTopLeft = mapper.toCanvasPoint(imgBox.origin)
        let vBottomRight = mapper.toCanvasPoint(CGPoint(x: imgBox.maxX, y: imgBox.maxY))
        let r = normalizedRect(from: vTopLeft, to: vBottomRight)

        let fontSize = max(10, min(48, ann.strokeWidth > 8 ? ann.strokeWidth : 16)) * s
        let displayText = (ann.text.isEmpty ? "Text" : ann.text) as NSString
        let textColor = ann.color
        let font = NSFont.systemFont(ofSize: fontSize, weight: ann.textStyle == .plain ? .semibold : .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let padX: CGFloat = (ann.textStyle == .plain ? 4 : 12) * s
        let padY: CGFloat = (ann.textStyle == .plain ? 2 : 7) * s
        let textDrawRect = NSRect(
            x: r.origin.x + padX,
            y: r.origin.y + padY,
            width: max(10, r.width - padX * 2),
            height: max(10, r.height - padY * 2)
        )

        ctx.saveGState()
        switch ann.textStyle {
        case .plain:
            // High-legibility subtle shadow so plain text pops cleanly over dark/light backgrounds
            let isLightInk = textColor.relativeLuminance > 0.45
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 3.5,
                color: (isLightInk ? NSColor.black : NSColor.white).withAlphaComponent(0.60).cgColor
            )
            displayText.draw(in: textDrawRect, withAttributes: attrs)

        case .card:
            let bg = textColor.relativeLuminance > 0.45
                ? NSColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.90)
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.95)
            let border = textColor.relativeLuminance > 0.45
                ? NSColor.white.withAlphaComponent(0.18)
                : NSColor.black.withAlphaComponent(0.12)

            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: NSColor.black.withAlphaComponent(0.22).cgColor)
            let cardPath = NSBezierPath(roundedRect: r, xRadius: 7 * s, yRadius: 7 * s)
            bg.setFill()
            cardPath.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            border.setStroke()
            cardPath.lineWidth = 1.0
            cardPath.stroke()

            displayText.draw(in: textDrawRect, withAttributes: attrs)

        case .quoteBubble:
            let bg = textColor.relativeLuminance > 0.45
                ? NSColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.92)
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.96)
            let border = textColor.relativeLuminance > 0.45
                ? NSColor.white.withAlphaComponent(0.20)
                : NSColor.black.withAlphaComponent(0.14)

            let bubblePath = speechBubblePath(rect: r, cornerRadius: 9 * s, tailWidth: 12 * s, tailHeight: 9 * s)
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.24).cgColor)
            bg.setFill()
            bubblePath.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            border.setStroke()
            bubblePath.lineWidth = 1.0
            bubblePath.stroke()

            displayText.draw(in: textDrawRect, withAttributes: attrs)
        }
        ctx.restoreGState()
    }

    private static func speechBubblePath(rect r: NSRect, cornerRadius cr: CGFloat, tailWidth tw: CGFloat, tailHeight th: CGFloat) -> NSBezierPath {
        let radius = min(cr, min(r.width, r.height) / 2)
        let tailStartX = min(r.maxX - radius - tw, r.minX + radius + 8)
        let tailTipX = tailStartX - 2

        let p = NSBezierPath()
        // Bottom edge starting after tail
        p.move(to: NSPoint(x: tailStartX + tw, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: 270, endAngle: 0, clockwise: false)
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: 0, endAngle: 90, clockwise: false)
        p.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
        p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: 90, endAngle: 180, clockwise: false)
        p.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: 180, endAngle: 270, clockwise: false)
        p.line(to: NSPoint(x: tailStartX, y: r.minY))
        // Clean speech bubble pointer tail
        p.curve(to: NSPoint(x: tailTipX, y: r.minY - th),
                controlPoint1: NSPoint(x: tailStartX, y: r.minY - th * 0.45),
                controlPoint2: NSPoint(x: tailTipX + 2, y: r.minY - th))
        p.curve(to: NSPoint(x: tailStartX + tw, y: r.minY),
                controlPoint1: NSPoint(x: tailStartX + tw * 0.45, y: r.minY - th * 0.65),
                controlPoint2: NSPoint(x: tailStartX + tw * 0.8, y: r.minY))
        p.close()
        return p
    }

    // MARK: - Pin & Highlighter
    private static func drawNumberedPin(number: Int, center: CGPoint, diameter: CGFloat, color: NSColor, scale: CGFloat, in ctx: CGContext) {
        let r = NSRect(x: center.x - diameter/2, y: center.y - diameter/2, width: diameter, height: diameter)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        color.setFill()
        let circle = NSBezierPath(ovalIn: r)
        circle.fill()
        ctx.restoreGState()

        let strokeColor = color.relativeLuminance > 0.72 ? NSColor.black.withAlphaComponent(0.85) : NSColor.white
        strokeColor.setStroke()
        circle.lineWidth = max(1.4, 1.6 * min(1.4, scale))
        circle.stroke()

        let text = "\(number)" as NSString
        let fontSize = max(10, diameter * 0.50)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color.relativeLuminance > 0.72 ? NSColor.black : NSColor.white
        ]
        let s = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: center.x - s.width / 2, y: center.y - s.height / 2), withAttributes: attrs)
    }

    private static func drawHighlighter(points: [CGPoint], width: CGFloat, color: NSColor) {
        guard !points.isEmpty else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for pt in points.dropFirst() { path.line(to: pt) }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.withAlphaComponent(0.38).setStroke()
        path.stroke()
    }

    public static func normalizedRect(from p1: CGPoint, to p2: CGPoint) -> NSRect {
        NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: max(1, abs(p1.x - p2.x)),
            height: max(1, abs(p1.y - p2.y))
        )
    }
}
