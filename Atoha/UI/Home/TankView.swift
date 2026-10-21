import SwiftUI
import RealityKit
import CoreMotion

/// 水槽に入れた1匹分。あとでにあるもの1件 = 金魚1匹。
struct TankCube: Equatable {
    let id: UUID
    let tint: GoldfishTint
}

/// あとでを、金魚すくいの水槽で見せる。金魚は傾けると寄る（ジャイロ）。
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
        .background(TankWater())
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
        .allowsHitTesting(false)
        .onAppear { visible = true; scene.setActive(scenePhase == .active) }
        .onDisappear { visible = false; scene.setActive(false) }
        .onChange(of: scenePhase) { _, phase in scene.setActive(visible && phase == .active) }
        .accessibilityElement()
        .accessibilityLabel("水槽に \(cubes.count) 匹")
    }
}

/// 水槽の水。平らな水色に、水面の帯と白い波紋。
private struct TankWater: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.water))
            // 水面の帯（少しだけ濃い）
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 10)),
                         with: .color(Color(Theme.waterUIColor).opacity(0.6).mix(with: Theme.ink, by: 0.08)))
            var ripples = Path()
            for (fx, fy, w) in [(0.1, 0.25, 26.0), (0.62, 0.18, 30.0), (0.36, 0.78, 24.0), (0.82, 0.66, 20.0)] {
                let x = size.width * fx, y = size.height * fy
                ripples.move(to: CGPoint(x: x, y: y))
                ripples.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - 6))
            }
            context.stroke(ripples, with: .color(Color(Theme.rippleUIColor).opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// 水槽の 3D シーン。ドットの金魚が浮いて漂い、傾けると寄る。すくう演出もここで動かす。
@MainActor
final class TankScene {
    /// 画面に出ている水槽（すくう演出を外から呼ぶため）
    static weak var current: TankScene?

    private struct Body {
        var node: ModelEntity
        var pos: SIMD3<Float>
        var vel: SIMD3<Float> = .zero
        var phase: SIMD3<Float>
        /// 水の中で落ち着く高さ（水槽の高さに対する割合、-1...1）
        var rest: Float
        var tint: GoldfishTint
        /// 今の向き（0 = 左向き、π = 右向き）
        var facing: Float
        /// nil: 水の中。値あり: 抜けていく途中の経過秒。
        var leaving: Float?
    }

    /// すくう途中のもの
    private struct Scoop {
        let id: UUID
        let success: Bool
        let poi: Entity
        let paper: ModelEntity
        let start: SIMD3<Float>
        var t: Float = 0
        var splashed = false
        var torn = false
    }

    private struct Droplet {
        let node: ModelEntity
        var vel: SIMD3<Float>
        var life: Float = 0
    }

    // 水槽（半分の大きさ）と金魚の大きさ（世界の単位）
    private static let half = SIMD3<Float>(1.75, 0.95, 0.4)
    private static let cell: Float = 0.05
    private static let poiCell: Float = 0.045
    private static let radius: Float = 0.2

    private let root = Entity()
    private let fishNode = Entity()
    private lazy var fishMesh: MeshResource = Self.makeFishMesh()
    private lazy var ringMesh: MeshResource = Self.makePoiMesh(Self.poiCells.ring)
    private lazy var paperMesh: MeshResource = Self.makePoiMesh(Self.poiCells.paper)
    private lazy var tornMesh: MeshResource = Self.makePoiMesh(Self.poiCells.torn)
    private lazy var handleMesh: MeshResource = Self.makePoiMesh(Self.poiCells.handle)
    private lazy var dropletMesh: MeshResource = .generateBox(size: 0.035)
    private var materials: [GoldfishTint: UnlitMaterial] = [:]
    private var inkMaterial = VoxelMesh.unlit(.black)
    private var accentMaterial = VoxelMesh.unlit(.red)
    private var paperMaterial = VoxelMesh.unlit(.white)
    private var dropMaterial = VoxelMesh.unlit(.white)

    private var bodies: [UUID: Body] = [:]
    private var scoops: [UUID: Scoop] = [:]
    private var droplets: [Droplet] = []
    /// すくって今に入れたもの。一覧から消えるまでのあいだ、水槽に戻さない
    private var scooped: Set<UUID> = []
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
        cam.scale = 1.15  // 縦の半分の大きさ
        cam.scaleDirection = .vertical
        let camera = Entity()
        camera.components.set(cam)
        camera.position = SIMD3(0, 0, 8)
        root.addChild(camera)

        // 正面から見る（金魚がドット絵として読めるように）
        root.addChild(fishNode)
        content.add(root)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.tick(dt: dt) }
        }
        built = true
        Self.current = self
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
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        for tint in [GoldfishTint.red, .black, .orange, .faint] {
            materials[tint] = VoxelMesh.unlit(tint.uiColor.resolvedColor(with: traits))
        }
        inkMaterial = VoxelMesh.unlit(Theme.inkUIColor.resolvedColor(with: traits))
        accentMaterial = VoxelMesh.unlit(Theme.accentUIColor.resolvedColor(with: traits))
        var paper = VoxelMesh.unlit(.white)
        paper.blending = .transparent(opacity: 0.75)
        paperMaterial = paper
        dropMaterial = VoxelMesh.unlit(Theme.rippleUIColor.resolvedColor(with: traits))
        for b in bodies.values { b.node.model?.materials = [material(b.tint)] }
    }

    private func material(_ tint: GoldfishTint) -> UnlitMaterial {
        materials[tint] ?? inkMaterial
    }

    // MARK: Diff

    func update(cubes: [TankCube]) {
        guard built else { pending = cubes; return }
        let ids = Set(cubes.map(\.id))
        scooped.formIntersection(ids)
        for cube in cubes where !scooped.contains(cube.id) {
            if var b = bodies[cube.id] {
                if b.tint != cube.tint || b.leaving != nil {
                    b.tint = cube.tint
                    b.leaving = nil
                    b.node.components.set(OpacityComponent(opacity: 1))
                    b.node.model?.materials = [material(cube.tint)]
                    bodies[cube.id] = b
                }
            } else {
                let node = ModelEntity(mesh: fishMesh, materials: [material(cube.tint)])
                let h = Self.half
                let start = SIMD3<Float>(Float.random(in: -h.x * 0.8...h.x * 0.8), h.y + 0.4,
                                         Float.random(in: -h.z...h.z))
                let facing: Float = Bool.random() ? 0 : .pi
                node.position = start
                node.orientation = simd_quatf(angle: facing, axis: SIMD3(0, 1, 0))
                fishNode.addChild(node)
                bodies[cube.id] = Body(node: node, pos: start,
                                       phase: SIMD3(Float.random(in: 0...6.28), Float.random(in: 0...6.28), Float.random(in: 0...6.28)),
                                       rest: Float.random(in: -0.6...0.6), tint: cube.tint, facing: facing, leaving: nil)
            }
        }
        for (id, var b) in bodies where !ids.contains(id) && b.leaving == nil && scoops[id] == nil {
            b.leaving = 0
            bodies[id] = b
        }
    }

    // MARK: すくう

    /// 今に入れるときの演出。success が false なら、ポイが破れて金魚は水に戻る（今がいっぱい）。
    func scoop(_ id: UUID, success: Bool) {
        guard built, let b = bodies[id], b.leaving == nil, scoops[id] == nil else { return }
        let poi = Entity()
        let handle = ModelEntity(mesh: handleMesh, materials: [accentMaterial])
        let paper = ModelEntity(mesh: paperMesh, materials: [paperMaterial])
        let ring = ModelEntity(mesh: ringMesh, materials: [inkMaterial])
        for e in [handle, paper, ring] { poi.addChild(e) }
        let start = SIMD3<Float>(b.pos.x, b.pos.y - 0.75, b.pos.z - 0.15)
        poi.position = start
        poi.components.set(OpacityComponent(opacity: 0))
        fishNode.addChild(poi)
        scoops[id] = Scoop(id: id, success: success, poi: poi, paper: paper, start: start)
        if success { scooped.insert(id) }
    }

    private func tickScoops(dt: Float) {
        let h = Self.half
        for (id, var s) in scoops {
            s.t += dt
            guard var b = bodies[id] else { s.poi.removeFromParent(); scoops[id] = nil; continue }
            let under = SIMD3<Float>(b.pos.x, b.pos.y - 0.1, b.pos.z - 0.15)
            if s.t < 0.25 {
                // ポイが下から金魚の下へ
                let k = Self.ease(s.t / 0.25)
                s.poi.position = s.start + (under - s.start) * k
                s.poi.components.set(OpacityComponent(opacity: min(1, s.t / 0.12)))
            } else if s.success {
                if s.t < 0.55 {
                    // 金魚ごと水面の上へ
                    let k = Self.ease((s.t - 0.25) / 0.3)
                    let surface = h.y + 0.3
                    b.pos.y += (surface - b.pos.y) * min(1, k * 0.6 + dt * 6)
                    s.poi.position = SIMD3(b.pos.x, b.pos.y - 0.1, b.pos.z - 0.15)
                    if !s.splashed && b.pos.y > h.y - 0.05 {
                        s.splashed = true
                        splash(at: SIMD3(b.pos.x, h.y, b.pos.z), count: 7)
                    }
                } else {
                    // 弧を描いて右上（お椀）へ、小さく薄くなって消える
                    let k = min(1, (s.t - 0.55) / 0.4)
                    let target = SIMD3<Float>(h.x + 0.3, h.y + 1.1, b.pos.z)
                    b.pos += (target - b.pos) * min(1, dt * 7)
                    b.node.scale = SIMD3(repeating: 1 - 0.5 * k)
                    b.node.components.set(OpacityComponent(opacity: 1 - k))
                    s.poi.components.set(OpacityComponent(opacity: max(0, 1 - k * 2)))
                    if k >= 1 {
                        b.node.removeFromParent()
                        s.poi.removeFromParent()
                        bodies[id] = nil
                        scoops[id] = nil
                        continue
                    }
                }
                b.node.position = b.pos
                bodies[id] = b
            } else {
                if s.t < 0.4 {
                    // 少し持ち上げたところで
                    b.pos.y += 0.5 * dt
                    s.poi.position = SIMD3(b.pos.x, b.pos.y - 0.1, b.pos.z - 0.15)
                    b.node.position = b.pos
                    bodies[id] = b
                } else {
                    if !s.torn {
                        // 紙のドットが抜けて穴があく。抜けたドットは水へ落ちる
                        s.torn = true
                        s.paper.model?.mesh = tornMesh
                        for _ in 0..<5 {
                            let jitter = SIMD3<Float>(Float.random(in: -0.12...0.12), Float.random(in: -0.08...0.08), 0)
                            addDroplet(at: s.poi.position + jitter + SIMD3(0, 0, 0.05),
                                       vel: SIMD3(Float.random(in: -0.2...0.2), Float.random(in: -0.6 ... -0.2), 0),
                                       material: paperMaterial)
                        }
                        b.vel = SIMD3(0, -0.6, 0)
                        bodies[id] = b
                    }
                    // ポイは沈みながら消える。金魚はもう水の動きに戻っている
                    let k = min(1, (s.t - 0.4) / 0.5)
                    s.poi.position.y -= 0.6 * dt
                    s.poi.components.set(OpacityComponent(opacity: 1 - k))
                    if k >= 1 {
                        s.poi.removeFromParent()
                        scoops[id] = nil
                        continue
                    }
                }
            }
            scoops[id] = s
        }
    }

    /// すくう途中で、水の動きを止めている金魚
    private func held(_ id: UUID) -> Bool {
        guard let s = scoops[id] else { return false }
        return s.success || s.t < 0.4
    }

    private func splash(at p: SIMD3<Float>, count: Int) {
        for _ in 0..<count {
            addDroplet(at: p + SIMD3(Float.random(in: -0.25...0.25), 0, 0.1),
                       vel: SIMD3(Float.random(in: -0.6...0.6), Float.random(in: 0.6...1.4), 0),
                       material: dropMaterial)
        }
    }

    private func addDroplet(at p: SIMD3<Float>, vel: SIMD3<Float>, material: UnlitMaterial) {
        let node = ModelEntity(mesh: dropletMesh, materials: [material])
        node.position = p
        fishNode.addChild(node)
        droplets.append(Droplet(node: node, vel: vel))
    }

    private func tickDroplets(dt: Float) {
        for i in droplets.indices.reversed() {
            droplets[i].life += dt
            droplets[i].vel.y -= 3.2 * dt
            droplets[i].node.position += droplets[i].vel * dt
            let life = droplets[i].life
            droplets[i].node.components.set(OpacityComponent(opacity: max(0, 1 - life / 0.7)))
            if life >= 0.7 {
                droplets[i].node.removeFromParent()
                droplets.remove(at: i)
            }
        }
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

    // MARK: Simulation

    private func tick(dt rawDT: Float) {
        // すくう演出は、画面が前にあるあいだ必ず最後まで動かす
        let dt = min(rawDT, 0.05)
        guard dt > 0 else { return }
        tickScoops(dt: dt)
        tickDroplets(dt: dt)
        guard isActive else { return }
        time += dt

        // 重力：端末の向きに合わせてゆっくり追う
        var target = SIMD3<Float>(0, -1, 0)
        if let g = motion.deviceMotion?.gravity {
            target = SIMD3(Float(g.x), Float(g.y), Float(g.z) * 0.5)
        }
        gravity += (target - gravity) * min(1, dt * 4)

        let h = Self.half - SIMD3(Self.radius, Self.radius * 0.6, 0)
        let damping = expf(-0.9 * dt)
        // 水槽はジャイロで動かす：傾けたぶんだけ（真下からのずれ）押す。真下向きの重さは浮力で打ち消す
        let tilt = SIMD3<Float>(gravity.x, gravity.y + 1, gravity.z) * 1.2
        let ids = Array(bodies.keys)

        for id in ids where !held(id) {
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
            // 水に浮いている：動きの主役は傾き。それぞれの高さへはゆるく戻り、自分ではかすかに泳ぐだけ
            var acc = tilt
            if b.pos.y <= h.y { acc.y += (b.rest * h.y - b.pos.y) * 0.35 }
            acc.x += sinf(time * 0.23 + b.phase.x) * 0.08
            acc.y += sinf(time * 0.31 + b.phase.y) * 0.05
            acc.z += sinf(time * 0.19 + b.phase.z) * 0.04
            b.vel += acc * dt
            b.vel *= damping
            b.pos += b.vel * dt
            bodies[id] = b
        }

        // 楕円とみなした当たり（やわらかく押し返す）
        let live = ids.filter { bodies[$0]?.leaving == nil && bodies[$0] != nil && !held($0) }
        let minDist = Self.radius * 2
        for i in 0..<live.count {
            for j in (i + 1)..<live.count {
                guard var a = bodies[live[i]], var c = bodies[live[j]] else { continue }
                var d = c.pos - a.pos
                d.y *= 1.6  // 金魚は横長なので、縦は近くまで寄れる
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
            // 進む向きに顔を向ける（左向きの絵なので、右へ進むときは半回転）
            if b.vel.x > 0.04 { b.facing += (.pi - b.facing) * min(1, dt * 5) }
            else if b.vel.x < -0.04 { b.facing += (0 - b.facing) * min(1, dt * 5) }
            let tiltZ = max(-0.35, min(0.35, b.vel.y * 0.6)) * (b.facing > .pi / 2 ? 1 : -1)
            b.node.position = b.pos
            b.node.orientation = simd_quatf(angle: b.facing, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: tiltZ, axis: SIMD3(0, 0, 1))
            bodies[id] = b
        }
    }

    private static func ease(_ x: Float) -> Float {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    // MARK: Meshes

    /// ドットの金魚（マスごとの箱をまとめた1つの形）。奥行きは2マス分。
    private static func makeFishMesh() -> MeshResource {
        let c = cell
        let boxes = GoldfishShape.cells.map { cell -> (center: SIMD3<Float>, half: SIMD3<Float>) in
            (SIMD3(Float(cell.x) * c - 4 * c, (2 - Float(cell.y)) * c, 0), SIMD3(c / 2, c / 2, c))
        }
        return VoxelMesh.mesh(boxes: boxes) ?? .generateBox(size: 0.2)
    }

    /// ドットのポイ（13×13マスの輪と紙、斜めの持ち手）
    private static let poiCells: (ring: [(Int, Int)], paper: [(Int, Int)], torn: [(Int, Int)], handle: [(Int, Int)]) = {
        var ring: [(Int, Int)] = [], paper: [(Int, Int)] = []
        for y in 0..<13 {
            for x in 0..<13 {
                let d = hypot(Double(x - 6), Double(y - 6))
                if d >= 4.6 && d < 6.5 { ring.append((x, y)) } else if d < 4.6 { paper.append((x, y)) }
            }
        }
        let extra: Set<Int> = [5 * 100 + 7, 6 * 100 + 7, 7 * 100 + 8]
        let torn = paper.filter { p in
            let (x, y) = p
            let dx = Double(x - 5), dy = Double(y - 6)
            let inEllipse: Bool = dx * dx / 4 + dy * dy / 9 <= 1.2
            let inHole = inEllipse || extra.contains(y * 100 + x)
            return !inHole
        }
        var handle: [(Int, Int)] = []
        for i in 0..<6 {
            handle.append((11 + i, 1 - i))
            handle.append((12 + i, 1 - i))
        }
        return (ring, paper, torn, handle)
    }()

    private static func makePoiMesh(_ cells: [(Int, Int)]) -> MeshResource {
        let c = poiCell
        let boxes = cells.map { p -> (center: SIMD3<Float>, half: SIMD3<Float>) in
            (SIMD3(Float(p.0 - 6) * c, Float(6 - p.1) * c, 0), SIMD3(c / 2, c / 2, c / 2))
        }
        return VoxelMesh.mesh(boxes: boxes) ?? .generateBox(size: 0.1)
    }
}
