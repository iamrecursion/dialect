import CoreText
import Foundation

// Builds Dialect's custom SF Symbol templates (the file manager's Session, Scheme and Delete
// Permanently icons) from the SF Symbols app's font: the outlines of the system symbols they're
// made from, at every weight and scale, combined with CoreGraphics' boolean path operations. It
// writes static templates, with all 27 variants drawn, so nothing has to interpolate between paths
// that boolean operations have made incompatible.
//
// Needs macOS with the SF Symbols app installed. To regenerate the app's symbols, from the
// repository's root:
//
//     swift utils/custom-symbols/generate.swift /tmp/symbols
//
// then copy each SVG over the one in its `Dialect/Assets.xcassets/<name>.symbolset`. The templates
// open in the SF Symbols app for hand refinement.

guard CommandLine.arguments.count == 2 else {
    print("usage: swift generate.swift <output directory>")
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let fontURL = URL(
    fileURLWithPath: "/Applications/SF Symbols.app/Contents/Resources/Fonts/SFSymbolsFallback.otf")
let baseFont = CTFontCreateWithFontDescriptor(
    (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor])[0], 100,
    nil)

// The font's named instances.
let weights: [(String, Double)] = [
    ("Ultralight", 28.93), ("Thin", 112.72), ("Light", 276.31), ("Regular", 400), ("Medium", 508),
    ("Semibold", 590.8), ("Bold", 700), ("Heavy", 858.4), ("Black", 1000),
]
let scales: [(String, String)] = [("S", "small"), ("M", "medium"), ("L", "large")]

// The font names its symbols' glyphs by code point only (`uni100AFF.small`), so these were found by
// rendering each system symbol with AppKit and matching it against every glyph's outline.
let documentBadgeClockFill = "uni100AFF"
let ellipsisCurlybraces = "uni1011F5"
let parentheses = "uni100E0F"
let trash = "uni100211"
let exclamationmarkTriangleFill = "uni1006E4"
let exclamationmarkTriangle = "uni1001FE"

struct Glyph {
    let path: CGPath
    let advance: CGFloat
}

func glyph(_ name: String, scale: String, weight: Double) -> Glyph {
    let font = CTFontCreateCopyWithAttributes(
        baseFont, 100, nil,
        CTFontDescriptorCreateWithAttributes(
            [kCTFontVariationAttribute: [0x7767_6874: weight]] as CFDictionary))
    var g = CTFontGetGlyphWithName(font, "\(name).\(scale)" as CFString)
    precondition(g != 0, "no glyph \(name).\(scale)")
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
    return Glyph(path: CTFontCreatePathForGlyph(font, g, nil)!, advance: advance.width)
}

/// A glyph that has no scale variants, such as a letter.
func latinGlyph(_ name: String, weight: Double) -> CGPath {
    let font = CTFontCreateCopyWithAttributes(
        baseFont, 100, nil,
        CTFontDescriptorCreateWithAttributes(
            [kCTFontVariationAttribute: [0x7767_6874: weight]] as CFDictionary))
    let g = CTFontGetGlyphWithName(font, name as CFString)
    precondition(g != 0, "no glyph \(name)")
    return CTFontCreatePathForGlyph(font, g, nil)!
}

func parts(_ path: CGPath) -> [CGPath] {
    return path.componentsSeparated(using: .winding)
}

func union(_ paths: [CGPath]) -> CGPath {
    return paths.dropFirst().reduce(paths[0]) { $0.union($1, using: .winding) }
}

/// The path grown by `distance` all round, for the gap around a badge.
func outset(_ path: CGPath, by distance: CGFloat) -> CGPath {
    let stroke = path.copy(
        strokingWithWidth: distance * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
    return path.union(stroke, using: .winding)
}

func transformed(_ path: CGPath, _ t: CGAffineTransform) -> CGPath {
    var t = t
    return path.copy(using: &t)!
}

// MARK: The symbols

/// A filled document with a λ in a circle at its bottom left:
/// `document.badge.clock.fill`, whose badge is already there, with the clock's
/// hands swapped for a λ.
func session(scale: String, weight: Double) -> (CGPath, base: Glyph) {
    let source = glyph(documentBadgeClockFill, scale: scale, weight: weight)
    // The document (cut for the badge), its folded corner, and the badge: the lowest part.
    let pieces = parts(source.path).sorted { $0.boundingBoxOfPath.minY < $1.boundingBoxOfPath.minY }
    let badge = pieces[0].boundingBoxOfPath
    let document = union(Array(pieces.dropFirst()))
    let r = badge.width / 2
    let center = CGPoint(x: badge.midX, y: badge.midY)

    // The font's λ at the symbol's weight, centered in the badge and three quarters of its height,
    // so it reads on the watch.
    let lambda = latinGlyph("lambda.grek", weight: weight)
    let l = lambda.boundingBoxOfPath
    let k = 1.5 * r / l.height
    let letter = transformed(
        lambda,
        CGAffineTransform(
            a: k, b: 0, c: 0, d: k, tx: center.x - l.midX * k, ty: center.y - l.midY * k))
    let circle = CGPath(ellipseIn: badge, transform: nil)
    let disc = circle.subtracting(letter, using: .winding)
    return (union([document, disc]), source)
}

/// `ellipsis.curlybraces` with each brace replaced by a parenthesis from
/// `parentheses`, scaled to the brace's height.
func scheme(scale: String, weight: Double) -> (CGPath, base: Glyph) {
    let source = glyph(ellipsisCurlybraces, scale: scale, weight: weight)
    let pieces = parts(source.path).sorted { $0.boundingBoxOfPath.minX < $1.boundingBoxOfPath.minX }
    let (leftBrace, rightBrace) = (pieces.first!, pieces.last!)
    let dots = Array(pieces.dropFirst().dropLast())
    let parens = parts(glyph(parentheses, scale: scale, weight: weight).path)
        .sorted { $0.boundingBoxOfPath.minX < $1.boundingBoxOfPath.minX }

    func fit(_ paren: CGPath, to brace: CGPath, alignLeft: Bool) -> CGPath {
        let p = paren.boundingBoxOfPath
        let b = brace.boundingBoxOfPath
        let k = b.height / p.height
        let x = alignLeft ? b.minX - p.minX * k : b.maxX - p.maxX * k
        return transformed(
            paren, CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: x, ty: b.minY - p.minY * k))
    }
    let left = fit(parens.first!, to: leftBrace, alignLeft: true)
    let right = fit(parens.last!, to: rightBrace, alignLeft: false)
    return (union([left, right] + dots), source)
}

