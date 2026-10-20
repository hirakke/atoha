import SwiftUI
import UIKit
import RealityKit
import CoreMotion
import simd

/// 気になることを、本人の軸がつくる空間にボクセルとして置く 3D マップ。
struct VoxelMapView: View {
    let items: [Item]
    let axes: [Axis]
    let selectedID: UUID?
    let mode: MapMode
    let onSelect: (Item?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scene: VoxelMapScene
    @State private var dragLast: CGSize = .zero
    @State private var pinching = false
    @State private var viewSize: CGSize = .zero

    init(items: [Item], axes: [Axis], selectedID: UUID?, mode: MapMode = .axis, onSelect: @escaping (Item?) -> Void) {
        self.items = items
        self.axes = axes
        self.selectedID = selectedID
        self.mode = mode
        self.onSelect = onSelect
        _scene = State(initialValue: VoxelMapScene())
    }

    /// 中身（@Model）の変化でも body が評価し直されるよう、使う値を読んでおく。
    private var observedSignature: Int {
        var h = Hasher()
        for i in items {
            h.combine(i.id)
            h.combine(i.showsOnMap)
            h.combine(i.isCloseToAxis)
            h.combine(i.isRated)
            h.combine(i.want)
            h.combine(i.theme)
            h.combine(i.axisScores)
            h.combine(i.createdAt)
        }
        for a in axes { h.combine(a.order); h.combine(a.negativePole); h.combine(a.positivePole) }
        return h.finalize()
    }

    var body: some View {
        let _ = observedSignature
        let palette = Theme.paletteID
        RealityView { content in
            scene.build(&content)
        } update: { _ in
            scene.onSelect = onSelect
            scene.setScheme(colorScheme, palette: palette)
            scene.update(items: items, axes: axes, selectedID: selectedID, mode: mode)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // 当たり判定は画面上に投影した位置で行う（エンティティを狙うタップは届かないことがあるため）
        .gesture(
            SpatialTapGesture().onEnded { value in
                scene.tapped(at: value.location, in: viewSize)
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4).onChanged { value in
                let d = CGSize(width: value.translation.width - dragLast.width,
                               height: value.translation.height - dragLast.height)
                dragLast = value.translation
                scene.pan(dx: Float(d.width), dy: Float(d.height))
            }.onEnded { _ in
                dragLast = .zero
            }
        )
        .simultaneousGesture(
            MagnifyGesture().onChanged { value in
                if !pinching { pinching = true; scene.pinchBegan() }
                scene.pinchChanged(Float(value.magnification))
            }.onEnded { _ in
                pinching = false
            }
        )
        .onAppear { scene.start() }
        .onDisappear { scene.stop() }
    }
}

/// マップの 3D シーン本体。SceneKit 版の Coordinator を RealityKit に移したもの。
@MainActor
final class VoxelMapScene {
    var onSelect: (Item?) -> Void = { _ in }

    // MARK: Entities
    private let root = Entity()
    private let cameraEntity = Entity()
    private let tiltEntity = Entity()
    private let contentEntity = Entity()
    private let axesEntity = Entity()
    private let itemsEntity = Entity()
    private let edgesEntity = Entity()
    private var axisDotsEntity: ModelEntity?
    private var labelEntities: [ModelEntity] = []
    private var edgeBuckets: [Int: ModelEntity] = [:]
    private var built = false

    // MARK: Item state
    @MainActor private final class Node {
        let id: UUID
        let entity = Entity()
        var visual: ModelEntity?
        var accent: Bool
        var fade: Float
        var scaleTarget: Float
        var pos: SIMD3<Float> = .zero
        var scale: Float
        var opacity: Float = 1
        var moveTween: VoxelTween?
        var scaleTween: VoxelTween?
        var fadeTween: VoxelTween?
        var removing = false
        init(id: UUID, accent: Bool, fade: Float, scale: Float) {
            self.id = id; self.accent = accent; self.fade = fade; self.scaleTarget = scale; self.scale = scale
        }
    }

    private var nodes: [UUID: Node] = [:]
    private var dying: [Node] = []
    private var targets: [UUID: SIMD3<Float>] = [:]
    private var itemsByID: [UUID: Item] = [:]
    private var axesKey: String?

    private var mode: MapMode = .axis
    private var selectedID: UUID?
    private var embCache: [UUID: [Double]] = [:]
    private var edgesKey: String?
    private var edges: [MapEdge] = []
    private var edgeSignature: Float = .nan
    private var edgesDirty = true

    // Force layout
    private var simIDs: [UUID] = []
    private var simPos: [SIMD3<Float>] = []
    private var simVel: [SIMD3<Float>] = []
    private var simEdges: [(Int, Int, Float)] = []
    private var simStep = 0
    private static let simTotal = 300
    private var simActive = false

    // Materials / meshes
    private var scheme: ColorScheme = .light
    private var ink = UIColor.black
    private var inkMaterial = VoxelMesh.unlit(.black)
    private var accentMaterial = VoxelMesh.unlit(Theme.accentUIColor)
    private var paletteID = Theme.paletteID
    private let wireMesh = VoxelMesh.wireBox(half: SIMD3(repeating: Float(VoxelMapScene.voxel) / 2), thickness: 0.010)
    private let boxMesh = MeshResource.generateBox(size: Float(VoxelMapScene.voxel))

    // Rotation state
    private var yaw: Float = 0.6
    private var pitch: Float = -0.35
    private var tiltX: Float = 0
    private var tiltY: Float = 0
    private var cameraZ: Float = 5.4
    private var pinchStartZ: Float = 5.4
    private var lastInteraction: CFTimeInterval = CACurrentMediaTime()
    /// 一度でも触ったら、自動回転はやめる（動いているボクセルはタップしにくいため）
    private var touched = false

    private let motion = CMMotionManager()
    private var referenceAttitude: CMAttitude?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    static let voxel: CGFloat = 0.16
    static let extent: Float = 2.0

    private var pendingArgs: (items: [Item], axes: [Axis], selectedID: UUID?, mode: MapMode)?

    // MARK: Setup

    func build(_ content: inout RealityViewCameraContent) {
        guard !built else { return }
        content.camera = .virtual
        content.renderingEffects.antialiasing = .multisample4X

        var cam = PerspectiveCameraComponent(near: 0.1, far: 100, fieldOfViewInDegrees: 52,
                                             fieldOfViewOrientation: .horizontal)
        cam.fieldOfViewOrientation = .horizontal  // 縦長の画面でも左右の極のラベルが収まるよう、横方向で画角を決める
        cameraEntity.components.set(cam)
        cameraEntity.position = SIMD3(0, 0, cameraZ)
        root.addChild(cameraEntity)

        root.addChild(tiltEntity)
        tiltEntity.addChild(contentEntity)
        contentEntity.addChild(axesEntity)
        contentEntity.addChild(edgesEntity)
        contentEntity.addChild(itemsEntity)
        applyRotation()
        content.add(root)

        subscriptionBag.append(content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.tick(dt: dt) }
        })

        refreshColors()
        built = true
        start()
        if let a = pendingArgs {
            update(items: a.items, axes: a.axes, selectedID: a.selectedID, mode: a.mode)
        }
    }

