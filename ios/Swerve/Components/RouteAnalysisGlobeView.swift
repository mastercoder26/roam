import SceneKit
import SwiftUI
import UIKit

/// A small, self-contained SceneKit scene used while Swerve analyzes a route.
/// The car is a child of `orbitNode`, so rotating that one helper node moves it
/// around the Earth without hand-calculating a 2D path.
struct RouteAnalysisGlobeView: UIViewRepresentable {
    let reduceMotion: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scene = RouteAnalysisGlobeScene.make(reduceMotion: reduceMotion)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard context.coordinator.reduceMotion != reduceMotion else { return }
        context.coordinator.reduceMotion = reduceMotion
        view.scene = RouteAnalysisGlobeScene.make(reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reduceMotion: reduceMotion)
    }

    final class Coordinator {
        var reduceMotion: Bool

        init(reduceMotion: Bool) {
            self.reduceMotion = reduceMotion
        }
    }
}

private enum RouteAnalysisGlobeScene {
    static func make(reduceMotion: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.position = SCNVector3(0, 0.1, 6.5)
        scene.rootNode.addChildNode(camera)

        let earth = SCNNode(geometry: SCNSphere(radius: 1.18))
        earth.geometry?.firstMaterial = earthMaterial
        scene.rootNode.addChildNode(earth)
        addGrid(to: earth)

        let orbitNode = SCNNode()
        orbitNode.eulerAngles.x = -.pi / 10
        orbitNode.addChildNode(makeCar())
        scene.rootNode.addChildNode(orbitNode)

        if !reduceMotion {
            let orbit = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 5.5)
            orbitNode.runAction(.repeatForever(orbit))
            earth.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 22)))
        }

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1_100
        keyLight.eulerAngles = SCNVector3(-.pi / 3, -.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 500
        fillLight.light?.color = UIColor(red: 0.38, green: 0.59, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(fillLight)

        return scene
    }

    private static var earthMaterial: SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.08, green: 0.34, blue: 0.78, alpha: 1)
        material.specular.contents = UIColor(white: 1, alpha: 0.85)
        material.shininess = 0.55
        return material
    }

    private static func addGrid(to earth: SCNNode) {
        for rotation in [Float(0), .pi / 2] {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 1.185, pipeRadius: 0.006))
            ring.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.22)
            ring.eulerAngles.x = rotation
            earth.addChildNode(ring)
        }
    }

    private static func makeCar() -> SCNNode {
        let car = SCNNode()
        car.position = SCNVector3(0, 0, 1.52)
        car.eulerAngles.y = -.pi / 2

        let body = SCNBox(width: 0.46, height: 0.16, length: 0.24, chamferRadius: 0.06)
        body.firstMaterial?.diffuse.contents = UIColor.systemOrange
        let bodyNode = SCNNode(geometry: body)
        car.addChildNode(bodyNode)

        let cabin = SCNBox(width: 0.24, height: 0.13, length: 0.2, chamferRadius: 0.04)
        cabin.firstMaterial?.diffuse.contents = UIColor(white: 0.92, alpha: 1)
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(-0.02, 0.13, 0)
        car.addChildNode(cabinNode)

        for x in [-0.15, 0.15] as [Float] {
            for z in [-0.14, 0.14] as [Float] {
                let wheel = SCNNode(geometry: SCNCylinder(radius: 0.065, height: 0.045))
                wheel.geometry?.firstMaterial?.diffuse.contents = UIColor.black
                wheel.eulerAngles.x = .pi / 2
                wheel.position = SCNVector3(x, -0.1, z)
                car.addChildNode(wheel)
            }
        }

        return car
    }
}
