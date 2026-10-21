import SwiftUI
import RealityKit
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
    @State private var scene = TankScene()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.paletteID
        RealityView { content in
            scene.build(&content)
        } update: { _ in
            scene.setScheme(colorScheme, palette: palette)
            scene.update(cubes: cubes)
            scene.setActive(visible && scenePhase == .active)
        }
        .frame(height: 200)
        .allowsHitTesting(false)
        .onAppear { visible = true; scene.setActive(scenePhase == .active) }
        .onDisappear { visible = false; scene.setActive(false) }
        .onChange(of: scenePhase) { _, phase in scene.setActive(visible && phase == .active) }
        .accessibilityElement()
        .accessibilityLabel("預かり中 \(cubes.count)")
    }
}

/// 水槽の 3D シーン。立方体はやわらかい当たりと弱い重力で漂う。
@MainActor
final class TankScene {
    private struct Body {
        var node: Entity
        var pos: SIMD3<Float>
        var vel: SIMD3<Float> = .zero
        var angles: SIMD3<Float>
        var phase: SIMD3<Float>
        /// 水の中で落ち着く高さ（水槽の高さに対する割合、-1...1）
        var rest: Float
        /// ゆっくり回り続ける速さ（ラジアン／秒）
        var spin: SIMD3<Float>
        var accent: Bool
        /// nil: 水の中。値あり: 抜けていく途中の経過秒。
        var leaving: Float?
    }

    // 水槽（半分の大きさ）と立方体の大きさ（世界の単位）
    private static let half = SIMD3<Float>(1.75, 0.95, 0.6)
    private static let size: Float = 0.26
    private static let radius: Float = 0.15

    private let root = Entity()
    private let tank = Entity()
    private let cubesNode = Entity()
    private var tankOutline: ModelEntity?
    private lazy var wireMesh: MeshResource = VoxelMesh.wireBox(half: SIMD3(repeating: Self.size / 2), thickness: 0.012)
    private lazy var accentMesh: MeshResource = .generateBox(size: Self.size)
    private var inkMaterial = VoxelMesh.unlit(.black)
    private var accentMaterial = VoxelMesh.unlit(Theme.accentUIColor)

    private var bodies: [UUID: Body] = [:]
    private var pending: [TankCube]?
    private var subscription: EventSubscription?
    private let motion = CMMotionManager()
    private var time: Float = 0
    private var gravity = SIMD3<Float>(0, -1, 0)
    private var isActive = false
    private var built = false
    private var scheme: ColorScheme = .light
    private var paletteID = Theme.paletteID

