import SceneKit
import SwiftUI

// Forward the full gesture to SceneKit for orbiting. Only a stationary click
// picks geometry, so finishing an orbit never toggles a triangle.
final class PickingSceneView: SCNView {
    var onPick: ((CGPoint) -> Void)?
    private var down: CGPoint?

    override func mouseDown(with event: NSEvent) {
        down = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let down, hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y) > 3 {
            self.down = nil
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if down != nil { onPick?(convert(event.locationInWindow, from: nil)) }
        down = nil
    }
}

struct ModelViewport: NSViewRepresentable {
    let mesh: EditableMesh
    let selectedFaces: Set<Int>
    let selectedPoint: Int?
    var affectedSelection: Set<Int> = []
    var inspectionEdge: SIMD2<Int>?
    var inspectingIssue = false
    let pick: (Int, Int) -> Void

    final class Coordinator {
        let surface = SCNNode()
        let wire = SCNNode()
        let edgeOverlay = SCNNode()
        var shownEdge: SIMD2<Int>?
        let marker = SCNNode(geometry: SCNSphere(radius: 0.028))
        var displayed: EditableMesh?
        var highlighted: Set<Int> = []
        var highlightedSelection: Set<Int> = []
        var faceGroups: [[Int]] = []
        var positions: [SCNVector3] = []
        var vertexSource: SCNGeometrySource?
        var normalSource: SCNGeometrySource?

        init() {
            wire.categoryBitMask = 2
            edgeOverlay.categoryBitMask = 2
            edgeOverlay.renderingOrder = 2
            marker.categoryBitMask = 2
            wire.renderingOrder = 1
            marker.renderingOrder = 3
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
                positions = mesh.vertices.map {
                    let p = ($0 - center) / (radius > 0 ? radius : 1)
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

            if changed || selection != highlighted || affectedSelection != highlightedSelection {
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
        for node in [coordinator.surface, coordinator.wire, coordinator.edgeOverlay, coordinator.marker] {
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
        eye.position = SCNVector3(2.3, 1.9, 3.2)
        eye.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(eye)
        view.pointOfView = eye
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3Zero
        return view
    }

    func updateNSView(_ view: PickingSceneView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(mesh: mesh, selection: selectedFaces, point: selectedPoint, affectedSelection: affectedSelection,
                           inspectionEdge: inspectionEdge, inspectingIssue: inspectingIssue)
        view.onPick = { [weak view] location in
            guard let hit = view?.hitTest(location, options: [.categoryBitMask: 1, .backFaceCulling: false]).first,
                  hit.node === coordinator.surface,
                  let target = coordinator.selection(element: hit.geometryIndex, primitive: hit.faceIndex,
                                                     near: hit.localCoordinates) else { return }
            pick(target.face, target.point)
        }
    }
}
