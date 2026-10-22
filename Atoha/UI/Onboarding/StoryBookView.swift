import SwiftUI

/// 初めて開いたときの絵本：金魚のものがたり。文は見出しと一行だけにして、絵の矢印と名札で流れを見せる。
struct StoryBookView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let title: String
        let line: String
        let art: AnyView
        let caption: String
    }

    private var pages: [Page] {
        [
            Page(title: "忘れても、水槽が覚えている", line: "金魚は三秒で忘れる、と言われます。",
                 art: AnyView(ForgetArt()), caption: "頭の中の予定は三秒で消える。水槽に入れておけば残る"),
            Page(title: "思いついたら、水槽へ", line: "小さな稚魚が一匹、生まれます。",
                 art: AnyView(ReleaseArt()), caption: "ひらめきが稚魚になり、あとでの水槽に入る。やめたものは川へ"),
            Page(title: "気持ちを付けると、色が出る", line: "本物の金魚も、育つと色が出ます。",
                 art: AnyView(ColorArt()), caption: "やりたい・やらなきゃを付けると、稚魚に色が出る"),
            Page(title: "選んで、すくう", line: "お椀は三つ。全部はすくえません。",
                 art: AnyView(ScoopArt()), caption: "あとでの水槽から一匹すくって、今のお椀に入れる"),
            Page(title: "できたら、持ち帰る", line: "お椀がひとつ、空きました。",
                 art: AnyView(TakeHomeArt()), caption: "できたら袋に入れて持ち帰る。まだならお椀で待つ"),
            Page(title: "池を見ると、自分が見える", line: "金魚は本当は、ちゃんと覚えています。",
                 art: AnyView(PondArt()), caption: "地図の池に、持ち帰った金魚が集まる場所が自分の傾向"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(page + 1) / \(pages.count)").font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.quiet)
                Spacer()
                if page < pages.count - 1 {
                    Button("スキップ") { onFinish() }.buttonStyle(.cube(.quiet))
                }
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 52)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            p.art
                                .frame(maxWidth: .infinity, minHeight: 260)
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.ink, lineWidth: Theme.stroke))
                                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.ink).offset(x: Theme.shadow + 1, y: Theme.shadow + 1))
                                .accessibilityElement()
                                .accessibilityLabel(p.caption)
                            Text(p.title).font(Theme.display(.title2)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text(p.line).atype(.body, color: Theme.quiet)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.accent : Theme.faint)
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(pages.count)ページ中\(page + 1)ページ目")
                Button(page == pages.count - 1 ? "はじめる" : "次へ") {
                    if page == pages.count - 1 { onFinish() } else { withAnimation { page += 1 } }
                }
                .buttonStyle(.cube(page == pages.count - 1 ? .accent : .primary, size: .large, fill: true))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .awning()
    }
}

// MARK: - 絵

/// 矢印（紅）
private struct Arrow: View {
    var angle: Angle = .zero
    var body: some View {
        Image(systemName: "arrow.right").font(.system(size: 22, weight: .black)).foregroundStyle(Theme.accent)
            .rotationEffect(angle)
    }
}

/// 画面の名札（あとで・今・地図）
private struct NameTag: View {
    let text: String
    var color: Color = Theme.band
    var body: some View {
        Text(text).font(.system(.footnote, weight: .black)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

/// 小さな水槽（網点の水と金魚）
private struct MiniTank<Content: View>: View {
    var width: CGFloat = 140
    var height: CGFloat = 80
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Theme.water)
            DotsFill().clipShape(RoundedRectangle(cornerRadius: 10))
            content
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 2.5))
    }
}

private struct DotsFill: View {
    var alpha = 0.16
    var body: some View {
        let ink = Theme.ink
        Canvas { context, size in
            var p = Path()
            var y: CGFloat = 4, row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 3 : 7
                while x < size.width { p.addRect(CGRect(x: x, y: y, width: 1.6, height: 1.6)); x += 8 }
                y += 4; row += 1
            }
            context.fill(p, with: .color(ink.opacity(alpha)))
        }
    }
}

private struct ForgetArt: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                GoldfishMark(color: Theme.accent, width: 48)
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Theme.ink).frame(width: 110, height: 8)
                    Capsule().fill(Theme.ink.opacity(0.4)).frame(width: 84, height: 8)
                    Capsule().fill(Theme.ink.opacity(0.12)).frame(width: 60, height: 8)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    Text("3").font(.system(.title2, design: .monospaced, weight: .black)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.accent))
                        .offset(x: 14, y: -14)
                }
            }
            Arrow(angle: .degrees(90))
            HStack(spacing: 10) {
                MiniTank(width: 150, height: 70) {
                    HStack(spacing: 14) {
                        GoldfishMark(color: Theme.accent, width: 30)
                        GoldfishMark(color: Theme.ink, style: .fry, width: 30)
                    }
                }
                NameTag(text: "あとで")
            }
        }
    }
}

private struct ReleaseArt: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.max").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.ink)
                Arrow()
                GoldfishMark(color: Theme.ink, style: .fry, width: 40)
                Arrow()
                VStack(spacing: 6) {
                    MiniTank(width: 110, height: 70) {
                        VStack(spacing: 6) {
                            GoldfishMark(color: Theme.accent, width: 24)
                            HStack { GoldfishMark(color: Theme.ink, width: 24); GoldfishMark(tint: .both, width: 24) }
                        }
                    }
                    NameTag(text: "あとで 18/20")
                }
            }
            Rectangle().fill(Theme.faint).frame(height: 2)
            HStack(spacing: 10) {
                Text("やめる → 川へ").atype(.small, color: Theme.quiet).fontWeight(.black)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Theme.quiet, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                Image(systemName: "water.waves").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.4))
                GoldfishMark(tint: .faint, width: 30).scaleEffect(x: -1)
            }
        }
    }
}

