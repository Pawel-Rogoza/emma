import SwiftUI
import SceneKit

public enum EmmaPortraitState: String, Sendable {
    case waiting, listening, thinking, speaking, interrupted
}

/// Photo-textured shallow relief. Not a full volumetric model.
/// Pass state from the existing voice coordinator; this view never owns audio.
@MainActor
public struct EmmaPortrait: View {
    private let size: CGFloat
    private let state: EmmaPortraitState
    private let audioLevel: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false

    public init(size: CGFloat = 100, state: EmmaPortraitState = .waiting, audioLevel: Double = 0) {
        self.size = size
        self.state = state
        self.audioLevel = audioLevel.isFinite ? min(1, max(0, audioLevel)) : 0
    }

    public var body: some View {
        Group {
            if size < 80 || reduceMotion || scenePhase != .active || !appeared {
                Image("emma-avatar", bundle: .module).resizable().scaledToFit()
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    NativeRelief(time: t, state: state, audioLevel: audioLevel)
                }
            }
        }
        .frame(width: size, height: size)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.77), .init(color: .clear, location: 0.99)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

@MainActor
private enum ReliefFactory {
    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        var vertices: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []
        let n = 160
        for row in 0...n {
            for col in 0...n {
                let x = Double(col) / Double(n) * 2 - 1
                let y = 1 - Double(row) / Double(n) * 2
                func g(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double) -> Double {
                    exp(-pow((x-cx)/sx, 2)-pow((y-cy)/sy, 2))
                }
                let z = 0.24*g(0,-0.1,0.60,0.60) + 0.18*g(-0.06,-0.08,0.19,0.19)
                    + 0.07*g(-0.42,0.55,0.22,0.45) + 0.07*g(0.42,0.50,0.23,0.44) + 0.09*g(0,-0.64,0.65,0.50)
                vertices.append(SCNVector3(Float(x), Float(y), Float(z)))
                uvs.append(CGPoint(x: Double(col)/Double(n), y: Double(row)/Double(n)))
            }
        }
        for row in 0..<n {
            for col in 0..<n {
                let a = Int32(row*(n+1)+col), b = a+Int32(n+1)
                indices += [a,b,a+1,b,b+1,a+1]
            }
        }
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(textureCoordinates: uvs)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Bundle.module.url(forResource: "emma-avatar", withExtension: "png")
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        let morpher = SCNMorpher()
        morpher.calculationMode = .additive
        morpher.targets = (0..<5).map { index in
            let targetVertices = vertices.map { v in
                let d = HeadMotion.delta(index,Double(v.x),Double(v.y))
                return SCNVector3(v.x+d.x,v.y+d.y,v.z+d.z)
            }
            return SCNGeometry(sources: [.init(vertices: targetVertices),.init(textureCoordinates: uvs)],elements: geometry.elements)
        }
        node.morpher = morpher
        node.name = "portrait"
        for (name, resource, order) in [("blinkOverlay", "emma-blink-overlay", 1), ("speakOverlay", "emma-speak-overlay", 2)] {
            let overlayGeometry = geometry.copy() as! SCNGeometry
            let overlayMaterial = SCNMaterial()
            overlayMaterial.lightingModel = .constant
            overlayMaterial.diffuse.contents = Bundle.module.url(forResource: resource, withExtension: "png")
            overlayMaterial.transparencyMode = .aOne
            overlayMaterial.writesToDepthBuffer = false
            overlayMaterial.readsFromDepthBuffer = false
            overlayGeometry.materials = [overlayMaterial]
            let overlay = SCNNode(geometry: overlayGeometry)
            overlay.name = name
            overlay.opacity = 0
            overlay.renderingOrder = order
            overlay.position = SCNVector3(0, 0, order == 1 ? 0.0002 : 0.0004)
            node.addChildNode(overlay)
        }
        scene.rootNode.addChildNode(node)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 35
        camera.position = SCNVector3(0,0,3.65)
        scene.rootNode.addChildNode(camera)
        return scene
    }
    static func update(_ view: SCNView, time: Double, state: EmmaPortraitState, audioLevel: Double) {
        guard let node = view.scene?.rootNode.childNode(withName: "portrait", recursively: false) else { return }
        let pose = HeadMotion.pose(time,state,audioLevel)
        node.eulerAngles = pose.angles
        node.scale = SCNVector3(pose.scale,pose.scale,pose.scale)
        for (index,weight) in pose.weights.enumerated() {
            node.morpher?.setWeight(index == 2 || index == 3 ? CGFloat(weight) : 0, forTargetAt: index)
        }
        node.childNode(withName: "blinkOverlay", recursively: false)?.opacity = CGFloat(max(pose.weights[0], pose.weights[1]))
        node.childNode(withName: "speakOverlay", recursively: false)?.opacity = CGFloat(pose.weights[4])
    }
    static func setup(_ view: SCNView) {
        view.scene = makeScene()
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.isPlaying = false
        view.backgroundColor = .clear
    }
}

#if os(iOS)
private struct NativeRelief: UIViewRepresentable {
    let time: Double
    let state: EmmaPortraitState
    let audioLevel: Double
    func makeUIView(context: Context) -> SCNView { let view = SCNView(); ReliefFactory.setup(view); return view }
    func updateUIView(_ view: SCNView, context: Context) { ReliefFactory.update(view, time: time, state: state, audioLevel: audioLevel) }
}
#else
private struct NativeRelief: NSViewRepresentable {
    let time: Double
    let state: EmmaPortraitState
    let audioLevel: Double
    func makeNSView(context: Context) -> SCNView { let view = SCNView(); ReliefFactory.setup(view); return view }
    func updateNSView(_ view: SCNView, context: Context) { ReliefFactory.update(view, time: time, state: state, audioLevel: audioLevel) }
}
#endif
