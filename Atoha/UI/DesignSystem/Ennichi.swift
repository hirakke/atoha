import SwiftUI

/// 縁日の飾り：画面の上の紅白の幕、吊った看板、お椀の札。

extension Theme {
    /// 時計の帯と幕の上の帯（暗い画面でも藍）
    static let bandUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x0B1020) : UIColor(hex: 0x1F2A44) }
    static var band: Color { Color(bandUIColor) }
}

/// 紅白の幕。裾は丸く波打つ。
struct AwningStrip: View {
    var height: CGFloat = 26

    var body: some View {
        let red = Theme.accent, white = Color.white
        Canvas { context, size in
            let w: CGFloat = 20
            let body = size.height - w / 2
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                var p = Path(CGRect(x: x, y: 0, width: w, height: body))
                p.addEllipse(in: CGRect(x: x, y: body - w / 2, width: w, height: w))
                context.fill(p, with: .color(i.isMultiple(of: 2) ? red : white))
                x += w
                i += 1
            }
        }
        .frame(height: height)
        .background(alignment: .top) { Theme.band.frame(height: 4) }
        .accessibilityHidden(true)
    }
}

extension View {
    /// 画面の上（時計の下）に紅白の幕をかける
    func awning() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            AwningStrip()
                .background { Theme.paper.ignoresSafeArea(edges: .top) }
        }
    }
}

/// 紐で吊った看板。画面の名前を出す。文字が大きいときは紐を外して左寄せの見出しにする。
struct HangingSign: View {
    let title: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Text(title).font(Theme.display(.largeTitle)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 96) {
                    Rectangle().fill(Theme.ink).frame(width: 3, height: 10)
                    Rectangle().fill(Theme.ink).frame(width: 3, height: 10)
                }
                Text(title)
                    .font(Theme.display(.title))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                    .background(Capsule().fill(Theme.ink).offset(x: Theme.shadow, y: Theme.shadow))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// お椀の札：今に入っている数を、お椀の絵と数で見せる。
struct BowlPlate: View {
    let filled: Int
    let capacity: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("お椀").atype(.small, color: .white).fontWeight(.bold)
            HStack(spacing: 6) {
                ForEach(0..<capacity, id: \.self) { index in
                    BowlIcon(filled: index < filled, width: 36, onDark: true)
                }
            }
            Spacer(minLength: 0)
            (Text("\(filled)").font(Theme.dot(.title2))
             + Text(" / \(capacity)").font(Theme.dot(.footnote)))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.band))
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent).offset(x: Theme.shadow, y: Theme.shadow))
        .accessibilityElement()
        .accessibilityLabel("お椀 \(capacity)つのうち \(filled)つ")
    }
}

/// 数の札（「水槽 18 / 20」など）。
struct CountPill: View {
    let label: String
    let count: Int
    let total: Int
    var alert = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(.caption, weight: .bold))
            (Text("\(count)").font(Theme.dot(.title3))
             + Text(" / \(total)").font(Theme.dot(.caption)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Capsule().fill(alert ? Theme.accent : Theme.band))
        .accessibilityElement()
        .accessibilityLabel("\(label) \(total)のうち \(count)")
    }
}

/// やめる候補の印（やりたくも、やらなきゃでもないもの）
struct ReleaseHint: View {
    var body: some View {
        Text("やめる候補")
            .atype(.small, color: Theme.quiet).fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.quiet, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
    }
}

/// ドットのアイコン（タブなど）。X のマスを塗った型抜きの画像を作る。
enum PixelIcon {
    static func image(_ rows: [String], cell: CGFloat = 3) -> UIImage {
        let w = rows.map(\.count).max() ?? 0, h = rows.count
        let size = CGSize(width: CGFloat(w) * cell, height: CGFloat(h) * cell)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    ctx.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
        }
        return img.withRenderingMode(.alwaysTemplate)
    }

    /// 今：金魚
    static let fish = image(["..XXX....", ".XXXXX.XX", "XXXXXXXX.", ".XXXXX.XX", "..XXX...."])
    /// あとで：水槽の波
    static let waves = image(["..XX..XX", "XX..XX..", "........", "..XX..XX", "XX..XX.."])
    /// 地図：上から見た池と軸
    static let pond = image(["..XXXXX..", ".X..X..X.", "X...X...X", "XXXXXXXXX", "X...X...X", ".X..X..X.", "..XXXXX.."])
}
