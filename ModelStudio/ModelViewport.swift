import SceneKit
import SwiftUI

struct ViewportEdit {
    var point: Int?
    var normal: SIMD3<Double>?
    let apply: (SIMD3<Double>) -> Void
}

final class PickingSceneView: SCNView {
    struct Drag {
        let anchor: SCNVector3
        let modelUnitsPerSceneUnit: Double
        let edit: ViewportEdit
    }

    var onPick: ((CGPoint) -> Void)?
    var onBeginEdit: ((CGPoint) -> Drag?)?
    private var drag: Drag?
    private var down: CGPoint?
    private var moved = false
    private let dragMarker = SCNNode(geometry: SCNSphere(radius: 0.035))
    private var orientationCube: OrientationCube?
    private var orientationTimer: Timer?

    private func mouseLocation(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        let point = mouseLocation(event)
        down = point
        moved = false
        drag = onBeginEdit?(point)
        if drag == nil { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let location = mouseLocation(event)
        moved = moved || hypot(location.x - down.x, location.y - down.y) > 3
        guard let drag else { super.mouseDragged(with: event); return }
        if moved, let displacement = displacement(from: down, to: location, drag: drag) {
            let p = displacement / drag.modelUnitsPerSceneUnit
            if dragMarker.parent == nil {
                let material = dragMarker.geometry?.firstMaterial
                material?.diffuse.contents = NSColor.systemOrange
                material?.lightingModel = .constant
                material?.readsFromDepthBuffer = false
                material?.writesToDepthBuffer = false
                dragMarker.renderingOrder = 5
                dragMarker.categoryBitMask = 2
                scene?.rootNode.addChildNode(dragMarker)
            }
            dragMarker.simdPosition = SIMD3<Float>(drag.anchor) + SIMD3<Float>(Self.sceneVector(p))
            dragMarker.isHidden = false
        } else {
            dragMarker.isHidden = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let drag = self.drag
        let start = down
        let location = mouseLocation(event)
        self.drag = nil
        down = nil
        dragMarker.isHidden = true
        if drag == nil { super.mouseUp(with: event) }
        if let start, moved, let drag, let delta = displacement(from: start, to: location, drag: drag) {
            drag.edit.apply(delta)
        } else if start != nil && !moved {
            onPick?(location)
        }
    }

    private static func sceneVector(_ model: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(model.x, model.z, -model.y)
    }

    func displacement(from start: CGPoint, to end: CGPoint, drag: Drag) -> SIMD3<Double>? {
        let anchor = projectPoint(drag.anchor)
        let from = SIMD3<Double>(unprojectPoint(SCNVector3(start.x, start.y, anchor.z)))
        let to = SIMD3<Double>(unprojectPoint(SCNVector3(end.x, end.y, anchor.z)))
        let delta = to - from
        let result: SIMD3<Double>
        if let normal = drag.edit.normal {
            let along = projectPoint(SCNVector3(SIMD3<Float>(drag.anchor) + SIMD3<Float>(Self.sceneVector(normal)) * 0.1))
            let screenDirection = SIMD2(Double(along.x - anchor.x), Double(along.y - anchor.y))
            let pixels = SIMD2(Double(end.x - start.x), Double(end.y - start.y))
            let projected = simd_length_squared(screenDirection)
            let distance: Double
            if projected > 9 {
                distance = 0.1 * simd_dot(pixels, screenDirection) / projected
            } else {
                // In a straight-on view, pull upward to move along a normal hidden in depth.
                let up = SIMD3<Double>(unprojectPoint(SCNVector3(start.x, end.y, anchor.z)))
                distance = simd_length(up - from) * (end.y >= start.y ? 1 : -1)
            }
            guard distance > 0 else { return nil }
            result = normal * distance
        } else {
            result = SIMD3(delta.x, -delta.z, delta.y)
        }
        let modelDelta = result * drag.modelUnitsPerSceneUnit
        let length = simd_length(modelDelta)
        return length.isFinite && length > 0 ? modelDelta : nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard drag == nil else { return }
        guard allowsCameraControl, let camera = pointOfView?.camera else {
            super.scrollWheel(with: event)
            return
        }
        // Change magnification without moving the orbit camera through the model.
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.004 : 0.08
        let step = min(max(event.scrollingDeltaY * sensitivity, -0.35), 0.35)
        camera.fieldOfView = min(max(camera.fieldOfView * exp(-step), 12), 100)
    }

    fileprivate static let homeEye = SIMD3<Float>(2.3, 1.9, 3.2)

    fileprivate func addOrientationControls() {
        let cube = OrientationCube(frame: .zero)
        cube.onFace = { [weak self] direction in
            self?.orient(from: direction * simd_length(Self.homeEye))
        }
        orientationCube = cube
        let home = NSButton(image: NSImage(systemSymbolName: "house", accessibilityDescription: "Home View")!,
                            target: self, action: #selector(resetView))
        home.toolTip = "Home View"
        home.setAccessibilityIdentifier("homeView")
        home.bezelStyle = .rounded
        let controls = NSStackView(views: [home, cube])
        controls.orientation = .vertical
        controls.alignment = .trailing
        controls.spacing = 5
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cube.widthAnchor.constraint(equalToConstant: 84),
            cube.heightAnchor.constraint(equalToConstant: 84)
        ])
    }

    @objc private func resetView() {
        pointOfView?.camera?.fieldOfView = 60
        orient(from: Self.homeEye)
    }

    private func orient(from direction: SIMD3<Float>) {
        guard let eye = pointOfView, drag == nil else { return }
        let up = abs(direction.y) > abs(direction.x) + abs(direction.z) ? SIMD3<Float>(0, 0, -1) : SIMD3<Float>(0, 1, 0)
        defaultCameraController.stopInertia()
        eye.simdPosition = direction
        eye.simdLook(at: .zero, up: up, localFront: SIMD3(0, 0, -1))
        defaultCameraController.target = SCNVector3Zero
        orientationCube?.sync(with: eye)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        orientationTimer?.invalidate()
        orientationTimer = nil
        guard window != nil, orientationCube != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let eye = self.pointOfView else { return }
                self.orientationCube?.sync(with: eye.presentation)
            }
        }
        orientationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { orientationTimer?.invalidate() }
}