    func build(_ content: inout RealityViewCameraContent) {
        guard !built else { return }
        content.camera = .virtual
        content.renderingEffects.antialiasing = .multisample4X

        var cam = OrthographicCameraComponent()
        cam.near = 0.1
        cam.far = 30
        cam.scale = 1.15  // SceneKit の orthographicScale と同じく、縦の半分の大きさ
        cam.scaleDirection = .vertical
        let camera = Entity()
        camera.components.set(cam)
        camera.position = SIMD3(0, 0, 8)
        root.addChild(camera)

        // 少しだけ回して、奥行きが見えるようにする
        tank.orientation = Self.rotation(SIMD3(-0.2, 0.28, 0))
        let outline = ModelEntity(mesh: VoxelMesh.wireBox(half: Self.half, thickness: 0.008), materials: [inkMaterial])
        tank.addChild(outline)
        tankOutline = outline
        tank.addChild(cubesNode)
        root.addChild(tank)
        content.add(root)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.tick(dt: dt) }
        }
        built = true
        refreshColors()
        if let cubes = pending { pending = nil; update(cubes: cubes) }
    }

    func setScheme(_ s: ColorScheme, palette: String) {
        guard s != scheme || palette != paletteID || !built else { return }
        scheme = s
        paletteID = palette
        if built { refreshColors() }
    }

    private func refreshColors() {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let ink = Theme.inkUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        inkMaterial = VoxelMesh.unlit(ink)
        var outline = VoxelMesh.unlit(ink)
        outline.blending = .transparent(opacity: 0.35)
        tankOutline?.model?.materials = [outline]
        accentMaterial = VoxelMesh.unlit(Theme.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
        for b in bodies.values { look(b.node, accent: b.accent) }
    }

    // MARK: Diff

    func update(cubes: [TankCube]) {
        guard built else { pending = cubes; return }
        let ids = Set(cubes.map(\.id))
        for cube in cubes {
            if let existing = bodies[cube.id] {
                if existing.accent != cube.accent || existing.leaving != nil {
                    var b = existing
                    b.accent = cube.accent
                    b.leaving = nil
                    b.node.components.set(OpacityComponent(opacity: 1))
                    look(b.node, accent: cube.accent)
                    bodies[cube.id] = b
                }
            } else {
                let node = Entity()
                look(node, accent: cube.accent)
                let h = Self.half
                let start = SIMD3<Float>(Float.random(in: -h.x * 0.8...h.x * 0.8), h.y + 0.4,
                                         Float.random(in: -h.z * 0.6...h.z * 0.6))
                let angles = SIMD3<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1))
                node.position = start
                node.orientation = Self.rotation(angles)
                cubesNode.addChild(node)
                bodies[cube.id] = Body(node: node, pos: start, angles: angles,
                                       phase: SIMD3(Float.random(in: 0...6.28), Float.random(in: 0...6.28), Float.random(in: 0...6.28)),
                                       rest: Float.random(in: -0.6...0.6),
                                       spin: SIMD3(Float.random(in: -0.3...0.3), Float.random(in: -0.3...0.3), Float.random(in: -0.2...0.2)),
                                       accent: cube.accent, leaving: nil)
            }
        }
        for (id, var b) in bodies where !ids.contains(id) && b.leaving == nil {
            b.leaving = 0
            bodies[id] = b
        }
    }

    private func look(_ node: Entity, accent: Bool) {
        node.children.removeAll()
        node.addChild(ModelEntity(mesh: accent ? accentMesh : wireMesh,
                                  materials: [accent ? accentMaterial : inkMaterial]))
    }

    // MARK: Run / stop

    func setActive(_ on: Bool) {
        guard on != isActive else { return }
        isActive = on
        if on {
            if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
                motion.deviceMotionUpdateInterval = 1.0 / 30.0
                motion.startDeviceMotionUpdates()
            }
        } else if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    /// SceneKit の eulerAngles と同じ順（Z、Y、X の順にかける）の回転。
    private static func rotation(_ e: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: e.x, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: e.y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: e.z, axis: SIMD3(0, 0, 1))
    }

    // MARK: Simulation

    private func tick(dt rawDT: Float) {
        guard isActive else { return }
        let dt = min(rawDT, 0.05)
        guard dt > 0 else { return }
        time += dt

        // 重力：端末の向きに合わせてゆっくり追う
        var target = SIMD3<Float>(0, -1, 0)
        if let g = motion.deviceMotion?.gravity {
            target = SIMD3(Float(g.x), Float(g.y), Float(g.z) * 0.5)
        }
        gravity += (target - gravity) * min(1, dt * 4)

        let h = Self.half - SIMD3(repeating: Self.radius)
        let damping = expf(-0.9 * dt)
        // 水槽はジャイロで動かす：傾けたぶんだけ（真下からのずれ）押す。真下向きの重さは浮力で打ち消す
        let tilt = SIMD3<Float>(gravity.x, gravity.y + 1, gravity.z) * 1.2
        let ids = Array(bodies.keys)

        for id in ids {
            guard var b = bodies[id] else { continue }
            if let t = b.leaving {
                // 上へ浮かんで、薄くなって消える
                let t2 = t + dt
                b.vel.y = 0.9
                b.vel.x *= damping
                b.pos += b.vel * dt
                b.node.components.set(OpacityComponent(opacity: max(0, 1 - t2 / 0.9)))
                b.node.position = b.pos
                if t2 >= 0.9 {
                    b.node.removeFromParent()
                    bodies[id] = nil
                } else {
                    b.leaving = t2
                    bodies[id] = b
                }
                continue
            }
            // 水に浮いている：動きの主役は傾き。それぞれの高さへはゆるく戻り、自分ではかすかに揺れるだけ
            var acc = tilt
            if b.pos.y <= h.y { acc.y += (b.rest * h.y - b.pos.y) * 0.35 }
            acc.x += sinf(time * 0.23 + b.phase.x) * 0.06
            acc.y += sinf(time * 0.31 + b.phase.y) * 0.05
            acc.z += sinf(time * 0.19 + b.phase.z) * 0.04
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
                    // 水の中なので、ぶつかってもやわらかく離れる
                    a.vel += n * rel * 0.5 * 1.1
                    c.vel -= n * rel * 0.5 * 1.1
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
                    if b.vel[axis] < 0 { b.vel[axis] *= -0.2 }
                } else if b.pos[axis] > h[axis] {
                    b.pos[axis] = h[axis]
                    if b.vel[axis] > 0 { b.vel[axis] *= -0.2 }
                }
            }
            if b.pos.y > h.y { b.vel.y -= 0.9 * dt } // 上から入ってきて、水面でふわっと沈む
            b.node.position = b.pos
            b.angles += (b.spin + SIMD3(b.vel.y, b.vel.x, b.vel.z) * 0.8) * dt
            b.node.orientation = Self.rotation(b.angles)
            bodies[id] = b
        }
    }
}
