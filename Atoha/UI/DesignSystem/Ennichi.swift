import SwiftUI

/// 縁日の飾り：画面の上の紅白の幕、見出し、お椀の列。

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

/// 画面の見出し。左寄せの Dela Gothic One（吊った看板はやめて、すっきり見せる）。
struct ScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.display(.title))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// お椀の列：今に入っている数を、ドットのお椀を並べて見せる（「お椀 ◯◯◯ 2 / 3」）。
struct BowlLine: View {
    let filled: Int
    let capacity: Int

    /// 数が多いときは、1つずつを小さくして1行に収める
    private var bowlWidth: CGFloat { capacity <= 3 ? 42 : capacity <= 5 ? 32 : 24 }

    var body: some View {
        HStack(spacing: 12) {
            Text("お椀").font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.quiet)
            HStack(spacing: bowlWidth / 12) {
                ForEach(0..<capacity, id: \.self) { index in
                    BowlIcon(filled: index < filled, width: bowlWidth)
                }
            }
            Spacer(minLength: 0)
            CountText(count: filled, total: capacity, size: .title2)
        }
        .accessibilityElement()
        .accessibilityLabel("お椀 \(capacity)つのうち \(filled)つ")
    }
}

/// 数（「17 / 20」）。ドットの書体で、分母は小さく控えめに。
struct CountText: View {
    let count: Int
    let total: Int
    var size: Font.TextStyle = .title3
    var alert = false

    private var small: Font.TextStyle { size == .title2 ? .subheadline : .footnote }

    var body: some View {
        (Text("\(count)").font(Theme.dot(size)).foregroundStyle(alert ? Theme.accent : Theme.ink)
         + Text(" / \(total)").font(Theme.dot(small)).foregroundStyle(Theme.quiet))
            .lineLimit(1)
            .fixedSize()
    }
}

/// 行の右の小さな矢印（押すと開く）。開いているときは下を向く
struct RowChevron: View {
    var open = false

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(Theme.quiet.opacity(0.8))
            .rotationEffect(.degrees(open ? 90 : 0))
            .accessibilityHidden(true)
    }
}

/// やめる候補の印（やりたくも、やらなきゃでもないもの）
struct ReleaseHint: View {
    var body: some View {
        Text("やめる候補")
            .atype(.small, color: Theme.quiet).fontWeight(.bold)
            .lineLimit(1)
            .fixedSize()
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
