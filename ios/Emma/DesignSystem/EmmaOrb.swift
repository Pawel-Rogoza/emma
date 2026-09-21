import SwiftUI
import SceneKit

// MARK: - Fotorealistyczna Emma 2.5D

/// Adaptacyjny awatar Emmy. Zachowuje nazwę dawnego `EmmaOrb`, dzięki czemu
/// wszystkie miejsca aplikacji dostają tę samą postać bez duplikowania logiki.
/// Duże warianty renderują płytki relief SceneKit, małe używają lekkiego obrazu.
@MainActor
public struct EmmaOrb: View {
    public enum Size: Sendable {
        case inline, small, medium, card, compact, hero, stage

        var diameter: CGFloat {
            switch self {
            case .inline: return 18
            case .small: return 25
            case .medium: return 32
            case .card: return 37
            // „Dzisiaj” (etap 3 audytu): kompaktowa karta z portretem 48–64 pt.
            case .compact: return 52
            case .hero: return 100
            case .stage: return 148
            }
        }

        var usesRelief: Bool {
            switch self {
            case .hero, .stage: return true
            default: return false
            }
        }

        /// Skala obrazu zapasowego.
        ///
        /// Dla rozmiarów reliefowych musi być **taka sama jak w renderze 3D**.
        /// Inaczej przełączenie na obrazek (np. „Reduce Motion”, zejście aplikacji
        /// do tła) zmienia widoczną wielkość postaci — a wtedy ikonka, która ma
        /// tylko mrugać, sprawia wrażenie, że rośnie i maleje.
        /// Wartość zmierzona na zrzutach: obwiednia postaci w reliefie to
        /// `reliefCoverage` ramki, a obrazek w skali 1 zajmuje `1.033` tej obwiedni.
        var portraitScale: CGFloat {
            switch self {
            case .inline, .small: return 1.34
            case .medium, .card, .compact: return 1.18
            case .hero, .stage: return EmmaOrb.reliefMatchScale
            }
        }
    }

    /// Ile ramki zajmuje postać w renderze 3D (relief) — patrz `portraitScale`.
    nonisolated static let reliefCoverage: CGFloat = 0.968
    /// Skala, przy której obrazek zapasowy pokrywa się z reliefem.
    nonisolated static let reliefMatchScale: CGFloat = 1 / reliefCoverage

    private let size: Size
    private let isActive: Bool
    private let breathing: Bool
    private let state: TurnState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(size: Size = .card, isActive: Bool = false, breathing: Bool = false, state: TurnState? = nil) {
        self.size = size
        self.isActive = isActive
        self.breathing = breathing
        self.state = state
    }

    private var resolvedState: TurnState {
        state ?? (isActive ? .listening : .waiting)
    }