    private var subscriptionBag: [EventSubscription] = []

    func start() {
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 30.0
            motion.startDeviceMotionUpdates()
        }
        haptic.prepare()
    }

    func stop() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        referenceAttitude = nil
    }

    func setScheme(_ s: ColorScheme, palette: String) {
        guard s != scheme || palette != paletteID else { return }
        scheme = s
        paletteID = palette
        if built { refreshColors() }
    }

    private func refreshColors() {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        ink = Theme.inkUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        inkMaterial = VoxelMesh.unlit(ink)
        accentMaterial = VoxelMesh.unlit(Theme.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
        for node in nodes.values { node.visual?.model?.materials = [node.accent ? accentMaterial : inkMaterial] }
        for node in dying { node.visual?.model?.materials = [node.accent ? accentMaterial : inkMaterial] }
        axisDotsEntity?.model?.materials = [inkMaterial]
        for l in labelEntities { l.model?.materials = [inkMaterial] }
        for e in edgeBuckets.values { e.model?.materials = [inkMaterial] }
    }

    // MARK: Diff update

    func update(items: [Item], axes: [Axis], selectedID: UUID?, mode newMode: MapMode) {
        pendingArgs = (items, axes, selectedID, newMode)
        guard built else { return }
        let modeChanged = newMode != mode
        mode = newMode
        if self.selectedID != selectedID { edgesDirty = true }
        self.selectedID = selectedID
        let graph = (newMode == .graph)
        axesEntity.isEnabled = !graph
        let visible = items.filter(\.showsOnMap)
        let activeAxes = Array(axes.sorted { $0.order < $1.order }.prefix(3))

        let key = activeAxes.map { "\($0.negativePole)|\($0.positivePole)" }.joined(separator: "‖")
        if key != axesKey {
            axesKey = key
            rebuildAxes(activeAxes)
        }

        var seen = Set<UUID>()
        itemsByID.removeAll(keepingCapacity: true)
        let now = Date()

        let minT = visible.map(\.createdAt.timeIntervalSince1970).min() ?? 0
        let maxT = visible.map(\.createdAt.timeIntervalSince1970).max() ?? 0
        let span = maxT - minT
        var layoutChanged = modeChanged

        for item in visible {
            let id = item.id
            seen.insert(id)
            itemsByID[id] = item
            let target = Self.position(for: item, axisCount: activeAxes.count)
            let accent = item.isCloseToAxis
            let rated: Float = (item.isRated ? item.want : nil).map { 0.8 + 0.7 * Float(min(1, max(0, $0))) } ?? 1.0
            let scale: Float = (id == selectedID) ? 1.6 * rated : rated
            let age: Float = span > 1 ? Float((item.createdAt.timeIntervalSince1970 - minT) / span) : 1
            let fade: Float = (id == selectedID) ? 1 : 0.3 + 0.7 * age

            if let node = nodes[id] {
                if node.accent != accent {
                    node.accent = accent
                    applyLook(to: node)
                }
                if node.fade != fade {
                    node.fade = fade
                    node.fadeTween = VoxelTween(from: node.opacity, to: fade, duration: 0.3, ease: .linear)
                    edgesDirty = true
                }
                if graph {
                    targets[id] = target
                } else if let old = targets[id], modeChanged || simd_distance(old, target) > 0.0005 {
                    targets[id] = target
                    node.moveTween = VoxelTween(from: node.pos, to: target, duration: 0.35, ease: .inOut)
                }
                if node.scaleTarget != scale {
                    node.scaleTarget = scale
                    node.scaleTween = VoxelTween(from: node.scale, to: scale, duration: 0.2, ease: .out)
                }
            } else {
                let node = Node(id: id, accent: accent, fade: fade, scale: scale)
                node.entity.name = id.uuidString
                node.entity.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(repeating: Float(Self.voxel)))]))
                node.entity.components.set(InputTargetComponent())
                applyLook(to: node)
                node.entity.scale = SIMD3(repeating: scale)
                itemsEntity.addChild(node.entity)
                nodes[id] = node
                targets[id] = target
                layoutChanged = true

                if graph {
                    node.pos = Self.seeded(id)
                    node.opacity = 0
                    node.fadeTween = VoxelTween(from: 0, to: fade, duration: 0.5, ease: .linear)
                } else if now.timeIntervalSince(item.createdAt) < 8 {
                    node.pos = SIMD3(target.x, target.y + 3, target.z)
                    node.opacity = 0
                    node.moveTween = VoxelTween(from: node.pos, to: target, duration: 0.6, ease: .out)
                    node.fadeTween = VoxelTween(from: 0, to: fade, duration: 0.6, ease: .linear)
                } else {
                    node.pos = target
                    node.opacity = fade
                }
                node.entity.position = node.pos
                node.entity.components.set(OpacityComponent(opacity: node.opacity))
            }
        }

        for (id, node) in nodes where !seen.contains(id) {
            nodes[id] = nil
            targets[id] = nil
            layoutChanged = true
            node.removing = true
            node.moveTween = nil
            node.scaleTween = nil
            node.fadeTween = VoxelTween(from: node.opacity, to: 0, duration: 0.25, ease: .linear)
            node.entity.components.remove(CollisionComponent.self)
            node.entity.components.remove(InputTargetComponent.self)
            dying.append(node)
        }

        if recomputeEdges(visible) { layoutChanged = true }
        if graph {
            if layoutChanged { startSim() }
        } else {
            simActive = false
        }
    }

    private func applyLook(to node: Node) {
        node.visual?.removeFromParent()
        let visual: ModelEntity
        if node.accent {
            visual = ModelEntity(mesh: boxMesh, materials: [accentMaterial])
        } else {
            visual = ModelEntity(mesh: wireMesh, materials: [inkMaterial])
        }
        node.entity.addChild(visual)
        node.visual = visual
    }

    // MARK: Edges

    private func embedding(for item: Item) -> [Double] {
        if let v = embCache[item.id] { return v }
        let raw = (item.embedding?.isEmpty == false) ? item.embedding! : EmbeddingService.embed(item.text)
        let v = EmbeddingService.l2(raw)
        embCache[item.id] = v
        return v
    }

    /// 各ノードから類似度の高い上位2本（下限 0.35、2本目は1本目の 85% 以上）＋同テーマの最近傍を強い辺にする。
    private func recomputeEdges(_ visible: [Item]) -> Bool {
        let key = visible.map { "\($0.id.uuidString)\($0.theme ?? "")" }.sorted().joined(separator: ",")
        if key == edgesKey { return false }
        edgesKey = key
        edgesDirty = true
        embCache = embCache.filter { id, _ in itemsByID[id] != nil }

        let n = visible.count
        let vecs = visible.map { embedding(for: $0) }
        func sim(_ i: Int, _ j: Int) -> Double {
            let a = vecs[i], b = vecs[j]
            guard a.count == b.count, !a.isEmpty else { return 0 }
            var d = 0.0
            a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in
                for k in 0..<pa.count { d += pa[k] * pb[k] }
            } }
            return d
        }
        var found: [String: MapEdge] = [:]
        func add(_ i: Int, _ j: Int, strong: Bool) {
            let a = visible[i].id, b = visible[j].id
            let (lo, hi) = a.uuidString < b.uuidString ? (a, b) : (b, a)
            let k = lo.uuidString + hi.uuidString
            if let old = found[k], old.strong || !strong { return }
            found[k] = MapEdge(a: lo, b: hi, strong: strong)
        }
        // 埋め込みの質で類似度の絶対値がぶれるので、最も近い1本は必ず結び、2本目だけ下限で絞る
        let floor = 0.15
        for i in 0..<n {
            var b1 = (-1, -2.0), b2 = (-1, -2.0)
            var bestSame = (-1, -2.0)
            let theme = visible[i].theme.flatMap { $0.isEmpty ? nil : $0 }
            for j in 0..<n where j != i {
                let s = sim(i, j)
                if s > b1.1 { b2 = b1; b1 = (j, s) } else if s > b2.1 { b2 = (j, s) }
                if let t = theme, visible[j].theme == t, s > bestSame.1 { bestSame = (j, s) }
            }
            if b1.0 >= 0 {
                add(i, b1.0, strong: false)
                if b2.0 >= 0, b2.1 >= floor, b2.1 >= b1.1 * 0.85 { add(i, b2.0, strong: false) }
            }
            if bestSame.0 >= 0 { add(i, bestSame.0, strong: true) }
        }
        edges = Array(found.values)
        return true
    }

    /// 点線を、不透明度ごとに 1 メッシュへまとめて作り直す。
    private func rebuildEdgeGeometry() {
        edgesDirty = false
        var groups: [Int: [(a: SIMD3<Float>, b: SIMD3<Float>)]] = [:]
        for e in edges {
            guard let na = nodes[e.a], let nb = nodes[e.b] else { continue }
            let pa = na.pos, pb = nb.pos
            let len = simd_distance(pa, pb)
            let count = min(40, max(2, Int(len / 0.14)))
            var alpha: Float = e.strong ? 0.6 : 0.38
            if let s = selectedID { alpha = (e.a == s || e.b == s) ? 0.85 : 0.05 }
            let f = min(na.fade, nb.fade)
            alpha *= 0.5 + 0.5 * f
            let bucket = max(1, Int((alpha * 25).rounded()))
            // 点線：各区間の前半だけ線分を引く
            var segs: [(a: SIMD3<Float>, b: SIMD3<Float>)] = []
            segs.reserveCapacity(count)
            for k in 0..<count {
                let t0 = Float(k) / Float(count), t1 = (Float(k) + 0.5) / Float(count)
                segs.append((pa + (pb - pa) * t0, pa + (pb - pa) * t1))
            }
            groups[bucket, default: []].append(contentsOf: segs)
        }
        for (bucket, entity) in edgeBuckets where groups[bucket] == nil {
            entity.isEnabled = false
        }
        for (bucket, segs) in groups {
            guard let mesh = VoxelMesh.mesh(segments: segs, halfWidth: 0.0045) else { continue }
            let opacity = Float(bucket) / 25
            if let entity = edgeBuckets[bucket] {
                entity.model?.mesh = mesh
                entity.isEnabled = true
            } else {
                let entity = ModelEntity(mesh: mesh, materials: [inkMaterial])
                entity.components.set(OpacityComponent(opacity: min(1, opacity)))
                edgesEntity.addChild(entity)
                edgeBuckets[bucket] = entity
            }
        }
    }

    // MARK: Force layout

    static func seeded(_ id: UUID) -> SIMD3<Float> {
        let u = hashPosition(id)
        return SIMD3(u[0], u[1], u[2]) * extent
    }

    private func startSim() {
        var index: [UUID: Int] = [:]
        simIDs = Array(nodes.compactMap { itemsByID[$0.key] != nil ? $0.key : nil }).sorted { $0.uuidString < $1.uuidString }
        simPos = simIDs.enumerated().map { i, id in
            index[id] = i
            if let node = nodes[id] {
                let v = node.pos
                // 新規ノードは原点に居ることがある。その場合は ID から決めた位置で始める。
                if v.x.isFinite, v.y.isFinite, v.z.isFinite, abs(v.x) + abs(v.y) + abs(v.z) > 0.001 { return v }
            }
            return Self.seeded(id)
        }
        simVel = Array(repeating: .zero, count: simIDs.count)
        simEdges = edges.compactMap { e in
            guard let a = index[e.a], let b = index[e.b] else { return nil }
            return (a, b, e.strong ? 1.0 : 0.6)
        }
        simStep = 0
        simActive = !simIDs.isEmpty
        for id in simIDs { nodes[id]?.moveTween = nil }
    }

    private func stepSim(iterations: Int) {
        let n = simPos.count
        let rep: Float = 6 / Float(n + 20)
        for _ in 0..<iterations where simStep < Self.simTotal {
            let alpha = max(0.03, 1 - Float(simStep) / Float(Self.simTotal))
            var force = [SIMD3<Float>](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<max(n, i + 1) {
                    var d = simPos[i] - simPos[j]
                    if abs(d.x) + abs(d.y) + abs(d.z) < 0.001 {
                        d = Self.seeded(simIDs[i]) - Self.seeded(simIDs[j]) + SIMD3(0.01, 0.02, 0.03)
                    }
                    let r2 = max(d.x * d.x + d.y * d.y + d.z * d.z, 0.02)
                    let f = d / r2.squareRoot() * min(rep / r2, 1.5)
                    force[i] += f
                    force[j] -= f
                }
                force[i] -= simPos[i] * 0.25
            }
            for (a, b, w) in simEdges {
                let d = simPos[b] - simPos[a]
                let len = max((d.x * d.x + d.y * d.y + d.z * d.z).squareRoot(), 0.001)
                let f = d / len * ((len - 0.7) * 0.8 * w)
                force[a] += f
                force[b] -= f
            }
            for i in 0..<n {
                var v = (simVel[i] + force[i] * 0.06 * alpha) * 0.8
                let sp = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
                if sp > 0.15 { v *= 0.15 / sp }
                simVel[i] = v
                simPos[i] += v
                if !(simPos[i].x.isFinite && simPos[i].y.isFinite && simPos[i].z.isFinite) { simPos[i] = Self.seeded(simIDs[i]); simVel[i] = .zero }
                let r = (simPos[i].x * simPos[i].x + simPos[i].y * simPos[i].y + simPos[i].z * simPos[i].z).squareRoot()
                if r > Self.extent * 1.2 { simPos[i] *= Self.extent * 1.2 / r }
            }
            simStep += 1
        }
        for (i, id) in simIDs.enumerated() {
            if let node = nodes[id] {
                node.pos = simPos[i]
                node.entity.position = simPos[i]
            }
        }
        if simStep >= Self.simTotal { simActive = false }
    }

    // MARK: Axes

    private func rebuildAxes(_ axes: [Axis]) {
        for c in Array(axesEntity.children) { c.removeFromParent() }
        labelEntities.removeAll()

        let reach: Float = Self.extent + 0.3
        let step: Float = 0.16
        var dots: [(center: SIMD3<Float>, half: SIMD3<Float>)] = []
        for dim in 0..<3 {
            var t: Float = -reach
            while t <= reach + 0.001 {
                dots.append((Self.vector(dim: dim, value: t), SIMD3(repeating: 0.0125)))
                t += step
            }
        }
        if let mesh = VoxelMesh.mesh(boxes: dots) {
            let e = ModelEntity(mesh: mesh, materials: [inkMaterial])
            e.components.set(OpacityComponent(opacity: 0.18))
            axesEntity.addChild(e)
            axisDotsEntity = e
        }

        for (dim, axis) in axes.enumerated() where dim < 3 {
            let labelReach = reach + 0.3
            axesEntity.addChild(makeLabel(axis.negativePole, at: Self.vector(dim: dim, value: -labelReach)))
            axesEntity.addChild(makeLabel(axis.positivePole, at: Self.vector(dim: dim, value: labelReach)))
        }
    }

    private func makeLabel(_ string: String, at position: SIMD3<Float>) -> Entity {
        let holder = Entity()
        holder.position = position
        holder.components.set(BillboardComponent())
        holder.components.set(OpacityComponent(opacity: 0.8))
        let font = UIFont.monospacedSystemFont(ofSize: 0.168, weight: .regular)
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: font)
        let text = ModelEntity(mesh: mesh, materials: [inkMaterial])
        let c = mesh.bounds.center
        text.position = SIMD3(-c.x, -c.y, 0)
        holder.addChild(text)
        labelEntities.append(text)
        return holder
    }

    // MARK: Interaction

    func pan(dx: Float, dy: Float) {
        yaw += dx * 0.008
        pitch = max(-1.3, min(1.3, pitch + dy * 0.008))
        lastInteraction = CACurrentMediaTime(); touched = true
        applyRotation()
    }

    func pinchBegan() {
        pinchStartZ = cameraZ
        lastInteraction = CACurrentMediaTime(); touched = true
    }

    func pinchChanged(_ magnification: Float) {
        cameraZ = max(2.8, min(10, pinchStartZ / max(magnification, 0.01)))
        cameraEntity.position = SIMD3(0, 0, cameraZ)
        lastInteraction = CACurrentMediaTime(); touched = true
    }

    /// タップした点に一番近い立方体を選ぶ。各立方体をカメラから画面へ投影して比べる。
    func tapped(at point: CGPoint, in size: CGSize) {
        lastInteraction = CACurrentMediaTime(); touched = true
        guard size.width > 0, size.height > 0 else { return }
        let focal = Float(size.width / 2) / tan(Float(26 * Double.pi / 180))  // 横の画角 52°
        var best: (id: UUID, distance: Float)?
        for (id, node) in nodes where !node.removing {
            let p = node.entity.position(relativeTo: cameraEntity)
            guard p.z < -0.05 else { continue }
            let depth = -p.z
            let sx = Float(size.width / 2) + focal * p.x / depth
            let sy = Float(size.height / 2) - focal * p.y / depth
            let distance = hypot(sx - Float(point.x), sy - Float(point.y))
            // 立方体の見かけの大きさに、指の分の余裕を足した範囲で当たりとする
            let radius = focal * Float(Self.voxel) * node.scale / depth * 0.75 + 18
            if distance <= radius, distance < (best?.distance ?? .infinity) { best = (id, distance) }
        }
        if let best, let item = itemsByID[best.id] {
            haptic.impactOccurred()
            haptic.prepare()
            onSelect(item)
        } else {
            onSelect(nil)
        }
    }

    // MARK: Frame loop

    private func tick(dt rawDT: Float) {
        guard built else { return }
        let dt = min(rawDT, 0.1)
        let now = CACurrentMediaTime()

        let idle = now - lastInteraction
        if !touched && idle > 3 {
            let ramp = Float(min(1, (idle - 3) / 2))
            yaw += dt * 0.12 * ramp
        }

        var targetX: Float = 0
        var targetY: Float = 0
        if let attitude = motion.deviceMotion?.attitude {
            if referenceAttitude == nil {
                referenceAttitude = attitude.copy() as? CMAttitude
            }
            if let ref = referenceAttitude, let rel = attitude.copy() as? CMAttitude {
                rel.multiply(byInverseOf: ref)
                targetX = max(-0.25, min(0.25, Float(rel.pitch) * 0.5))
                targetY = max(-0.25, min(0.25, Float(rel.roll) * 0.5))
            }
        }
        let k = min(1, dt * 6)
        tiltX += (targetX - tiltX) * k
        tiltY += (targetY - tiltY) * k
        tiltEntity.orientation = simd_quatf(angle: tiltX, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: tiltY, axis: SIMD3(0, 1, 0))
        applyRotation()

        advanceTweens(dt: dt)

        if simActive { stepSim(iterations: 2) }
        if !edges.isEmpty {
            var sig: Float = 0
            for e in edges {
                if let p = nodes[e.a]?.pos { sig += p.x + p.y * 1.3 + p.z * 1.7 }
                if let p = nodes[e.b]?.pos { sig += p.x + p.y * 1.3 + p.z * 1.7 }
            }
            if sig != edgeSignature { edgeSignature = sig; edgesDirty = true }
        }
        if edgesDirty { rebuildEdgeGeometry() }
    }

    private func advanceTweens(dt: Float) {
        func step(_ node: Node) {
            if var t = node.moveTween {
                let (v, done) = t.advance(dt)
                node.pos = v
                node.entity.position = v
                node.moveTween = done ? nil : t
            }
            if var t = node.scaleTween {
                let (v, done) = t.advance(dt)
                node.scale = v.x
                node.entity.scale = SIMD3(repeating: v.x)
                node.scaleTween = done ? nil : t
            }
            if var t = node.fadeTween {
                let (v, done) = t.advance(dt)
                node.opacity = v.x
                node.entity.components.set(OpacityComponent(opacity: v.x))
                node.fadeTween = done ? nil : t
            }
        }
        for node in nodes.values { step(node) }
        if !dying.isEmpty {
            for node in dying { step(node) }
            dying.removeAll { node in
                guard node.fadeTween == nil else { return false }
                node.entity.removeFromParent()
                return true
            }
        }
    }

    private func applyRotation() {
        contentEntity.orientation = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
    }

    // MARK: Geometry helpers

    static func vector(dim: Int, value: Float) -> SIMD3<Float> {
        switch dim {
        case 0: SIMD3(value, 0, 0)
        case 1: SIMD3(0, value, 0)
        default: SIMD3(0, 0, value)
        }
    }

    // MARK: Positioning

    static func position(for item: Item, axisCount: Int) -> SIMD3<Float> {
        let unit: [Float]
        if axisCount > 0, !item.axisScores.isEmpty {
            unit = (0..<3).map { i in
                guard i < item.axisScores.count, i < axisCount else { return 0 }
                return Float(max(-1, min(1, item.axisScores[i])))
            }
        } else if let embedding = item.embedding, !embedding.isEmpty {
            unit = project(embedding)
        } else {
            unit = hashPosition(item.id)
        }
        return SIMD3(unit[0] * extent, unit[1] * extent, unit[2] * extent)
    }

    /// 固定シードのランダム射影で埋め込みを 3 次元へ。
    private static func project(_ e: [Double]) -> [Float] {
        let norm = e.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return [0, 0, 0] }
        var out: [Float] = []
        for k in 0..<3 {
            var rng = VoxelSplitMix(seed: 0xA70_4A00 &+ UInt64(k) &* 0x9E37_79B9)
            var dot = 0.0
            for v in e {
                // approx. gaussian: sum of uniforms
                let g = (rng.unit() + rng.unit() + rng.unit() - 1.5) * 2
                dot += (v / norm) * g
            }
            // dot ~ N(0, ~1)
            out.append(Float(tanh(dot)))
        }
        return out
    }

    fileprivate static func hashPosition(_ id: UUID) -> [Float] {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        var rng = VoxelSplitMix(seed: hash)
        return (0..<3).map { _ in Float(rng.unit() * 2 - 1) * 0.85 }
    }
}

