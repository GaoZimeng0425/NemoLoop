// NemoLoop/Ring/SceneKitRingSpike.swift
import SwiftUI
import SceneKit

/// Spike: the ring rendered by SceneKit instead of SwiftUI so blades get REAL
/// per-pixel depth — each blade is a tilted plane node and the wrap seam's
/// overlap (first blade under the last) falls out of the depth buffer, which
/// painter's-algorithm `zIndex` can never do.
///
/// Everything else (summon lifecycle, pointer sampling, dead zone, commit) is
/// unchanged: `RingViewModel.highlightedIndex` still drives the highlight, the
/// SceneKit view only renders it.
enum SceneKitRingSpike {
    /// Flip to false to fall back to the SwiftUI `RingView`.
    static let enabled = true

    // Spike knobs — tweak by eye.
    static let bladeTiltDegrees: Double = 14   // turbine lean about the radial axis
    static let cameraHeight: CGFloat = 420     // near-top-down; some slant shows the 3D
    static let cameraSlant: CGFloat = 120
}

struct SceneKitRingView: NSViewRepresentable {
    let icons: [NSImage?]
    let viewModel: RingViewModel

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.scene = Self.makeScene(icons: icons)
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        return view
    }

    /// `highlightedIndex` is observed here: SwiftUI re-invokes updateNSView on
    /// every change and we repaint the emissive wash on the winning blade.
    func updateNSView(_ view: SCNView, context: Context) {
        let highlighted = viewModel.highlightedIndex
        guard let blades = view.scene?.rootNode.childNode(withName: "blades", recursively: false) else { return }
        for (i, blade) in blades.childNodes.enumerated() {
            guard let mat = blade.geometry?.firstMaterial else { continue }
            mat.emission.contents = i == highlighted
                ? NSColor(calibratedWhite: 1, alpha: 0.5)
                : NSColor.clear
        }
    }

    // MARK: - Scene

    private static func makeScene(icons: [NSImage?]) -> SCNScene {
        let scene = SCNScene()
        let count = max(1, icons.count)
        let pitch = count > 1
            ? min(RingTheme.bladeDegrees,
                  (360 - RingTheme.arcGapDegrees - RingTheme.bladeDegrees) / Double(count - 1))
            : 0

        let inner = RingTheme.innerRadius
        let outer = RingTheme.outerRadius
        let mid = RingTheme.midRadius

        let blades = SCNNode()
        blades.name = "blades"
        for i in 0..<count {
            // from-up clockwise angle of the blade's center, matching BladeLayout
            // (blade 0 centered on up, wrap gap counterclockwise of it).
            let start = -RingTheme.bladeDegrees / 2
            let angle = (start + RingTheme.bladeDegrees / 2 + Double(i) * pitch) * .pi / 180

            let pivot = SCNNode()
            // SceneKit is y-up; the ring lies in the XZ plane. Screen-up is world +Z
            // (the camera's worldUp), so a from-up cw angle maps to -angle about Y.
            pivot.rotation = SCNVector4(0, 1, 0, Float(-angle))

            let shape = SCNShape(path: cardPath(width: bladeCardWidth, height: outer - inner),
                                 extrusionDepth: 0.5)
            let mat = SCNMaterial()
            mat.lightingModel = .constant          // unlit: UI look, no lights needed
            if let icon = icons[i] {
                mat.diffuse.contents = icon
                mat.multiply.contents = NSColor(calibratedWhite: 0.6, alpha: 1) // tint icons toward the card color
            } else {
                mat.diffuse.contents = NSColor(calibratedWhite: 0.92, alpha: 0.9)
            }
            mat.transparency = 0.92
            shape.materials = [mat]

            let blade = SCNNode(geometry: shape)
            // Lay the card flat (X = tangential, Z = radial), then lean it about its
            // RADIAL axis so the leading tangential edge lifts over the neighbour —
            // the wrap seam closes because depth testing, not draw order, decides.
            blade.eulerAngles = SCNVector3(-Float.pi / 2, 0, Float(-SceneKitRingSpike.bladeTiltDegrees * .pi / 180))
            blade.position = SCNVector3(0, 0, Float(mid))
            pivot.addChildNode(blade)
            blades.addChildNode(pivot)
        }
        scene.rootNode.addChildNode(blades)

        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 1
        camera.zFar = 1000   // default is 100 — the ring sits ~330 away and was fully clipped
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, Float(SceneKitRingSpike.cameraHeight), Float(SceneKitRingSpike.cameraSlant))
        // A camera looks down its local -Z; say so explicitly, keep world +Z as screen-up.
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private static let bladeCardWidth: CGFloat = 64

    /// Rounded card like the SwiftUI blades; SCNShape wants an NSBezierPath.
    private static func cardPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let rect = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
        return NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    }
}