private final class OrientationCube: SCNView {
    var onFace: ((SIMD3<Float>) -> Void)?
    private let eye = SCNNode()
    private let box: SCNBox
    private static let faces: [(label: String, direction: SIMD3<Float>)] = [
        ("FRONT", [0, 0, 1]), ("RIGHT", [1, 0, 0]), ("BACK", [0, 0, -1]),
        ("LEFT", [-1, 0, 0]), ("TOP", [0, 1, 0]), ("BOTTOM", [0, -1, 0])
    ]

    override init(frame: CGRect) {
        box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        super.init(frame: frame, options: nil)
        box.materials = Self.faces.map { Self.material(label: $0.label) }
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: box))
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.05
        eye.camera = camera
        scene.rootNode.addChildNode(eye)
        self.scene = scene
        pointOfView = eye
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        toolTip = "View Cube · Click a face to align the view"
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("View Cube")
        setAccessibilityIdentifier("viewCube")
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func sync(with source: SCNNode) {
        let rotation = source.simdOrientation
        guard eye.simdOrientation.vector != rotation.vector || eye.simdPosition == .zero else { return }
        eye.simdOrientation = rotation
        eye.simdPosition = rotation.act(SIMD3(0, 0, 4))
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(location, options: nil).first, Self.faces.indices.contains(hit.geometryIndex) else { return }
        onFace?(Self.faces[hit.geometryIndex].direction)
    }

    private static func material(label: String) -> SCNMaterial {
        let image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSColor(srgbRed: 0.16, green: 0.23, blue: 0.29, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.50, green: 0.66, blue: 0.69, alpha: 1).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 2, dy: 2))
            border.lineWidth = 4
            border.stroke()
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 23, weight: .semibold),
                .foregroundColor: NSColor.white
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        return material
    }
}

struct ModelViewport: NSViewRepresentable {
    let mesh: EditableMesh
    let selectedFaces: Set<Int>
    let selectedPoint: Int?
    var affectedSelection: Set<Int> = []
    var inspectionEdge: SIMD2<Int>?
    var inspectingIssue = false
    var showsOrientation = false
    var beginEdit: ((Int, Int) -> ViewportEdit?)?
    let pick: (Int, Int) -> Void