private struct ColorArt: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 2))
                    Path { p in p.move(to: CGPoint(x: 50, y: 6)); p.addLine(to: CGPoint(x: 50, y: 94)); p.move(to: CGPoint(x: 6, y: 50)); p.addLine(to: CGPoint(x: 94, y: 50)) }
                        .stroke(Theme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    Circle().fill(Theme.accent).frame(width: 14, height: 14).offset(x: 22, y: 20)
                    Circle().fill(Theme.accent.opacity(0.2)).frame(width: 32, height: 32).offset(x: 13, y: 11)
                    Text("↑やりたい").font(.system(.caption2, weight: .black)).foregroundStyle(Theme.ink).offset(x: 4, y: -18)
                    Text("やらなきゃ→").font(.system(.caption2, weight: .black)).foregroundStyle(Theme.ink).offset(x: 34, y: 102)
                }
                .frame(width: 100, height: 100)
                GoldfishMark(color: Theme.ink, style: .fry, width: 36)
                Arrow()
                GoldfishMark(color: Theme.accent, width: 56)
            }
            .padding(.top, 10)
            Rectangle().fill(Theme.faint).frame(height: 2)
            HStack(spacing: 14) {
                ForEach([GoldfishTint.red, .black, .both, .faint], id: \.self) { t in
                    VStack(spacing: 4) {
                        GoldfishMark(tint: t, width: 34)
                        Text(t.label).font(.system(.caption2, weight: .black)).foregroundStyle(t == .faint ? Theme.quiet : Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }
}

private struct ScoopArt: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    MiniTank(width: 110, height: 90) {
                        VStack(spacing: 8) {
                            GoldfishMark(color: Theme.ink, width: 24)
                            HStack { GoldfishMark(color: Theme.ink, style: .fry, width: 22); GoldfishMark(tint: .faint, width: 22) }
                        }
                        .padding(.top, 20)
                    }
                    // ぽい
                    ZStack {
                        Circle().fill(Theme.surface.opacity(0.9)).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                        GoldfishMark(color: Theme.accent, width: 28)
                    }
                    .frame(width: 50, height: 50)
                    .offset(x: 24, y: -36)
                }
                NameTag(text: "あとで")
            }
            Arrow(angle: .degrees(-20)).padding(.bottom, 60)
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    BowlIcon(filled: true, width: 34)
                    BowlIcon(filled: true, width: 34)
                    BowlIcon(filled: false, width: 34)
                        .overlay(alignment: .top) { Image(systemName: "arrow.down").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.accent).offset(y: -16) }
                }
                NameTag(text: "今 2→3", color: Theme.accent)
            }
        }
        .padding(.top, 30)
    }
}

private struct TakeHomeArt: View {
    @State private var lift = false
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(spacing: 10) {
                    Label("できた", systemImage: "checkmark").font(.system(.subheadline, weight: .black)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                    BowlIcon(filled: false, width: 50)
                }
                Arrow(angle: .degrees(-45)).padding(.bottom, 30)
                BagIcon(tint: .red, width: 60)
                    .offset(y: lift ? -10 : 0)
                    .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { lift = true } }
            }
            Rectangle().fill(Theme.faint).frame(height: 2)
            HStack(spacing: 10) {
                Text("まだ").atype(.small).fontWeight(.black)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                Arrow()
                BowlIcon(filled: true, width: 44)
                Text("お椀で待つ").atype(.small, color: Theme.quiet).fontWeight(.bold)
            }
        }
    }
}

private struct PondArt: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.water)
                DotsFill(alpha: 0.12).clipShape(RoundedRectangle(cornerRadius: 22))
                Path { p in p.move(to: CGPoint(x: 120, y: 10)); p.addLine(to: CGPoint(x: 120, y: 170)); p.move(to: CGPoint(x: 14, y: 90)); p.addLine(to: CGPoint(x: 226, y: 90)) }
                    .stroke(Theme.ink, lineWidth: 2)
                GoldfishMark(color: Theme.accent, width: 30).offset(x: -70, y: -50)
                GoldfishMark(color: Theme.ink, width: 24).offset(x: -40, y: -20)
                GoldfishMark(color: Theme.ink, style: .fry, width: 22).offset(x: -60, y: 40)
                Circle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                    .frame(width: 100, height: 100).offset(x: 60, y: 36)
                GoldfishMark(color: Theme.ink, style: .takenHome, width: 30).offset(x: 44, y: 22)
                GoldfishMark(color: Theme.ink, style: .takenHome, width: 30).offset(x: 78, y: 40)
                GoldfishMark(color: Theme.ink, style: .takenHome, width: 26).offset(x: 52, y: 58)
                GoldfishMark(color: Theme.ink, style: .takenHome, width: 22).offset(x: 72, y: 14)
                Text("人と").font(.system(.caption, weight: .black)).foregroundStyle(Theme.ink).offset(x: 100, y: 74)
                Text("作る").font(.system(.caption, weight: .black)).foregroundStyle(Theme.ink).offset(x: 16, y: 80)
            }
            .frame(width: 240, height: 180)
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.ink, lineWidth: 2.5))
            NameTag(text: "地図")
        }
    }
}