/// 時間で進む単純なトゥイーン（SCNAction の move / scale / fade の代わり）。値は xyz、スカラーは x。
struct VoxelTween {
    enum Ease { case linear, `in`, out, inOut }
    var from: SIMD3<Float>
    var to: SIMD3<Float>
    var duration: Float
    var ease: Ease
    var elapsed: Float = 0

    init(from: SIMD3<Float>, to: SIMD3<Float>, duration: Float, ease: Ease) {
        self.from = from; self.to = to; self.duration = duration; self.ease = ease
    }

    init(from: Float, to: Float, duration: Float, ease: Ease) {
        self.init(from: SIMD3(from, 0, 0), to: SIMD3(to, 0, 0), duration: duration, ease: ease)
    }

    mutating func advance(_ dt: Float) -> (SIMD3<Float>, done: Bool) {
        elapsed += dt
        let u = min(1, elapsed / max(duration, 0.0001))
        let e: Float
        switch ease {
        case .linear: e = u
        case .in: e = u * u
        case .out: e = 1 - (1 - u) * (1 - u)
        case .inOut: e = u * u * (3 - 2 * u)
        }
        return (from + (to - from) * e, u >= 1)
    }
}

private struct VoxelSplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

struct MapEdge {
    let a: UUID
    let b: UUID
    let strong: Bool
}
