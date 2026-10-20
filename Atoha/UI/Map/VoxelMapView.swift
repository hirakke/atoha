import SwiftUI
import UIKit
import SceneKit
import CoreMotion

/// 気になることを、本人の軸がつくる空間にボクセルとして置く 3D マップ。
struct VoxelMapView: UIViewRepresentable {
    let items: [Item]
    let axes: [Axis]
    let selectedID: UUID?
    let mode: MapMode
    let onSelect: (Item?) -> Void

    init(items: [Item], axes: [Axis], selectedID: UUID?, mode: MapMode = .axis, onSelect: @escaping (Item?) -> Void) {
        self.items = items
        self.axes = axes
        self.selectedID = selectedID
        self.mode = mode
        self.onSelect = onSelect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.onSelect = onSelect
        context.coordinator.update(items: items, axes: axes, selectedID: selectedID, mode: mode)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.refreshColors()
        context.coordinator.update(items: items, axes: axes, selectedID: selectedID, mode: mode)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSelect: (Item?) -> Void = { _ in }

        private weak var scnView: SCNView?
        private let scene = SCNScene()
        private let cameraNode = SCNNode()
        private let tiltNode = SCNNode()
        private let contentNode = SCNNode()
        private let axesNode = SCNNode()
        private let itemsNode = SCNNode()
        private let edgesNode = SCNNode()
        private let edgeMaterial = SCNMaterial()

        private var fades: [UUID: Float] = [:]
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

        private var nodes: [UUID: SCNNode] = [:]
        private var looks: [UUID: Bool] = [:]          // accent?
        private var targets: [UUID: SCNVector3] = [:]
        private var scales: [UUID: Float] = [:]
        private var itemsByID: [UUID: Item] = [:]
        private var axesKey: String?

        // Shared materials / geometries
        private let accentMaterial = SCNMaterial()
        private let wireMaterial = SCNMaterial()
        private let hitMaterial = SCNMaterial()
        private let axisMaterial = SCNMaterial()
        private let labelMaterial = SCNMaterial()
        private lazy var accentBox: SCNGeometry = {
            let b = SCNBox(width: Self.voxel, height: Self.voxel, length: Self.voxel, chamferRadius: 0)
            b.materials = [accentMaterial]
            return b
        }()
        private lazy var hitBox: SCNGeometry = {
            let b = SCNBox(width: Self.voxel, height: Self.voxel, length: Self.voxel, chamferRadius: 0)
            b.materials = [hitMaterial]
            return b
        }()
        private lazy var edgeGeometry: SCNGeometry = Self.makeEdges(size: Self.voxel, material: wireMaterial)

        // Rotation state
        private var yaw: Float = 0.6
        private var pitch: Float = -0.35
        private var tiltX: Float = 0
        private var tiltY: Float = 0
        private var cameraZ: Float = 5.4
        private var pinchStartZ: Float = 5.4
        private var lastPan: CGPoint = .zero
        private var lastInteraction: CFTimeInterval = CACurrentMediaTime()
        /// 一度でも触ったら、自動回転はやめる（動いているボクセルはタップしにくいため）
        private var touched = false
        private var lastTick: CFTimeInterval = CACurrentMediaTime()

        private var displayLink: CADisplayLink?
        private let motion = CMMotionManager()
        private var referenceAttitude: CMAttitude?
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        static let voxel: CGFloat = 0.16
        static let extent: Float = 2.0
        static let itemCategory = 1 << 1

        // MARK: Setup

        func attach(to view: SCNView) {
            scnView = view
            view.scene = scene
            view.backgroundColor = .clear
            view.isOpaque = false
            scene.background.contents = UIColor.clear
            view.antialiasingMode = .multisampling4X
            view.allowsCameraControl = false
            view.rendersContinuously = true
            view.autoenablesDefaultLighting = false

            let camera = SCNCamera()
            // 縦長の画面でも左右の極のラベルが収まるよう、横方向で画角を決める
            camera.projectionDirection = .horizontal
            camera.fieldOfView = 52
            camera.zNear = 0.1
            camera.zFar = 100
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, cameraZ)
            scene.rootNode.addChildNode(cameraNode)

            scene.rootNode.addChildNode(tiltNode)
            tiltNode.addChildNode(contentNode)
            contentNode.addChildNode(axesNode)
            contentNode.addChildNode(edgesNode)
            contentNode.addChildNode(itemsNode)
            applyRotation()

            for m in [accentMaterial, wireMaterial, axisMaterial, labelMaterial, edgeMaterial] {
                m.lightingModel = .constant
                m.isDoubleSided = true
            }
            edgeMaterial.diffuse.contents = UIColor.white
            edgeMaterial.writesToDepthBuffer = false
            hitMaterial.lightingModel = .constant
            hitMaterial.colorBufferWriteMask = []
            hitMaterial.writesToDepthBuffer = false
            refreshColors()

            view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: SCNView, _: UITraitCollection) in
                self?.refreshColors()
            }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(tap)

            if motion.isDeviceMotionAvailable {
                motion.deviceMotionUpdateInterval = 1.0 / 30.0
                motion.startDeviceMotionUpdates()
            }

            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            haptic.prepare()
        }

        func teardown() {
            displayLink?.invalidate()
            displayLink = nil
            if motion.isDeviceMotionActive {
                motion.stopDeviceMotionUpdates()
            }
        }

        func refreshColors() {
            let traits = scnView?.traitCollection ?? UITraitCollection.current
            let ink = Theme.inkUIColor.resolvedColor(with: traits)
            accentMaterial.diffuse.contents = Theme.accentUIColor
            wireMaterial.diffuse.contents = ink
            axisMaterial.diffuse.contents = ink.withAlphaComponent(0.18)
            labelMaterial.diffuse.contents = ink.withAlphaComponent(0.8)
            edgesDirty = true
        }

        // MARK: Diff update

        func update(items: [Item], axes: [Axis], selectedID: UUID?, mode newMode: MapMode) {
            let modeChanged = newMode != mode
            mode = newMode
            if self.selectedID != selectedID { edgesDirty = true }
            self.selectedID = selectedID
            let graph = (newMode == .graph)
            axesNode.isHidden = graph
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
                    if looks[id] != accent {
                        applyLook(to: node, accent: accent)
                        looks[id] = accent
                    }
                    if fades[id] != fade {
                        fades[id] = fade
                        node.runAction(.fadeOpacity(to: CGFloat(fade), duration: 0.3), forKey: "fade")
                        edgesDirty = true
                    }
                    if graph {
                        targets[id] = target
                    } else if let old = targets[id], modeChanged || Self.distance(old, target) > 0.0005 {
                        targets[id] = target
                        let move = SCNAction.move(to: target, duration: 0.35)
                        move.timingMode = .easeInEaseOut
                        node.runAction(move, forKey: "move")
                    }
                    if scales[id] != scale {
                        scales[id] = scale
                        let s = SCNAction.scale(to: CGFloat(scale), duration: 0.2)
                        s.timingMode = .easeOut
                        node.runAction(s, forKey: "scale")
                    }
                } else {
                    let node = SCNNode()
                    node.name = id.uuidString
                    node.categoryBitMask = Self.itemCategory
                    applyLook(to: node, accent: accent)
                    node.scale = SCNVector3(scale, scale, scale)
                    itemsNode.addChildNode(node)
                    nodes[id] = node
                    looks[id] = accent
                    targets[id] = target
                    scales[id] = scale
                    fades[id] = fade
                    layoutChanged = true

                    if graph {
                        let p = Self.seeded(id)
                        node.position = SCNVector3(p.x, p.y, p.z)
                        node.opacity = 0
                        node.runAction(.fadeOpacity(to: CGFloat(fade), duration: 0.5), forKey: "fade")
                    } else if now.timeIntervalSince(item.createdAt) < 8 {
                        node.position = SCNVector3(target.x, target.y + 3, target.z)
                        node.opacity = 0
                        let move = SCNAction.move(to: target, duration: 0.6)
                        move.timingMode = .easeOut
                        node.runAction(.group([move, .fadeOpacity(to: CGFloat(fade), duration: 0.6)]), forKey: "move")
                    } else {
                        node.position = target
                        node.opacity = CGFloat(fade)
                    }
                }
            }

            for (id, node) in nodes where !seen.contains(id) {
                nodes[id] = nil
                looks[id] = nil
                targets[id] = nil
                scales[id] = nil
                fades[id] = nil
                layoutChanged = true
                node.categoryBitMask = 0
                node.runAction(.sequence([.fadeOut(duration: 0.25), .removeFromParentNode()]))
            }

            if recomputeEdges(visible) { layoutChanged = true }
            if graph {
                if layoutChanged { startSim() }
            } else {
                simActive = false
            }
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

        private func rebuildEdgeGeometry() {
            edgesDirty = false
            let traits = scnView?.traitCollection ?? UITraitCollection.current
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            Theme.inkUIColor.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            var verts: [SCNVector3] = []
            var cols: [Float] = []
            for e in edges {
                guard let na = nodes[e.a], let nb = nodes[e.b] else { continue }
                let pa = na.presentation.position, pb = nb.presentation.position
                let len = Self.distance(pa, pb)
                let count = min(40, max(2, Int(len / 0.14)))
                var alpha: Float = e.strong ? 0.6 : 0.38
                if let s = selectedID { alpha = (e.a == s || e.b == s) ? 0.85 : 0.05 }
                let f = min(fades[e.a] ?? 1, fades[e.b] ?? 1)
                alpha *= 0.5 + 0.5 * f
                // 点線：各区間の前半だけ線分を引く
                for k in 0..<count {
                    for t in [Float(k) / Float(count), (Float(k) + 0.5) / Float(count)] {
                        verts.append(SCNVector3(pa.x + (pb.x - pa.x) * t, pa.y + (pb.y - pa.y) * t, pa.z + (pb.z - pa.z) * t))
                        cols.append(contentsOf: [Float(r), Float(g), Float(b), alpha])
                    }
                }
            }
            guard !verts.isEmpty else { edgesNode.geometry = nil; return }
            let src = SCNGeometrySource(vertices: verts)
            let colorData = cols.withUnsafeBufferPointer { Data(buffer: $0) }
            let colSrc = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: verts.count,
                                           usesFloatComponents: true, componentsPerVector: 4,
                                           bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let idx = (0..<UInt32(verts.count)).map { $0 }
            let el = SCNGeometryElement(indices: idx, primitiveType: .line)
            let geo = SCNGeometry(sources: [src, colSrc], elements: [el])
            geo.materials = [edgeMaterial]
            edgesNode.geometry = geo
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
                    let p = node.position
                    let v = SIMD3(p.x, p.y, p.z)
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
            for id in simIDs { nodes[id]?.removeAction(forKey: "move") }
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
                let p = simPos[i]
                nodes[id]?.position = SCNVector3(p.x, p.y, p.z)
            }
            if simStep >= Self.simTotal { simActive = false }
        }

        private func applyLook(to node: SCNNode, accent: Bool) {
            node.childNodes.forEach { $0.removeFromParentNode() }
            if accent {
                node.geometry = accentBox
            } else {
                node.geometry = hitBox
                let edges = SCNNode(geometry: edgeGeometry)
                node.addChildNode(edges)
            }
        }

        // MARK: Axes

        private func rebuildAxes(_ axes: [Axis]) {
            axesNode.childNodes.forEach { $0.removeFromParentNode() }

            let dots = SCNNode()
            let dot = SCNBox(width: 0.025, height: 0.025, length: 0.025, chamferRadius: 0)
            dot.materials = [axisMaterial]
            let reach: Float = Self.extent + 0.3
            let step: Float = 0.16
            for dim in 0..<3 {
                var t: Float = -reach
                while t <= reach + 0.001 {
                    let n = SCNNode(geometry: dot)
                    n.position = Self.vector(dim: dim, value: t)
                    dots.addChildNode(n)
                    t += step
                }
            }
            let flat = dots.flattenedClone()
            flat.categoryBitMask = 1
            axesNode.addChildNode(flat)

            for (dim, axis) in axes.enumerated() where dim < 3 {
                let labelReach = reach + 0.3
                axesNode.addChildNode(makeLabel(axis.negativePole, at: Self.vector(dim: dim, value: -labelReach)))
                axesNode.addChildNode(makeLabel(axis.positivePole, at: Self.vector(dim: dim, value: labelReach)))
            }
        }

        private func makeLabel(_ string: String, at position: SCNVector3) -> SCNNode {
            let text = SCNText(string: string, extrusionDepth: 0)
            text.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            text.flatness = 0.1
            text.materials = [labelMaterial]

            let textNode = SCNNode(geometry: text)
            let (minV, maxV) = textNode.boundingBox
            textNode.pivot = SCNMatrix4MakeTranslation((minV.x + maxV.x) / 2, (minV.y + maxV.y) / 2, 0)
            let s: Float = 0.014
            textNode.scale = SCNVector3(s, s, s)

            let holder = SCNNode()
            holder.position = position
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            holder.constraints = [billboard]
            holder.addChildNode(textNode)
            return holder
        }

        // MARK: Interaction

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
                || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = scnView else { return }
            let p = g.translation(in: view)
            if g.state == .began { lastPan = .zero }
            let dx = Float(p.x - lastPan.x)
            let dy = Float(p.y - lastPan.y)
            lastPan = p
            yaw += dx * 0.008
            pitch = max(-1.3, min(1.3, pitch + dy * 0.008))
            lastInteraction = CACurrentMediaTime(); touched = true
            applyRotation()
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                pinchStartZ = cameraZ
            case .changed, .ended:
                let scale = max(Float(g.scale), 0.01)
                cameraZ = max(2.8, min(10, pinchStartZ / scale))
                cameraNode.position = SCNVector3(0, 0, cameraZ)
            default:
                break
            }
            lastInteraction = CACurrentMediaTime(); touched = true
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            lastInteraction = CACurrentMediaTime(); touched = true
            let point = g.location(in: view)
            let hits = view.hitTest(point, options: [
                .categoryBitMask: Self.itemCategory,
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
            ])
            var node: SCNNode? = hits.first?.node
            while let n = node, n.name == nil || UUID(uuidString: n.name ?? "") == nil {
                node = n.parent
            }
            if let name = node?.name, let id = UUID(uuidString: name), let item = itemsByID[id] {
                haptic.impactOccurred()
                haptic.prepare()
                onSelect(item)
            } else {
                onSelect(nil)
            }
        }

        // MARK: Frame loop

        @objc private func tick(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            let dt = Float(min(now - lastTick, 0.1))
            lastTick = now

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
            tiltNode.eulerAngles = SCNVector3(tiltX, tiltY, 0)
            applyRotation()

            if simActive { stepSim(iterations: 2) }
            if !edges.isEmpty {
                var sig: Float = 0
                for e in edges {
                    if let p = nodes[e.a]?.presentation.position { sig += p.x + p.y * 1.3 + p.z * 1.7 }
                    if let p = nodes[e.b]?.presentation.position { sig += p.x + p.y * 1.3 + p.z * 1.7 }
                }
                if sig != edgeSignature { edgeSignature = sig; edgesDirty = true }
            }
            if edgesDirty { rebuildEdgeGeometry() }
        }

        private func applyRotation() {
            contentNode.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        // MARK: Geometry helpers

        static func vector(dim: Int, value: Float) -> SCNVector3 {
            switch dim {
            case 0: SCNVector3(value, 0, 0)
            case 1: SCNVector3(0, value, 0)
            default: SCNVector3(0, 0, value)
            }
        }

        static func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        static func makeEdges(size: CGFloat, material: SCNMaterial) -> SCNGeometry {
            let h = Float(size / 2)
            var vertices: [SCNVector3] = []
            for x in [-h, h] { for y in [-h, h] { for z in [-h, h] { vertices.append(SCNVector3(x, y, z)) } } }
            // index = xi*4 + yi*2 + zi
            let indices: [UInt16] = [
                0, 1, 2, 3, 4, 5, 6, 7,   // z edges
                0, 2, 1, 3, 4, 6, 5, 7,   // y edges
                0, 4, 1, 5, 2, 6, 3, 7,   // x edges
            ]
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.materials = [material]
            return geometry
        }

        // MARK: Positioning

        static func position(for item: Item, axisCount: Int) -> SCNVector3 {
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
            return SCNVector3(unit[0] * extent, unit[1] * extent, unit[2] * extent)
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
