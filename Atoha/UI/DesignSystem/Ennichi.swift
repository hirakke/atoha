import SwiftUI

/// 縁日の飾り：画面の見出し、お椀の列、札。上の幕はやめて、時計の下は紙のままにする。

extension Theme {
    /// 藍の帯（名札や札の面。暗い画面でも藍）
    static let bandUIColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x0B1020) : UIColor(hex: 0x1F2A44) }
    static var band: Color { Color(bandUIColor) }
}

/// 画面の見出し。左寄せの大きな Dela Gothic One（約40pt、文字サイズの設定に合わせて大きくなる）。
struct ScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.custom("DelaGothicOne-Regular", size: 40, relativeTo: .largeTitle))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// 画面の上の一行：見出しの横に数などを並べ、右端にボタン（設定や表示）を置く。
struct ScreenHeader<Inline: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var inline: Inline
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ScreenTitle(title: title)
            inline.padding(.top, 6)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 46)
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, @ViewBuilder inline: () -> Inline) {
        self.init(title: title, inline: inline, trailing: { EmptyView() })
    }
}

/// 見出しの横の小さなお椀の列と数（「◯◯◯ 2 / 3」）
struct HeaderBowls: View {
    let filled: Int
    let capacity: Int

    /// 数が多いときは、1つずつを小さくする
    private var bowlWidth: CGFloat { capacity <= 3 ? 30 : capacity <= 5 ? 22 : 16 }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<capacity, id: \.self) { index in
                BowlIcon(filled: index < filled, width: bowlWidth, hollow: true)
            }
            CountText(count: filled, total: capacity, size: .body).padding(.leading, 6)
        }
        .accessibilityElement()
        .accessibilityLabel("お椀 \(capacity)つのうち \(filled)つ")
    }
}

/// 丸い枠のボタン（44pt）。設定の歯車など
struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 札の左上の小さな見出し（「次」「おすすめ」）。ドットの書体で紅く
struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.dot(.footnote))
            .tracking(1.3)
            .foregroundStyle(Theme.accent)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// 白い札：太い枠と、ずらした影（「次」は藍、「おすすめ」は紅）
    func boldCard(_ color: Color = Theme.ink) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return self
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(color, lineWidth: 2.5))
            .background(shape.fill(color).offset(x: Theme.shadow, y: Theme.shadow))
            .padding(.trailing, Theme.shadow)
            .padding(.bottom, Theme.shadow)
    }

    /// 行をまとめる白い札：薄い枠だけ（影なし）
    func quietCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return self
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.faint, lineWidth: 2))
    }
}

/// 札の中の行の区切り
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.faint.opacity(0.6)).frame(height: 1.5)
    }
}

/// 丸いボタン（枠や影のない紅の面、または藍の枠の白い面）。高さ44pt
struct PillButtonStyle: ButtonStyle {
    var filled = true
    var size: Font.TextStyle = .body
    var horizontal: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size, weight: .black))
            .foregroundStyle(filled ? Theme.onAccent : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .frame(minHeight: 44)
            .background {
                if filled {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().fill(Theme.surface).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .fixedSize()
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(filled: Bool = true, size: Font.TextStyle = .body, horizontal: CGFloat = 22) -> PillButtonStyle {
        PillButtonStyle(filled: filled, size: size, horizontal: horizontal)
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
    /// 池：上から見た池と軸
    static let pond = image(["..XXXXX..", ".X..X..X.", "X...X...X", "XXXXXXXXX", "X...X...X", ".X..X..X.", "..XXXXX.."])
}
