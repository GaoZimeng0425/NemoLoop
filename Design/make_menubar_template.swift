// Renders the menu-bar template icon: the B1 "回环点" mark reduced to its
// silhouette — an open ring (gap at the upper left) plus a dot sitting ON the
// ring in that gap. Black + alpha only; the imageset is declared template so
// macOS tints it for light/dark menu bars. Run: swift make_menubar_template.swift <outDir>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: swift make_menubar_template.swift <output-dir>\n", stderr)
    exit(1)
}
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// B1 proportions on a unit canvas: circle r=5 at 16pt, stroke 1.8pt, dot r=1.5pt.
// The gap is WIDER than B1's own (70°…170° vs 80°…160°): at 16–18pt the dot and
// the round caps otherwise swallow the notch and the mark reads as a solid ring.
func render(pointSize: CGFloat, scale: CGFloat, name: String) {
    let px = Int(pointSize * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) // canvas edge; all geometry scales from the 16pt proportions
    let black = NSColor.black

    let radius = s * (5.0 / 16.0)
    let stroke = s * (1.8 / 16.0)
    let center = NSPoint(x: s / 2, y: s / 2)

    let arc = NSBezierPath()
    arc.lineWidth = stroke
    arc.lineCapStyle = .round
    // From 70° clockwise the long way round to 170°: the gap opens upper-left.
    arc.appendArc(withCenter: center, radius: radius,
                  startAngle: 70, endAngle: 170, clockwise: true)
    black.setStroke()
    arc.stroke()

    let dotAngle = 120.0 * Double.pi / 180
    let dotCenter = NSPoint(x: center.x + radius * CGFloat(cos(dotAngle)),
                            y: center.y + radius * CGFloat(sin(dotAngle)))
    let dot = NSBezierPath(ovalIn: NSRect(x: dotCenter.x - stroke * 0.83,
                                          y: dotCenter.y - stroke * 0.83,
                                          width: stroke * 1.66, height: stroke * 1.66))
    black.setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(name) (\(px)px)")
}

render(pointSize: 16, scale: 1, name: "menubar-16.png")
render(pointSize: 16, scale: 2, name: "menubar-16@2x.png")
render(pointSize: 18, scale: 1, name: "menubar-18.png")
render(pointSize: 18, scale: 2, name: "menubar-18@2x.png")
