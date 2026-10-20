import SwiftUI
import SwiftData

/// 軸の画面。採用した軸、AIが出す候補、1週間のドット。
struct AxesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Axis.order) private var axes: [Axis]
    @Query(sort: \Item.createdAt) private var items: [Item]

    @State private var candidates: [AxisCandidate] = []
    @State private var loading = false
    @State private var newNegative = ""
    @State private var newPositive = ""

    private let maxAxes = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        axesSection
                        candidatesSection
                        weekSection
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("サンプルを入れる") { SampleData.insert(into: context) }
                        Button("軸を再計算") { AxisEngine.rescore(items: items, axes: axes); try? context.save() }
                    } label: {
                        Image(systemName: "ellipsis").atype(.small, color: Theme.quiet)
                    }
                }
            }
        }
    }

    private var axesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("軸")
            ForEach(axes) { axis in
                HStack {
                    Text(axis.negativePole)
                    Text("↔").atype(.body, color: Theme.quiet)
                    Text(axis.positivePole)
                    Spacer()
                    Button { remove(axis) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.cube(.quiet))
                    .accessibilityLabel("軸を外す")
                }
                .atype(.body)
                .padding(.vertical, 6)
            }
            if axes.count < maxAxes {
                Card(padding: 10) {
                    HStack(spacing: 8) {
                        TextField("一人で", text: $newNegative)
                        Text("↔").atype(.small, color: Theme.quiet)
                        TextField("人と", text: $newPositive)
                        Button("追加") {
                            adopt(negative: newNegative, positive: newPositive)
                            newNegative = ""; newPositive = ""
                        }
                        .buttonStyle(.cube(.secondary))
                        .disabled(newNegative.isEmpty || newPositive.isEmpty)
                    }
                    .atype(.small)
                    .textFieldStyle(.plain)
                }
            }
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("候補")
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else if axes.count < maxAxes {
                    Button {
                        Task { await suggest() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.cube(.quiet))
                    .accessibilityLabel("候補を出す")
                }
            }
            ForEach(candidates) { candidate in
                CandidateCard(candidate: candidate,
                              keep: { negative, positive in adopt(negative: negative, positive: positive); drop(candidate) },
                              reject: { drop(candidate) })
            }
        }
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("1週間")
            WeekDotStrip(days: WeekDotStrip.lastSevenDays(from: items))
        }
    }

    private func suggest() async {
        loading = true
        candidates = await AxisEngine.suggestCandidates(from: items, existing: axes)
        loading = false
    }

    private func adopt(negative: String, positive: String) {
        guard axes.count < maxAxes else { return }
        context.insert(Axis(negativePole: negative, positivePole: positive, order: (axes.map(\.order).max() ?? -1) + 1))
        try? context.save()
        rescoreAfterChange()
    }

    private func remove(_ axis: Axis) {
        context.delete(axis)
        try? context.save()
        rescoreAfterChange()
    }

    private func drop(_ candidate: AxisCandidate) {
        withAnimation { candidates.removeAll { $0.id == candidate.id } }
    }

    private func rescoreAfterChange() {
        let current = (try? context.fetch(FetchDescriptor<Axis>(sortBy: [SortDescriptor(\.order)]))) ?? []
        AxisEngine.rescore(items: items, axes: current)
        try? context.save()
    }
}

/// 軸の候補。仮の名前と、それぞれの極に寄った自分のメモを見せる。
/// 合う言葉がなかった候補は極が空で、本人が両側に名前を付ける。
private struct CandidateCard: View {
    let candidate: AxisCandidate
    let keep: (_ negative: String, _ positive: String) -> Void
    let reject: () -> Void

    @State private var negative = ""
    @State private var positive = ""

    private var unnamed: Bool { candidate.negativePole.isEmpty || candidate.positivePole.isEmpty }
    private var names: (String, String) {
        unnamed ? (negative.trimmingCharacters(in: .whitespaces), positive.trimmingCharacters(in: .whitespaces))
                : (candidate.negativePole, candidate.positivePole)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(unnamed ? "この違いは？" : "\(candidate.negativePole) ↔ \(candidate.positivePole)？")
                    .atype(.title)
                // それぞれの極に寄った自分のメモを並べて、どちらの自分かを見比べられるようにする
                side(candidate.negativePole, candidate.lowSamples, field: $negative)
                side(candidate.positivePole, candidate.highSamples, field: $positive)
                HStack(spacing: 8) {
                    Button("残す") { keep(names.0, names.1) }
                        .buttonStyle(.cube(.primary))
                        .disabled(names.0.isEmpty || names.1.isEmpty || names.0 == names.1)
                    Button("ちがう", action: reject)
                        .buttonStyle(.cube(.secondary))
                }
            }
        }
    }

    @ViewBuilder private func side(_ pole: String, _ texts: [String], field: Binding<String>) -> some View {
        if !texts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if unnamed {
                    TextField("こちらは", text: field)
                        .atype(.body)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.quiet.opacity(0.4)).frame(height: 1) }
                } else {
                    Text(pole).atype(.label, color: Theme.quiet)
                }
                ForEach(texts, id: \.self) { text in
                    HStack(spacing: 8) {
                        DotMark(kind: .concern, size: 8)
                        Text(text).atype(.small, color: Theme.quiet).lineLimit(1)
                    }
                }
            }
        }
    }
}
