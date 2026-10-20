import SwiftUI
import SceneKit
import CoreMotion

/// 水槽に入れた1つ分。預かり中のもの1件 = 立方体1つ。
struct TankCube: Equatable {
    let id: UUID
    let accent: Bool
}

/// 預かり中を水槽で見せる。数字は出さない。
struct TankView: View {
    let cubes: [TankCube]
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TankRepresentable(cubes: cubes, active: visible && scenePhase == .active)
            .frame(height: 200)
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .accessibilityElement()
            .accessibilityLabel("預かり中 \(cubes.count)")
    }
}

private struct TankRepresentable: UIViewRepresentable {
    let cubes: [TankCube]
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.update(cubes: cubes)
        context.coordinator.setActive(active)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.refreshColors()
        context.coordinator.update(cubes: cubes)
        context.coordinator.setActive(active)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        private struct Body {
            var node: SCNNode
            var pos: SIMD3<Float>
            var vel: SIMD3<Float> = .zero
            var phase: SIMD3<Float>
            var accent: Bool
            /// nil: 水の中。値あり: 抜けていく途中の経過秒。
            var leaving: Float?
        }

        // 水槽（半分の大きさ）と立方体の大きさ（世界の単位）
        private static let half = SIMD3<Float>(1.75, 0.95, 0.6)
        private static let size: CGFloat = 0.26
        private static let radius: Float = 0.15

        private weak var view: SCNView?
        private let scene = SCNScene()
        private let tank = SCNNode()
        private let cubesNode = SCNNode()
        private let wire = SCNMaterial()
        private let tankMaterial = SCNMaterial()
        private let accentMaterial = SCNMaterial()
        private lazy var accentBox: SCNGeometry = {
            let b = SCNBox(width: Self.size, height: Self.size, length: Self.size, chamferRadius: 0)
            b.materials = [accentMaterial]
            return b
        }()
        private lazy var edgeGeometry: SCNGeometry = Self.edges(half: Float(Self.size) / 2, material: wire)

        private var bodies: [UUID: Body] = [:]
        private var displayLink: CADisplayLink?
        private let motion = CMMotionManager()
        private var lastTick = CACurrentMediaTime()
        private var time: Float = 0
        private var gravity = SIMD3<Float>(0, -1, 0)
        private var isActive = false

        func attach(to view: SCNView) {
            self.view = view
            view.scene = scene
            view.backgroundColor = .clear
            view.isOpaque = false
            view.antialiasingMode = .multisampling4X
            view.allowsCameraControl = false
            view.isUserInteractionEnabled = false
            view.preferredFramesPerSecond = 30
            scene.background.contents = UIColor.clear

            for m in [wire, tankMaterial, accentMaterial] {
                m.lightingModel = .constant
                m.isDoubleSided = true
            }

            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 1.15
            camera.zNear = 0.1
            camera.zFar = 30
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 8)
            scene.rootNode.addChildNode(cameraNode)

            // 少しだけ回して、奥行きが見えるようにする
            tank.eulerAngles = SCNVector3(-0.2, 0.28, 0)
            tank.addChildNode(SCNNode(geometry: Self.edges(half: 1, material: tankMaterial, scale: Self.half)))
            tank.addChildNode(cubesNode)
            scene.rootNode.addChildNode(tank)

