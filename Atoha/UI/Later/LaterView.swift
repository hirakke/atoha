import SwiftUI
import SwiftData

/// あとで：回したもの（水槽の金魚）。いちばんのおすすめを札にして、残りは1つの箱に並べる。今に入れるかは本人が選ぶ。
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
                    VStack(alignment: .leading, spacing: 22) {
                        HangingSign(title: "あとで")
                        TankView(cubes: waiting.map { TankCube(id: $0.id, tint: GoldfishTint.of(want: $0.effectiveWant, must: $0.effectiveMust)) })
                            .overlay(alignment: .topTrailing) {
                                CountPill(label: "水槽", count: waiting.count, total: SettingsStore.laterCapacity,
                                          alert: waiting.count >= SettingsStore.laterCapacity)
                                    .padding(10)
                            }
                            .padding(.trailing, Theme.shadow)
                        if waiting.isEmpty {
                            Text("「あとでに回す」で入れたものが、ここで泳ぎます。")
                                .atype(.small, color: Theme.quiet)
                                .onPaper()
                        } else {
                            if let top = ordered.first {
                                RecommendCard(item: top, room: room).padding(.top, 10)
                            }
                            Text(room > 0 ? "今のお椀にすくえるのは、あと\(room)匹" : "お椀がいっぱいです。今のものが終わると、すくえます")
                                .atype(.small, color: Theme.quiet)
                            if ordered.count > 1 {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(ordered.dropFirst().enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { Rectangle().fill(Theme.faint).frame(height: 2) }
                                        SuggestionRow(item: item, room: room)
                                    }
                                }
                                .onPaper(padding: 14)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) { CaptureButton() }
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .awning()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// いちばんのおすすめ。紅い枠の札に「今に入れる」を大きく。
private struct RecommendCard: View {
    let item: Item
    let room: Int
    @State private var scooper = Scooper()
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                mark(item)
                Text(item.text).atype(.title).frame(maxWidth: .infinity, alignment: .leading)
                if item.isBothLow { ReleaseHint() }
            }
            Button("今に入れる") { scooper.scoop(item, room: room, in: context) }
                .buttonStyle(.cube(room == 0 ? .flat : .accent, fill: true))
                .opacity(room == 0 ? 0.55 : 1)
                .accessibilityHint(room == 0 ? "今がいっぱいです" : "")
        }
        .padding(.top, 20)
        .padding([.horizontal, .bottom], 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent, lineWidth: Theme.stroke))
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent).offset(x: Theme.shadow + 1, y: Theme.shadow + 1))
        .sticker("おすすめ")
    }
}

/// あとでの行。今に入れるかは本人が選ぶ。
private struct SuggestionRow: View {
    @Environment(\.modelContext) private var context
    let item: Item
    let room: Int
    @State private var scooper = Scooper()

    var body: some View {
        HStack(spacing: 12) {
            mark(item)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).atype(.body)
                HStack(spacing: 10) {
                    if item.isBothLow { ReleaseHint() }
                    // 水槽から出す（金魚を逃がす）。あとでの上限があるので、減らす手段として置く
                    Button { release() } label: {
                        Text("やめる").atype(.small, color: Theme.quiet).underline()
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)
            // いっぱいでも押せる。押すとポイが破れて、入らないことが伝わる
            Button("今に入れる") { scooper.scoop(item, room: room, in: context) }
                .buttonStyle(.cube(room == 0 ? .flat : .secondary))
                .opacity(room == 0 ? 0.55 : 1)
                .accessibilityHint(room == 0 ? "今がいっぱいです" : "")
        }
        .padding(.vertical, 6)
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
        DotMark(kind: item.kind, want: item.effectiveWant, must: item.effectiveMust, size: 14)
    } else {
        DotMark(kind: .concern, size: 14)
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