    public var body: some View {
        ZStack {
            if (breathing || isActive), size.usesRelief {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x9CBFDD, opacity: 0.16), .clear],
                        center: .center,
                        startRadius: size.diameter * 0.12,
                        endRadius: size.diameter * 0.58
                    ))
                    .scaleEffect(1.24)
            }

            // Render 3D trzymamy także wtedy, gdy aplikacja jest tylko nieaktywna
            // (alert systemowy, Centrum sterowania, połączenie przychodzące).
            // Wcześniej każde takie zdarzenie podmieniało postać na obrazek
            // i z powrotem — czyli ikonka „rosła i malała” zamiast mrugać.
            // Do tła schodzimy normalnie: wtedy i tak nikt na nią nie patrzy.
            if size.usesRelief, !reduceMotion, scenePhase != .background {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    EmmaReliefView(
                        time: context.date.timeIntervalSinceReferenceDate,
                        state: resolvedState
                    )
                }
            } else {
                Image("emma-avatar-refined")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(size.portraitScale)
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .contentShape(Circle())
        .accessibilityHidden(true)
        // Postać ma stały rozmiar i jest wskaźnikiem stanu: nie dziedziczy
        // animacji otaczającego ekranu ani nie przenika między obrazkiem
        // a reliefem. Przenikanie dwóch różnych renderów wyglądało jak
        // powiększanie i zmniejszanie zamiast mrugania.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

@MainActor
private enum EmmaReliefFactory {
    private static let grid = 96

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        let geometry = makeGeometry()
        geometry.materials = [material(named: "emma-avatar-refined")]

        let portrait = SCNNode(geometry: geometry)
        portrait.name = "emmaPortrait"
        portrait.morpher = makeEarMorpher(base: geometry)

        for (name, resource, order) in [
            ("blinkOverlay", "emma-blink-overlay", 1),
            ("speakOverlay", "emma-speak-overlay", 2)
        ] {
            let overlayGeometry = geometry.copy() as! SCNGeometry
            overlayGeometry.materials = [material(named: resource)]
            let overlay = SCNNode(geometry: overlayGeometry)
            overlay.name = name
            overlay.opacity = 0
            overlay.renderingOrder = order
            overlay.position = SCNVector3(0, 0, order == 1 ? 0.0002 : 0.0004)
            portrait.addChildNode(overlay)
        }

        scene.rootNode.addChildNode(portrait)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 35
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 10
        camera.position = SCNVector3(0, 0, 3.65)
        scene.rootNode.addChildNode(camera)
        return scene
    }

    private static func material(named name: String) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = name
        material.lightingModel = .constant
        material.diffuse.contents = UIImage(named: name)
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = true
        return material
    }

    private static func makeGeometry() -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var indices: [Int32] = []

        for row in 0...grid {
            for column in 0...grid {
                let x = Double(column) / Double(grid) * 2 - 1
                let y = 1 - Double(row) / Double(grid) * 2
                vertices.append(SCNVector3(Float(x), Float(y), Float(depth(x, y))))
                coordinates.append(CGPoint(x: Double(column) / Double(grid), y: Double(row) / Double(grid)))
            }
        }
        for row in 0..<grid {
            for column in 0..<grid {
                let a = Int32(row * (grid + 1) + column)
                let b = a + Int32(grid + 1)
                indices += [a, b, a + 1, b, b + 1, a + 1]
            }
        }

        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: coordinates)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private static func depth(_ x: Double, _ y: Double) -> Double {
        func g(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double) -> Double {
            exp(-pow((x - cx) / sx, 2) - pow((y - cy) / sy, 2))
        }
        return 0.24 * g(0, -0.10, 0.60, 0.60)
            + 0.18 * g(-0.06, -0.08, 0.19, 0.19)
            + 0.07 * g(-0.42, 0.55, 0.22, 0.45)
            + 0.07 * g(0.42, 0.50, 0.23, 0.44)
            + 0.06 * g(0, -0.62, 0.48, 0.42)
    }

    private static func makeEarMorpher(base geometry: SCNGeometry) -> SCNMorpher {
        let source = geometry.sources(for: .vertex)[0]
        let bytes = source.data as NSData
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(source.vectorCount)
        for index in 0..<source.vectorCount {
            let pointer = bytes.bytes
                .advanced(by: source.dataOffset + index * source.dataStride)
                .assumingMemoryBound(to: Float.self)
            vertices.append(SCNVector3(pointer[0], pointer[1], pointer[2]))
        }

        let morpher = SCNMorpher()
        morpher.calculationMode = .additive
        morpher.targets = [-1.0, 1.0].map { side in
            let target = vertices.map { vertex -> SCNVector3 in
                let x = Double(vertex.x), y = Double(vertex.y)
                let w = exp(-pow((x - side * 0.46) / 0.27, 2) - pow((y - 0.66) / 0.36, 2))
                    * min(1, max(0, (y - 0.28) / 0.20))
                return SCNVector3(
                    vertex.x + Float(side * (y - 0.30) * 0.072 * w),
                    vertex.y + Float(-abs(x - side * 0.28) * 0.050 * w),
                    vertex.z + Float(0.026 * w)
                )
            }
            return SCNGeometry(
                sources: [SCNGeometrySource(vertices: target)] + geometry.sources(for: .texcoord),
                elements: geometry.elements
            )
        }
        return morpher
    }

    static func update(_ view: SCNView, time: Double, state: TurnState) {
        guard let portrait = view.scene?.rootNode.childNode(withName: "emmaPortrait", recursively: false) else { return }
        let pose = EmmaPortraitMotion.pose(time: time, state: state)
        // Zerowa animacja niejawna jest tu istotna: gdy SwiftUI wykonuje tę
        // aktualizację w swoim bloku animacji, SceneKit interpolowałby transform
        // węzła, a interpolacja macierzy obrotu potrafi przejść przez stan
        // nieortogonalny — czyli postać na chwilę się rozciąga. Stąd „czasami
        // się buguje”: zamiast mrugania widać było rośnięcie i zmniejszanie.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        defer { SCNTransaction.commit() }
        portrait.eulerAngles = pose.angles
        // Obwiednia postaci jest stała. Oddychanie niosą wyłącznie ruch głowy,
        // uszy i światło — nigdy skala (patrz DESIGN_CONTRACT, „Animacja").
        portrait.scale = SCNVector3(1, 1, 1)
        portrait.morpher?.setWeight(CGFloat(pose.leftEar), forTargetAt: 0)
        portrait.morpher?.setWeight(CGFloat(pose.rightEar), forTargetAt: 1)
        portrait.childNode(withName: "blinkOverlay", recursively: false)?.opacity = CGFloat(pose.blink)
        portrait.childNode(withName: "speakOverlay", recursively: false)?.opacity = CGFloat(pose.speak)
    }

    static func configure(_ view: SCNView) {
        view.scene = makeScene()
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isPlaying = true
    }
}