    final class Coordinator {
        let surface = SCNNode()
        let wire = SCNNode()
        let faceOutline = SCNNode()
        let edgeOverlay = SCNNode()
        var shownEdge: SIMD2<Int>?
        let marker = SCNNode(geometry: SCNSphere(radius: 0.028))
        var displayed: EditableMesh?
        var highlighted: Set<Int> = []
        var highlightedSelection: Set<Int> = []
        private var showingIssueOutline = false
        var faceGroups: [[Int]] = []
        var positions: [SCNVector3] = []
        private(set) var modelUnitsPerSceneUnit = 1.0
        var vertexSource: SCNGeometrySource?
        var normalSource: SCNGeometrySource?

        init() {
            wire.categoryBitMask = 2
            faceOutline.categoryBitMask = 2
            faceOutline.renderingOrder = 2
            edgeOverlay.categoryBitMask = 2
            edgeOverlay.renderingOrder = 3
            marker.categoryBitMask = 2
            wire.renderingOrder = 1
            marker.renderingOrder = 4
            marker.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        }

        func update(mesh: EditableMesh, selection: Set<Int>, point: Int?, affectedSelection: Set<Int> = [],
                    inspectionEdge: SIMD2<Int>? = nil, inspectingIssue: Bool = false) {
            let changed = displayed != mesh
            if changed {
                // Normalize the display copy. Source coordinates and face IDs remain in model space.
                let (low, high) = mesh.surfaceBounds
                let center = high * 0.5 + low * 0.5
                let radius = (high * 0.5 - low * 0.5).max()
                modelUnitsPerSceneUnit = radius > 0 ? radius : 1
                positions = mesh.vertices.map {
                    let p = ($0 - center) / modelUnitsPerSceneUnit
                    return SCNVector3(p.x, p.z, -p.y)
                }
                var corners: [SCNVector3] = []
                var normals: [SCNVector3] = []
                for face in mesh.faces {
                    let v = face.vertices
                    let a = positions[v.x], b = positions[v.y], c = positions[v.z]
                    let cross = simd_cross(SIMD3<Float>(b) - SIMD3<Float>(a), SIMD3<Float>(c) - SIMD3<Float>(a))
                    let n = simd_length_squared(cross) > 0 ? simd_normalize(cross) : SIMD3(0, 1, 0)
                    corners.append(contentsOf: [a, b, c])
                    normals.append(contentsOf: repeatElement(SCNVector3(n), count: 3))
                }
                vertexSource = SCNGeometrySource(vertices: corners)
                normalSource = SCNGeometrySource(normals: normals)
                let triangles = SCNGeometryElement(data: nil, primitiveType: .triangles,
                                                   primitiveCount: mesh.faces.count, bytesPerIndex: 0)
                let outline = SCNGeometry(sources: [vertexSource!], elements: [triangles])
                let ink = SCNMaterial()
                ink.fillMode = .lines
                ink.lightingModel = .constant
                ink.diffuse.contents = NSColor.darkGray
                ink.isDoubleSided = true
                ink.writesToDepthBuffer = false
                outline.materials = [ink]
                wire.geometry = outline
                displayed = mesh
            }

            let selectionChanged = selection != highlighted
            if changed || selectionChanged || affectedSelection != highlightedSelection {
                // SceneKit returns an element and primitive index. Keep their
                // mapping to mesh faces even when a selected face changes color.
                let groups = Dictionary(grouping: mesh.faces.indices) { index -> Int in
                    let id = mesh.faces[index].id
                    if selection.contains(id) { return 1 }
                    return affectedSelection.contains(id) ? 2 : 0
                }
                let colors: [NSColor] = [.systemTeal, .systemOrange, .systemIndigo]
                var elements: [SCNGeometryElement] = []
                var materials: [SCNMaterial] = []
                faceGroups = []
                for group in colors.indices {
                    guard let faces = groups[group] else { continue }
                    let indices = faces.flatMap { i in [UInt32(i * 3), UInt32(i * 3 + 1), UInt32(i * 3 + 2)] }
                    elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
                    let material = SCNMaterial()
                    material.diffuse.contents = colors[group]
                    material.isDoubleSided = true
                    materials.append(material)
                    faceGroups.append(faces)
                }
                let geometry = SCNGeometry(sources: [vertexSource!, normalSource!], elements: elements)
                geometry.materials = materials
                surface.geometry = geometry
                highlighted = selection
                highlightedSelection = affectedSelection
            }

            if changed || selectionChanged || inspectingIssue != showingIssueOutline {
                showingIssueOutline = inspectingIssue
                faceOutline.geometry = nil
                if inspectingIssue && !selection.isEmpty {
                    // Filled triangles can be occluded or collapse to a line. Draw their
                    // edges over the surface; the corner marker also locates a point collapse.
                    let indices = mesh.faces.indices.filter { selection.contains(mesh.faces[$0].id) }.flatMap { index in
                        let a = UInt32(index * 3), b = a + 1, c = a + 2
                        return [a, b, b, c, c, a]
                    }
                    let lines = SCNGeometryElement(indices: indices, primitiveType: .line)
                    let geometry = SCNGeometry(sources: [vertexSource!], elements: [lines])
                    let ink = SCNMaterial()
                    ink.lightingModel = .constant
                    ink.diffuse.contents = NSColor.systemOrange
                    ink.readsFromDepthBuffer = false
                    ink.writesToDepthBuffer = false
                    geometry.materials = [ink]
                    faceOutline.geometry = geometry
                }
            }

            if changed || shownEdge != inspectionEdge {
                shownEdge = inspectionEdge
                edgeOverlay.geometry = nil
                if let edge = inspectionEdge {
                    let line = SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)
                    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: [positions[edge.x], positions[edge.y]])],
                                               elements: [line])
                    let material = SCNMaterial()
                    material.lightingModel = .constant
                    material.diffuse.contents = NSColor.systemPink
                    material.readsFromDepthBuffer = false
                    material.writesToDepthBuffer = false
                    geometry.materials = [material]
                    edgeOverlay.geometry = geometry
                }
            }
            marker.geometry?.firstMaterial?.readsFromDepthBuffer = !inspectingIssue
            marker.isHidden = true
            if let point, positions.indices.contains(point) {
                marker.position = positions[point]
                marker.isHidden = false
            }
        }

        func selection(element: Int, primitive: Int, near position: SCNVector3) -> (face: Int, point: Int)? {
            guard let mesh = displayed, faceGroups.indices.contains(element),
                  faceGroups[element].indices.contains(primitive) else { return nil }
            let face = mesh.faces[faceGroups[element][primitive]]
            let hit = SIMD3<Float>(position)
            let corners = [face.vertices.x, face.vertices.y, face.vertices.z]
            let nearest = corners.min {
                simd_distance_squared(hit, SIMD3<Float>(positions[$0])) <
                    simd_distance_squared(hit, SIMD3<Float>(positions[$1]))
            }!
            return (face.id, nearest)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PickingSceneView {
        let view = PickingSceneView()
        let scene = SCNScene()
        let coordinator = context.coordinator
        for node in [coordinator.surface, coordinator.wire, coordinator.faceOutline, coordinator.edgeOverlay, coordinator.marker] {
            scene.rootNode.addChildNode(node)
        }
        view.scene = scene
        view.backgroundColor = .textBackgroundColor
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true

        let eye = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 1000
        eye.camera = camera
        eye.simdPosition = PickingSceneView.homeEye
        eye.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(eye)
        view.pointOfView = eye
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3Zero
        if showsOrientation { view.addOrientationControls() }
        return view
    }

    func updateNSView(_ view: PickingSceneView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(mesh: mesh, selection: selectedFaces, point: selectedPoint, affectedSelection: affectedSelection,
                           inspectionEdge: inspectionEdge, inspectingIssue: inspectingIssue)
        weak var weakView = view
        func hit(at location: CGPoint) -> (face: Int, point: Int, anchor: SCNVector3)? {
            guard let hit = weakView?.hitTest(location, options: [.categoryBitMask: 1, .backFaceCulling: false]).first,
                  hit.node === coordinator.surface,
                  let target = coordinator.selection(element: hit.geometryIndex, primitive: hit.faceIndex,
                                                     near: hit.localCoordinates) else { return nil }
            return (target.face, target.point, hit.worldCoordinates)
        }
        view.onPick = { location in
            guard let target = hit(at: location) else { return }
            pick(target.face, target.point)
        }
        view.onBeginEdit = beginEdit.map { begin in
            { location in
                guard let target = hit(at: location), let edit = begin(target.face, target.point) else { return nil }
                let anchor = edit.point.map { coordinator.positions[$0] } ?? target.anchor
                return PickingSceneView.Drag(anchor: anchor, modelUnitsPerSceneUnit: coordinator.modelUnitsPerSceneUnit, edit: edit)
            }
        }
    }
}
