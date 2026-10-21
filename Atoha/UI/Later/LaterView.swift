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
                        TankView(cubes: waiting.map { TankCube(id: $0.id, accent: $0.isRated && $0.effectiveWant >= 0.5) })
                        if waiting.isEmpty {
                            Text("「あとでに回す」で入れたものが、ここに並びます。")
                                .atype(.small, color: Theme.quiet)
                                .onPaper()
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("おすすめ順")
                                Text(room > 0 ? "今に入れられるのはあと\(room)件" : "今がいっぱいです。今のものが終わると入れられます")
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
            Text("\(waiting.count)").atype(.label)
            Spacer()
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
            Button("今に入れる") {
                withAnimation { _ = ReturnService.accept(item, in: context) }
            }
            .buttonStyle(.cube(top ? .accent : .secondary))
            .disabled(room == 0)
        }
        .padding(.vertical, 4)
    }
}
