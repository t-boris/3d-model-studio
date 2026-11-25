import SceneKit
import SwiftUI

struct ModelViewport: NSViewRepresentable {
    let mesh: EditableMesh

    final class Coordinator {
        let surface = SCNNode()
        var displayed: EditableMesh?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        scene.rootNode.addChildNode(context.coordinator.surface)
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

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.displayed != mesh else { return }
        coordinator.surface.geometry = geometry()
        coordinator.displayed = mesh
    }

    private func geometry() -> SCNGeometry {
        // Normalize the display copy before converting to GPU floats. Physical
        // coordinates, face order and vertex sharing stay in the editable mesh.
        let (low, high) = mesh.surfaceBounds
        let center = high * 0.5 + low * 0.5
        let radius = (high * 0.5 - low * 0.5).max()
        let scale = radius > 0 ? radius : 1
        func displayPoint(_ index: Int) -> SIMD3<Float> {
            let p = (mesh.vertices[index] - center) / scale
            return SIMD3(Float(p.x), Float(p.z), Float(-p.y))
        }
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        positions.reserveCapacity(mesh.faces.count * 3)
        normals.reserveCapacity(mesh.faces.count * 3)
        for face in mesh.faces {
            let a = displayPoint(face.vertices.x)
            let b = displayPoint(face.vertices.y)
            let c = displayPoint(face.vertices.z)
            let cross = simd_cross(b - a, c - a)
            let normal = simd_length_squared(cross) > 0 ? simd_normalize(cross) : SIMD3(0, 1, 0)
            positions.append(contentsOf: [SCNVector3(a), SCNVector3(b), SCNVector3(c)])
            normals.append(contentsOf: repeatElement(SCNVector3(normal), count: 3))
        }
        let element = SCNGeometryElement(data: nil, primitiveType: .triangles, primitiveCount: mesh.faces.count,
                                         bytesPerIndex: 0)
        let geometry = SCNGeometry(sources: [.init(vertices: positions), .init(normals: normals)], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemTeal
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
}
