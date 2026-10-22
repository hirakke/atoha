import SwiftUI
import SwiftData

/// あとで：回したもの（水槽の金魚）。いちばんのおすすめを札にして、残りは罫で区切った行を白い札にまとめる。今に入れるかは本人が選ぶ。
/// （いつ思い出すかの時間の区分は、わかりやすさのため一旦なくしている）
struct LaterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.createdAt) private var items: [Item]

    private var waiting: [Item] { items.filter { $0.state == .waiting } }
    /// 今にあと何件入れられるか
    private var room: Int { max(0, SettingsStore.nowCapacity - items.filter { $0.state == .returned }.count) }
    /// おすすめ順（優先順位の高い順）
    private var ordered: [Item] {
        let now = Date.now
        return waiting.sorted { $0.priority(now: now) > $1.priority(now: now) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground(fadeTop: true)
                VStack(spacing: 0) {
                    ScreenHeader(title: "あとで") {
                        CountText(count: waiting.count, total: SettingsStore.laterCapacity, size: .body,
                                  alert: waiting.count >= SettingsStore.laterCapacity)
                            .accessibilityLabel("水槽 \(SettingsStore.laterCapacity)のうち \(waiting.count)")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TankView(cubes: waiting.map { TankCube(id: $0.id, tint: GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust)) })
                            if waiting.isEmpty {
                                Text("「あとでに回す」で入れたものが、ここで泳ぎます。")
                                    .atype(.small, color: Theme.quiet)
                                    .padding(.horizontal, 4)
                            } else {
                                if let top = ordered.first {
                                    RecommendCard(item: top, room: room)
                                }
                                if room == 0 {
                                    Text("お椀がいっぱいです。今のものが終わると、すくえます")
                                        .atype(.small, color: Theme.quiet)
                                        .padding(.horizontal, 4)
                                }
                                if ordered.count > 1 {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(ordered.dropFirst().enumerated()), id: \.element.id) { index, item in
                                            if index > 0 { RowDivider() }
                                            SuggestionRow(item: item, room: room)
                                        }
                                    }
                                    .quietCard()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                }
                .safeAreaInset(edge: .bottom) { CaptureButton() }
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// いちばんのおすすめ。白い札に紅い枠と影、左上に小さく「おすすめ」。1行で「今に入れる」。文字が大きいときはボタンを下に回す。
private struct RecommendCard: View {
    let item: Item
    let room: Int
    @State private var scooper = Scooper()
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "おすすめ")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    label
                    button
                }
                VStack(alignment: .leading, spacing: 12) {
                    label
                    button.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.top, 14)
        .padding(.leading, 16)
        .padding([.trailing, .bottom], 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boldCard(Theme.accent)
    }

    private var label: some View {
        HStack(spacing: 12) {
            mark(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).font(.system(.headline, weight: .black)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if item.isBothLow { ReleaseHint() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var button: some View {
        Button("今に入れる") { scooper.scoop(item, room: room, in: context) }
            .buttonStyle(.pill(size: .subheadline, horizontal: 16))
            .opacity(room == 0 ? 0.45 : 1)
            .accessibilityHint(room == 0 ? "今がいっぱいです" : "")
    }
}

/// あとでの行。押すと開いて「今に入れる」「やめる」が出る。今に入れるかは本人が選ぶ。
private struct SuggestionRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    let room: Int
    @State private var scooper = Scooper()
    @State private var open = false

    private var faint: Bool { item.isRated && GoldfishTint.of(want: item.effectiveWant, must: item.effectiveMust) == .faint }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                mark(item)
                Text(item.text).atype(.body, color: faint ? Theme.quiet : nil).fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isBothLow { ReleaseHint() }
                RowChevron(open: open)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(open ? "閉じる" : "今に入れる・やめるを出す")

            if open {
                FlowRow {
                    // いっぱいでも押せる。押すとポイが破れて、入らないことが伝わる
                    Button("今に入れる") { scooper.scoop(item, room: room, in: context) }
                        .buttonStyle(.cube(room == 0 ? .flat : .accent))
                        .environment(\.atypeInk, nil)
                        .opacity(room == 0 ? 0.55 : 1)
                        .accessibilityHint(room == 0 ? "今がいっぱいです" : "")
                    // 水槽から出す（金魚を逃がす）。あとでの上限があるので、減らす手段として置く
                    Button("やめる") { release() }
                        .buttonStyle(.cube(item.isBothLow ? .primary : .secondary))
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    /// あとでから外す（やめる）。金魚は川へ逃がす
    private func release() {
        guard !scooper.busy else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            item.state = .released
            item.resolvedAt = .now
            ReturnService.sync(in: context)
        }
    }
}

@ViewBuilder private func mark(_ item: Item) -> some View {
    if item.isRated {
        DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 15)
    } else {
        DotMark(kind: .concern, size: 15)
    }
}

/// 水槽でポイを動かしてから、今に入れる。いっぱいならポイが破れて終わる。
@Observable
private final class Scooper {
    var busy = false

    @MainActor
    func scoop(_ item: Item, room: Int, in context: ModelContext) {
        guard !busy else { return }
        busy = true
        if room > 0 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            TankScene.current?.scoop(item.id, success: true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()  // お椀に「ぽちゃ」
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation { _ = ReturnService.accept(item, in: context) }
                self.busy = false
            }
        } else {
            TankScene.current?.scoop(item.id, success: false)
            Task { @MainActor in
                let haptic = UIImpactFeedbackGenerator(style: .rigid)
                try? await Task.sleep(for: .milliseconds(400))
                haptic.impactOccurred()
                try? await Task.sleep(for: .milliseconds(120))
                haptic.impactOccurred()
                try? await Task.sleep(for: .milliseconds(400))
                self.busy = false
            }
        }
    }
}