/// `trash` with `exclamationmark.triangle.fill` over its lower right, and a gap
/// cut around the triangle, as SF Symbols' badges have.
func trashPermanent(scale: String, weight: Double) -> (CGPath, base: Glyph) {
    let source = glyph(trash, scale: scale, weight: weight)
    let can = source.path.boundingBoxOfPath
    // The font's filled triangle is solid: its "!" is a separate layer. The outline triangle has
    // the "!" as its own contours, everything but the ring, and they line up with the filled one.
    let solid = glyph(exclamationmarkTriangleFill, scale: scale, weight: weight).path
    let outline = parts(glyph(exclamationmarkTriangle, scale: scale, weight: weight).path)
        .sorted { $0.boundingBoxOfPath.width > $1.boundingBoxOfPath.width }
    let triangle = solid.subtracting(union(Array(outline.dropFirst())), using: .winding)
    let t = triangle.boundingBoxOfPath
    let k = 0.6 * can.width / t.width
    let x = can.maxX + 0.12 * can.width - t.maxX * k
    let y = can.minY - 0.06 * can.height - t.minY * k
    let place = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: x, ty: y)
    let badge = transformed(triangle, place)
    // The gap follows the triangle's outline only: grown from the "!" too, it leaves a stray blob.
    let gap = 0.05 * can.height
    let cut = source.path.subtracting(outset(transformed(solid, place), by: gap), using: .winding)
    return (cut.union(badge, using: .winding), source)
}

// MARK: SVG

func svgPath(_ path: CGPath, dx: CGFloat) -> String {
    var d = ""
    func p(_ point: CGPoint) -> String {
        return String(format: "%.3f %.3f", point.x + dx, -point.y)
    }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: d += "M\(p(e.points[0]))"
        case .addLineToPoint: d += "L\(p(e.points[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
        case .addCurveToPoint: d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func template(_ make: (String, Double) -> (CGPath, base: Glyph)) -> String {
    let baselines: [String: CGFloat] = ["S": 696, "M": 1126, "L": 1556]
    var guides = ""
    var symbols = ""
    for (scaleID, scale) in scales {
        let baseline = baselines[scaleID]!
        guides += """
              <line id="Baseline-\(scaleID)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(baseline)" y2="\(baseline)"/>
              <line id="Capline-\(scaleID)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\(String(format: "%.3f", baseline - 70.459))" y2="\(String(format: "%.3f", baseline - 70.459))"/>

            """
        for (column, (weightName, weight)) in weights.enumerated() {
            let (path, base) = make(scale, weight)
            let box = path.boundingBoxOfPath
            let baseBox = base.path.boundingBoxOfPath
            // Keep the base symbol's side bearings, and widen the margins for anything that sticks
            // out past its ink.
            let leftMargin = min(0, box.minX - baseBox.minX)
            let rightMargin = base.advance + max(0, box.maxX - baseBox.maxX)
            let width = rightMargin - leftMargin
            let center: CGFloat = 560 + CGFloat(column) * 296
            let left = center - width / 2
            let id = "\(weightName)-\(scaleID)"
            let f = { (v: CGFloat) in String(format: "%.3f", v) }
            guides += """
                  <line id="left-margin-\(id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(f(left))" x2="\(f(left))" y1="\(f(baseline - 95.2))" y2="\(f(baseline + 24.1))"/>
                  <line id="right-margin-\(id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(f(left + width))" x2="\(f(left + width))" y1="\(f(baseline - 95.2))" y2="\(f(baseline + 24.1))"/>

                """
            symbols += """
                  <g id="\(id)" transform="matrix(1 0 0 1 \(f(left)) \(f(baseline)))">
                   <path class="monochrome-0 multicolor-0:tintColor hierarchical-0:primary" d="\(svgPath(path, dx: -leftMargin))"/>
                  </g>

                """
        }
    }
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
         <!--glyph: "", point size: 100.0, template writer version: "Dialect 1"-->
         <style>.monochrome-0 {-sfsymbols-motion-group:0}
        .SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}
        </style>
         <g id="Notes">
          <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
         </g>
         <g id="Guides">
        \(guides) </g>
         <g id="Symbols">
        \(symbols) </g>
        </svg>

        """
}

for (name, make) in [
    ("session", session), ("scheme", scheme), ("trash.permanent", trashPermanent),
] as [(String, (String, Double) -> (CGPath, base: Glyph))] {
    let url = output.appending(path: "\(name).svg")
    try! template(make).write(to: url, atomically: true, encoding: .utf8)
    print("wrote", url.path)
}