            refreshColors()
            view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: SCNView, _: UITraitCollection) in
                self?.refreshColors()
            }
        }

        func refreshColors() {
            let traits = view?.traitCollection ?? UITraitCollection.current
            let ink = Theme.inkUIColor.resolvedColor(with: traits)
            wire.diffuse.contents = ink
            tankMaterial.diffuse.contents = ink.withAlphaComponent(0.35)
            accentMaterial.diffuse.contents = Theme.accentUIColor
        }

        // MARK: Diff

        func update(cubes: [TankCube]) {
            let ids = Set(cubes.map(\.id))
            for cube in cubes {
                if let existing = bodies[cube.id] {
                    if existing.accent != cube.accent || existing.leaving != nil {
                        var b = existing
                        b.accent = cube.accent
                        b.leaving = nil
                        b.node.opacity = 1
                        Self.look(b.node, accent: cube.accent, box: accentBox, edges: edgeGeometry)
                        bodies[cube.id] = b
                    }
                } else {
                    let node = SCNNode()
                    Self.look(node, accent: cube.accent, box: accentBox, edges: edgeGeometry)
                    let h = Self.half
                    let start = SIMD3<Float>(Float.random(in: -h.x * 0.8...h.x * 0.8), h.y + 0.4,
                                             Float.random(in: -h.z * 0.6...h.z * 0.6))
                    node.simdPosition = start
                    node.eulerAngles = SCNVector3(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1))
                    cubesNode.addChildNode(node)
                    bodies[cube.id] = Body(node: node, pos: start,
                                           phase: SIMD3(Float.random(in: 0...6.28), Float.random(in: 0...6.28), Float.random(in: 0...6.28)),
                                           accent: cube.accent, leaving: nil)
                }
            }
            for (id, var b) in bodies where !ids.contains(id) && b.leaving == nil {
                b.leaving = 0
                bodies[id] = b
            }
        }

        private static func look(_ node: SCNNode, accent: Bool, box: SCNGeometry, edges: SCNGeometry) {
            node.childNodes.forEach { $0.removeFromParentNode() }
            if accent {
                node.geometry = box
            } else {
                node.geometry = nil
                node.addChildNode(SCNNode(geometry: edges))
            }
        }

        // MARK: Run / stop

        func setActive(_ on: Bool) {
            guard on != isActive else { return }
            isActive = on
            if on {
                lastTick = CACurrentMediaTime()
                if motion.isDeviceMotionAvailable {
                    motion.deviceMotionUpdateInterval = 1.0 / 30.0
                    motion.startDeviceMotionUpdates()
                }
                let link = CADisplayLink(target: LinkTarget { [weak self] in self?.tick() }, selector: #selector(LinkTarget.fire))
                link.preferredFramesPerSecond = 30
                link.add(to: .main, forMode: .common)
                displayLink = link
                view?.isPlaying = true
            } else {
                stop()
            }
        }

        func teardown() {
            isActive = false
            stop()
        }

        private func stop() {
            displayLink?.invalidate()
            displayLink = nil
            if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
            view?.isPlaying = false
            view?.pause(nil)
        }

        // MARK: Simulation

        private func tick() {
            let now = CACurrentMediaTime()
            let dt = Float(min(now - lastTick, 0.05))
            lastTick = now
            guard dt > 0 else { return }
            time += dt

            // 重力：端末の向きに合わせてゆっくり追う
            var target = SIMD3<Float>(0, -1, 0)
            if let g = motion.deviceMotion?.gravity {
                target = SIMD3(Float(g.x), Float(g.y), Float(g.z) * 0.5)
            }
            gravity += (target - gravity) * min(1, dt * 4)

            let h = Self.half - SIMD3(repeating: Self.radius)
            let damping = expf(-1.6 * dt)
            let ids = Array(bodies.keys)

            for id in ids {
                guard var b = bodies[id] else { continue }
                if let t = b.leaving {
                    // 上へ浮かんで、薄くなって消える
                    let t2 = t + dt
                    b.vel.y = 0.9
                    b.vel.x *= damping
                    b.pos += b.vel * dt
                    b.node.opacity = CGFloat(max(0, 1 - t2 / 0.9))
                    b.node.simdPosition = b.pos
                    if t2 >= 0.9 {
                        b.node.removeFromParentNode()
                        bodies[id] = nil
                    } else {
                        b.leaving = t2
                        bodies[id] = b
                    }
                    continue
                }
                // 弱い重力 + ゆるいゆらぎ
                var acc = gravity * 0.35
                acc.x += sinf(time * 0.5 + b.phase.x) * 0.12
                acc.y += sinf(time * 0.43 + b.phase.y) * 0.12
                acc.z += sinf(time * 0.37 + b.phase.z) * 0.08
                b.vel += acc * dt
                b.vel *= damping
                b.pos += b.vel * dt
                bodies[id] = b
            }

            // 球とみなした当たり（やわらかく押し返す）
            let live = ids.filter { bodies[$0]?.leaving == nil && bodies[$0] != nil }
            let minDist = Self.radius * 2
            for i in 0..<live.count {
                for j in (i + 1)..<live.count {
                    guard var a = bodies[live[i]], var c = bodies[live[j]] else { continue }
                    let d = c.pos - a.pos
                    let dist = simd_length(d)
                    guard dist < minDist, dist > 0.0001 else { continue }
                    let n = d / dist
                    let push = (minDist - dist) * 0.5
                    a.pos -= n * push
                    c.pos += n * push
                    let rel = simd_dot(c.vel - a.vel, n)
                    if rel < 0 {
                        a.vel += n * rel * 0.5 * 1.4
                        c.vel -= n * rel * 0.5 * 1.4
                    }
                    bodies[live[i]] = a
                    bodies[live[j]] = c
                }
            }

            // 壁。落ちてくる途中のものは天井を無視して入ってくる。
            for id in live {
                guard var b = bodies[id] else { continue }
                for axis in 0..<3 {
                    if axis == 1 && b.pos.y > h.y { continue }
                    if b.pos[axis] < -h[axis] {
                        b.pos[axis] = -h[axis]
                        if b.vel[axis] < 0 { b.vel[axis] *= -0.35 }
                    } else if b.pos[axis] > h[axis] {
                        b.pos[axis] = h[axis]
                        if b.vel[axis] > 0 { b.vel[axis] *= -0.35 }
                    }
                }
                if b.pos.y > h.y { b.vel.y -= 1.2 * dt } // 上から入ってくる
                b.node.simdPosition = b.pos
                b.node.simdEulerAngles += SIMD3(b.vel.y, b.vel.x, b.vel.z) * dt * 1.5
                bodies[id] = b
            }
        }

        // MARK: Geometry

        /// 箱の辺だけ。
        static func edges(half: Float, material: SCNMaterial, scale: SIMD3<Float> = SIMD3(1, 1, 1)) -> SCNGeometry {
            var vertices: [SCNVector3] = []
            for x in [-1, 1] as [Float] { for y in [-1, 1] as [Float] { for z in [-1, 1] as [Float] {
                vertices.append(SCNVector3(x * half * scale.x, y * half * scale.y, z * half * scale.z))
            } } }
            let indices: [UInt16] = [
                0, 1, 2, 3, 4, 5, 6, 7,
                0, 2, 1, 3, 4, 6, 5, 7,
                0, 4, 1, 5, 2, 6, 3, 7,
            ]
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
            geometry.materials = [material]
            return geometry
        }
    }
}

/// CADisplayLink が強く参照しても、Coordinator が解放できるようにする橋渡し。
private final class LinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}
