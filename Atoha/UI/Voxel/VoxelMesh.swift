import RealityKit
import UIKit
import simd

/// RealityKit には線のプリミティブが無いので、細い箱を 1 つのメッシュにまとめて線に見せる。
@MainActor
enum VoxelMesh {
    /// 軸に平行な箱をまとめて 1 つの MeshDescriptor にする。
    static func descriptor(boxes: [(center: SIMD3<Float>, half: SIMD3<Float>)]) -> MeshDescriptor {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(boxes.count * 8)
        indices.reserveCapacity(boxes.count * 36)
        // 各頂点は index = xi*4 + yi*2 + zi
        let faces: [UInt32] = [
            0, 1, 3, 0, 3, 2,   // -x
            4, 6, 7, 4, 7, 5,   // +x
            0, 4, 5, 0, 5, 1,   // -y
            2, 3, 7, 2, 7, 6,   // +y
            0, 2, 6, 0, 6, 4,   // -z
            1, 5, 7, 1, 7, 3,   // +z
        ]
        for b in boxes {
            let base = UInt32(positions.count)
            for xi in 0..<2 { for yi in 0..<2 { for zi in 0..<2 {
                positions.append(b.center + SIMD3(xi == 0 ? -b.half.x : b.half.x,
                                                  yi == 0 ? -b.half.y : b.half.y,
                                                  zi == 0 ? -b.half.z : b.half.z))
            } } }
            for f in faces { indices.append(base + f) }
        }
        var d = MeshDescriptor(name: "voxel-boxes")
        d.positions = MeshBuffers.Positions(positions)
        d.primitives = .triangles(indices)
        return d
    }

    /// 線分（a→b）を、断面 2*halfWidth の細い角柱として 1 つにまとめる。点線の 1 区間ぶん。
    static func descriptor(segments: [(a: SIMD3<Float>, b: SIMD3<Float>)], halfWidth: Float) -> MeshDescriptor {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(segments.count * 8)
        indices.reserveCapacity(segments.count * 36)
        // 頂点は index = end*4 + su*2 + sv
        let faces: [UInt32] = [
            0, 1, 3, 0, 3, 2,
            4, 5, 7, 4, 7, 6,
            0, 1, 5, 0, 5, 4,
            1, 3, 7, 1, 7, 5,
            3, 2, 6, 3, 6, 7,
            2, 0, 4, 2, 4, 6,
        ]
        for s in segments {
            let d = s.b - s.a
            let len = simd_length(d)
            guard len > 0.0001 else { continue }
            let dir = d / len
            let ref: SIMD3<Float> = abs(dir.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(dir, ref)) * halfWidth
            let v = simd_normalize(simd_cross(dir, u)) * halfWidth
            let base = UInt32(positions.count)
            for end in [s.a, s.b] { for su in [-1, 1] as [Float] { for sv in [-1, 1] as [Float] {
                positions.append(end + u * su + v * sv)
            } } }
            for f in faces { indices.append(base + f) }
        }
        var d = MeshDescriptor(name: "voxel-segments")
        d.positions = MeshBuffers.Positions(positions)
        d.primitives = .triangles(indices)
        return d
    }

    static func mesh(segments: [(a: SIMD3<Float>, b: SIMD3<Float>)], halfWidth: Float) -> MeshResource? {
        guard !segments.isEmpty else { return nil }
        return try? MeshResource.generate(from: [descriptor(segments: segments, halfWidth: halfWidth)])
    }

    static func mesh(boxes: [(center: SIMD3<Float>, half: SIMD3<Float>)]) -> MeshResource? {
        guard !boxes.isEmpty else { return nil }
        return try? MeshResource.generate(from: [descriptor(boxes: boxes)])
    }

    /// 直方体（半分の大きさ `half`）の 12 辺を、太さ `thickness` の細い箱として 1 メッシュにしたもの。
    static func wireBoxBoxes(half: SIMD3<Float>, thickness: Float) -> [(center: SIMD3<Float>, half: SIMD3<Float>)] {
        let t = thickness / 2
        var out: [(center: SIMD3<Float>, half: SIMD3<Float>)] = []
        for axis in 0..<3 {
            let a = (axis + 1) % 3, b = (axis + 2) % 3
            for sa in [-1, 1] as [Float] { for sb in [-1, 1] as [Float] {
                var c = SIMD3<Float>.zero
                c[a] = sa * half[a]
                c[b] = sb * half[b]
                var h = SIMD3<Float>(repeating: t)
                h[axis] = half[axis] + t
                out.append((c, h))
            } }
        }
        return out
    }

    static func wireBox(half: SIMD3<Float>, thickness: Float) -> MeshResource {
        mesh(boxes: wireBoxBoxes(half: half, thickness: thickness))!
    }

    /// 線が色で潰れないよう、両面描画の Unlit を作る。
    static func unlit(_ color: UIColor) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        m.faceCulling = .none
        return m
    }
}
