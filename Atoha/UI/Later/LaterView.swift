import SwiftUI
import SwiftData

/// あとで：回したものを、おすすめ順に1つのリストで並べる。今に入れるかは本人が選ぶ。
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
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        TankView(cubes: waiting.map { TankCube(id: $0.id, tint: GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust)) })
                        if waiting.isEmpty {
                            Text("「あとでに回す」で入れたものが、ここに並びます。")
                                .atype(.small, color: Theme.quiet)
                                .onPaper()
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("おすすめ順")
                                Text(room > 0 ? "今に入れられるのはあと\(room)匹" : "今がいっぱいです。今のものが終わると入れられます")
                                    .atype(.label).padding(.bottom, 6)
                                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                                    SuggestionRow(item: item, top: index == 0, room: room)
                                }
                            }
                            .onPaper(padding: 14)
                        }
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .bottom) { CaptureButton() }
                // タブバーの下の白いぼかしを消して、方眼を最後まで見せる
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .paperStatusBar()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("あとで").atype(.display)
            Text("\(waiting.count)匹").atype(.label)
            Spacer()
            // すくった金魚が入る先（今のお椀）
            HStack(spacing: 4) {
                ForEach(0..<SettingsStore.nowCapacity, id: \.self) { index in
                    BowlIcon(filled: index < SettingsStore.nowCapacity - room, width: 22)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("今 \(SettingsStore.nowCapacity - room) / \(SettingsStore.nowCapacity)")
        }
    }
}

/// あとでの行。おすすめ順に並び、今に入れるかは本人が選ぶ。
private struct SuggestionRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    /// いちばんのおすすめ
    let top: Bool
    let room: Int
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isRated {
                    DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 10)
                } else {
                    DotMark(kind: .concern, size: 10)
                }
            }
            .padding(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).atype(.body)
                if top { Text("おすすめ").atype(.label, color: Theme.accent) }
            }
            Spacer(minLength: 8)
            // いっぱいでも押せる。押すとポイが破れて、入らないことが伝わる
            Button("今に入れる") { scoop() }
                .buttonStyle(.cube(room == 0 ? .flat : (top ? .accent : .secondary)))
                .opacity(room == 0 ? 0.55 : 1)
                .accessibilityHint(room == 0 ? "今がいっぱいです" : "")
        }
        .padding(.vertical, 4)
    }

    /// 水槽でポイを動かしてから、今に入れる。いっぱいならポイが破れて終わる。
    private func scoop() {
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
                busy = false
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
                busy = false
            }
        }
    }
}