private enum EmmaPortraitMotion {
    struct Pose {
        let angles: SCNVector3
        let leftEar: Double
        let rightEar: Double
        let blink: Double
        let speak: Double
    }

    static func pose(time: Double, state: TurnState) -> Pose {
        func pulse(_ phase: Double, _ start: Double, _ duration: Double) -> Double {
            let value = (phase - start) / duration
            guard value >= 0, value < 1 else { return 0 }
            return pow(sin(value * .pi), 2)
        }

        let cycle = time.truncatingRemainder(dividingBy: 7.8)
        let blink = max(pulse(cycle, 2.60, 0.21), pulse(cycle, 6.10, 0.19), pulse(cycle, 6.44, 0.17))
        let twitch = pulse(time.truncatingRemainder(dividingBy: 11.2), 4.5, 0.48)
        let listening = state == .listening
        let thinking = state == .thinking
        let speaking = state == .speaking
        let interrupted = state == .interrupted
        let speech = speaking
            ? min(0.92, max(0.12, 0.36 + 0.25 * sin(time * 11) + 0.18 * sin(time * 17.3)))
            : 0
        let leftEar = (listening ? 0.52 : interrupted ? 0.04 : 0.10) + twitch * 0.42
        let rightEar = (listening ? 0.40 : interrupted ? 0.03 : 0.08)
            + pulse((time + 1.7).truncatingRemainder(dividingBy: 13), 5, 0.5) * 0.36
        let x = sin(time * 0.73) * 0.010 + (listening ? -0.028 : 0) + (speaking ? sin(time * 3.1) * 0.006 : 0)
        let y = sin(time * 0.43) * 0.022 + (thinking ? 0.032 : 0) + (interrupted ? -0.020 : 0)
        let z = sin(time * 0.58) * 0.012 + (listening ? -0.052 : thinking ? 0.026 : interrupted ? 0.018 : 0)
        return Pose(
            angles: SCNVector3(Float(x), Float(y), Float(z)),
            leftEar: leftEar,
            rightEar: rightEar,
            blink: blink,
            speak: speech
        )
    }
}

private struct EmmaReliefView: UIViewRepresentable {
    let time: Double
    let state: TurnState

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        EmmaReliefFactory.configure(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        EmmaReliefFactory.update(view, time: time, state: state)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false
        view.scene = nil
    }
}

#Preview("Emma — rozmiary i stany") {
    VStack(spacing: 22) {
        HStack(spacing: 16) {
            EmmaOrb(size: .inline)
            EmmaOrb(size: .small)
            EmmaOrb(size: .medium)
            EmmaOrb(size: .card)
        }
        HStack(spacing: 20) {
            EmmaOrb(size: .hero, breathing: true, state: .waiting)
            EmmaOrb(size: .hero, isActive: true, state: .speaking)
        }
        EmmaOrb(size: .stage, breathing: true, state: .listening)
    }
    .padding(30)
    .background(EmmaTheme.bg)
}
