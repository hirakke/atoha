import SwiftUI
import SwiftData

/// 書き出し画面「あとでに回す」。書く → （気持ちを付ける：つけなくてもいい） → 水槽に放す。
/// 放したあとは、閉じるか続けて回すかを本人が選ぶ。水槽がいっぱいなら、書いたものは残したまま知らせる。
/// いつ思い出すかの時間設定は、わかりやすさのため一旦なくしている（ReturnTiming は残してある）。
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Axis.order) private var axes: [Axis]

    /// 画面の段階
    enum Phase { case write, feel, done, full }

    @State private var phase: Phase = .write
    @State private var text = ""
    /// 時間は決めない。「あとで」から自分で選んで今に入れる
    private let timing: ReturnTiming = .atBreak
    // 任意：預けるときに付けてもよい。付けなければ nil のまま
    @State private var want: Double?
    @State private var must: Double?
    /// 水槽（あとで）に入っている数
    @State private var count = 0

    private var capacity: Int { SettingsStore.laterCapacity }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            PaperBackground(fadeTop: true)
            VStack(spacing: 0) {
                header
                switch phase {
                case .write: writeBody
                case .feel: feelBody.transition(.opacity)
                case .done: doneBody.transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .full: fullBody.transition(.opacity)
                }
            }
        }
        .onAppear(perform: start)
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("あとでに回す")
                    .font(.custom("DelaGothicOne-Regular", size: 30, relativeTo: .title))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                CircleIconButton(systemName: "xmark", label: "閉じる") { dismiss() }
            }
            if phase == .write {
                // 水槽の残り（「水槽 17 / 20　あと3匹 入ります」）
                HStack(spacing: 8) {
                    Image(uiImage: PixelIcon.waves)
                        .resizable().interpolation(.none)
                        .frame(width: 18, height: 11)
                        .foregroundStyle(Theme.waterDot)
                    (Text("水槽 \(count)").font(Theme.dot(.subheadline))
                     + Text(" / \(capacity)").font(Theme.dot(.caption)))
                    Text("あと\(max(0, capacity - count))匹 入ります")
                        .font(.system(.footnote, weight: .bold))
                }
                .foregroundStyle(Theme.quiet)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("水槽 \(capacity)のうち \(count)。あと\(max(0, capacity - count))匹 入ります")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: 1 書く

    private var writeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            CaptureField(text: $text, onSubmit: submit)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .boldCard()

            HStack(spacing: 10) {
                Button(action: openFeeling) {
                    HStack(spacing: 8) {
                        if let want, let must {
                            GoldfishMark(tint: GoldfishTint.of(want: want, must: must), width: 20)
                        } else {
                            PadIcon()
                        }
                        Text("気持ちを付ける")
                    }
                }
                .buttonStyle(CaptureButtonStyle(kind: .chip))
                .accessibilityValue(feelingLabel ?? "")

                Text(feelingLabel ?? "つけなくてもいい")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.quiet)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            releaseButton
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// 付けた気持ちの名前（付けていなければ nil）
    private var feelingLabel: String? {
        guard let want, let must else { return nil }
        return GoldfishTint.of(want: want, must: must).label
    }

    // MARK: 2 気持ちを付ける

    private var feelBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 書いたものを小さく。押すと書く段階へ戻る
            Button { withAnimation(.easeOut(duration: 0.15)) { phase = .write } } label: {
                HStack(spacing: 10) {
                    Text(trimmed.isEmpty ? "気になっていること" : trimmed)
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(trimmed.isEmpty ? Theme.quiet : Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("書きなおす")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.quiet)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.faint, lineWidth: 2))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trimmed)
            .accessibilityHint("書きなおす")

            VStack(alignment: .leading, spacing: 12) {
                Text("指で置く")
                    .font(Theme.dot(.footnote))
                    .tracking(1)
                    .foregroundStyle(Theme.quiet)
                    .accessibilityHidden(true)
                WantMustBoard(want: $want, must: $must)
                readout
            }
            .padding(18)
            .boldCard()

            Spacer(minLength: 0)

            releaseButton
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// パッドの下の読み：金魚と色の名前、控えめな一言
    private var readout: some View {
        HStack(spacing: 10) {
            if let want, let must {
                let tint = GoldfishTint.of(want: want, must: must)
                GoldfishMark(tint: tint, width: 27)
                Text(tint.label).font(.system(.body, weight: .black)).foregroundStyle(Theme.ink)
                Text(WantMustBoard.qualifier(tint)).font(.system(.footnote, weight: .bold)).foregroundStyle(Theme.quiet)
            } else {
                GoldfishMark(color: Theme.ink, style: .fry, width: 27)
                Text("まだ置いていません").font(.system(.footnote, weight: .bold)).foregroundStyle(Theme.quiet)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: 3 放したあと

    private var doneBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 22) {
                MiniTank(content: .entering)
                    .accessibilityLabel("稚魚が水槽に入ったところ")
                VStack(spacing: 8) {
                    Text("水槽に放しました")
                        .font(.system(.title2, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("「あとで」から選んで、\n今に入れられます。")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.quiet)
                        .lineSpacing(4)
                    (Text("水槽 \(count)").font(Theme.dot(.subheadline))
                     + Text(" / \(capacity)").font(Theme.dot(.caption)))
                        .foregroundStyle(Theme.quiet)
                        .accessibilityLabel("水槽 \(capacity)のうち \(count)")
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                Button("閉じる") { dismiss() }
                    .buttonStyle(CaptureButtonStyle(kind: .primary))
                Button("続けて回す", action: again)
                    .buttonStyle(CaptureButtonStyle(kind: .outline))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: 4 水槽がいっぱい

    private var fullBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 22) {
                MiniTank(content: .full)
                    .overlay(alignment: .topTrailing) {
                        (Text("\(count)").font(Theme.dot(.body)) + Text(" / \(capacity)").font(Theme.dot(.caption)))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                            .padding(10)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("金魚でいっぱいの水槽。\(capacity)のうち \(count)")
                VStack(spacing: 8) {
                    Text("水槽がいっぱいです")
                        .font(.system(.title2, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("「あとで」で今に入れるか、\nやめるものを選ぶと、また回せます。")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.quiet)
                        .lineSpacing(4)
                }
                .multilineTextAlignment(.center)
                if !trimmed.isEmpty {
                    // 書いたものは消さずに残しておく
                    HStack(spacing: 10) {
                        GoldfishMark(color: Theme.ink, style: .fry, width: 22)
                        Text("書いた「\(trimmed)」は、このまま残しておきます")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(Theme.ink.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.faint, lineWidth: 2))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                Button("「あとで」を開く") {
                    AppRouter.shared.tab = "later"
                    dismiss()
                }
                .buttonStyle(CaptureButtonStyle(kind: .primary))
                Button("閉じる") { dismiss() }
                    .buttonStyle(CaptureButtonStyle(kind: .outline))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: ボタンと動き

    /// 「水槽に放す」。藍の面に白い稚魚、紅いずらした影
    private var releaseButton: some View {
        Button(action: submit) {
            HStack(spacing: 10) {
                GoldfishMark(color: Theme.paper, style: .fry, width: 22)
                Text("水槽に放す")
            }
        }
        .buttonStyle(CaptureButtonStyle(kind: .primary))
        .disabled(trimmed.isEmpty)
    }

    private func start() {
        count = ReturnService.laterCount(in: context)
        if ReturnService.laterRoom(in: context) == 0 { phase = .full }
        #if DEBUG
        // 見た目の確認用（保存はしない）
        switch DebugLaunch.captureState {
        case "write": text = "美術館の企画展を見に行く"
        case "pad": text = "美術館の企画展を見に行く"; want = 0.8; must = 0.25; phase = .feel
        case "done": phase = .done
        case "full": text = "美術館の企画展を見に行く"; count = capacity; phase = .full
        default: break
        }
        #endif
    }

    private func openFeeling() {
        FocusingTextView.current?.commitMarkedText()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeOut(duration: 0.2)) { phase = .feel }
    }

    /// 続けて回す：空の書く段階に戻す
    private func again() {
        text = ""
        want = nil
        must = nil
        count = ReturnService.laterCount(in: context)
        withAnimation(.easeOut(duration: 0.2)) {
            phase = ReturnService.laterRoom(in: context) == 0 ? .full : .write
        }
    }

    private func submit() {
        FocusingTextView.current?.commitMarkedText()
        let trimmed = trimmed
        guard !trimmed.isEmpty, phase == .write || phase == .feel else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // 水槽がいっぱいなら回さない。書いたものは残したまま知らせる
        guard ReturnService.laterRoom(in: context) > 0 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            count = ReturnService.laterCount(in: context)
            withAnimation(.easeOut(duration: 0.2)) { phase = .full }
            return
        }

        let item = Item(text: trimmed, timing: timing)
        item.want = want
        item.must = must
        context.insert(item)
        try? context.save()
        if let date = item.returnAt { NotificationScheduler.reschedule(for: date, in: context) }
        LiveActivityService.sync(in: context)

        let axes = axes
        Task { @MainActor in
            await ItemProcessor.process(item, axes: axes)
            try? context.save()
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        count = ReturnService.laterCount(in: context)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { phase = .done }
    }
}

// MARK: - 部品

/// 書き出し画面の丸いボタン。藍の面（54pt、紅い影）・藍の枠の白い面（48pt）・小さな枠の札（44pt）
private struct CaptureButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, chip }
    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            let shift: CGFloat = kind == .primary && pressed ? Theme.shadow : 0
            configuration.label
                .font(.system(kind == .primary ? .body : .subheadline, weight: .black))
                .foregroundStyle(kind == .primary ? Theme.paper : Theme.ink)
                .lineLimit(1)
                .padding(.leading, kind == .chip ? 12 : 22)
                .padding(.trailing, kind == .chip ? 16 : 22)
                .frame(maxWidth: kind == .chip ? nil : .infinity,
                       minHeight: kind == .primary ? 54 : kind == .outline ? 48 : 44)
                .background {
                    if kind == .primary {
                        Capsule().fill(Theme.ink)
                    } else {
                        Capsule().fill(Theme.surface).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                    }
                }
                .offset(x: shift, y: shift)
                .background {
                    if kind == .primary { Capsule().fill(Theme.accent).offset(x: Theme.shadow, y: Theme.shadow) }
                }
                .padding(.trailing, kind == .primary ? Theme.shadow : 0)
                .padding(.bottom, kind == .primary ? Theme.shadow : 0)
                .contentShape(Capsule())
                .opacity(isEnabled ? (kind != .primary && pressed ? 0.7 : 1) : 0.4)
                .animation(.easeOut(duration: 0.08), value: pressed)
                .onChange(of: pressed) { _, now in
                    if now { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
        }
    }
}

/// 「気持ちを付ける」の小さな絵：枠と点線の十字、左上に紅い点
private struct PadIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 2)
            Path { p in
                p.move(to: CGPoint(x: 9, y: 3)); p.addLine(to: CGPoint(x: 9, y: 15))
                p.move(to: CGPoint(x: 3, y: 9)); p.addLine(to: CGPoint(x: 15, y: 9))
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.4, dash: [1.6, 1.8]))
            Circle().fill(Theme.accent).frame(width: 4.4, height: 4.4).position(x: 6, y: 6)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// 小さな水槽：薄い水色に青の網点、底に深い帯。稚魚が入ってくるところか、いっぱいの様子を描く
private struct MiniTank: View {
    enum Content { case entering, full }
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = false

    /// 絵の基準の大きさ（デザインの 320×168）。横は幅に合わせて伸ばし、縦は高さのまま
    private let base = CGSize(width: 320, height: 168)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        GeometryReader { proxy in
            let sx = proxy.size.width / base.width
            ZStack(alignment: .topLeading) {
                water
                switch content {
                case .entering: entering(sx: sx)
                case .full: fullFish(sx: sx)
                }
            }
        }
        .frame(height: base.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2.5))
        .onAppear {
            guard content == .entering else { return }
            if reduceMotion { dropped = true } else {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) { dropped = true }
            }
        }
    }

    /// 水の面と網点（浅いところは薄く、底の帯は濃く）
    private var water: some View {
        let dot = Theme.waterDot
        return Canvas { context, size in
            let deepTop = size.height - 40
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.water))
            context.fill(Path(CGRect(x: 0, y: deepTop, width: size.width, height: 40)), with: .color(dot.opacity(0.06)))
            var shallow = Path(), deep = Path()
            var y: CGFloat = 1.5, row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 1.5 : 4.5
                while x < size.width {
                    if y >= deepTop {
                        deep.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
                    } else {
                        shallow.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    }
                    x += 6
                }
                y += 3
                row += 1
            }
            context.fill(shallow, with: .color(dot.opacity(0.3)))
            context.fill(deep, with: .color(dot.opacity(0.45)))
        }
    }

    /// 稚魚が上から入ってくる：水面の波紋、点の足跡、奥に2匹
    private func entering(sx: CGFloat) -> some View {
        let cx = 160 * sx
        return ZStack(alignment: .topLeading) {
            GoldfishMark(color: Theme.accent.opacity(0.35), width: 28.8)
                .offset(x: 40 * sx, y: 104)
            GoldfishMark(color: Theme.ink.opacity(0.3), width: 28.8)
                .scaleEffect(x: -1)
                .offset(x: 236 * sx, y: 92)
            // 水面の波紋
            Path { p in
                p.move(to: CGPoint(x: cx - 34, y: 30)); p.addQuadCurve(to: CGPoint(x: cx + 34, y: 30), control: CGPoint(x: cx, y: 18))
            }
            .stroke(Theme.waterDot.opacity(0.7), lineWidth: 2)
            Path { p in
                p.move(to: CGPoint(x: cx - 22, y: 38)); p.addQuadCurve(to: CGPoint(x: cx + 22, y: 38), control: CGPoint(x: cx, y: 30))
            }
            .stroke(Theme.waterDot.opacity(0.45), lineWidth: 2)
            // 沈んできた跡
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(Theme.ink.opacity(0.45))
                    .frame(width: 2, height: 2)
                    .offset(x: cx - 1, y: 44 + CGFloat(i) * 8)
            }
            .opacity(dropped ? 1 : 0)
            GoldfishMark(color: Theme.ink, style: .fry, width: 36)
                .offset(x: cx - 18, y: dropped ? 70 : -24)
        }
    }

    /// 水槽いっぱいの金魚（デザインの並び）
    private func fullFish(sx: CGFloat) -> some View {
        // x, y, 色（r=紅 / k=藍 / b=両方 / f=薄い / y=稚魚）, 左向きを反転
        let fish: [(CGFloat, CGFloat, Character, Bool)] = [
            (18, 22, "r", false), (74, 30, "k", true), (132, 18, "b", false), (190, 28, "r", false), (250, 22, "y", false),
            (30, 70, "f", true), (88, 78, "r", false), (146, 66, "k", true), (204, 74, "b", false), (262, 66, "r", false),
            (16, 116, "y", false), (70, 124, "k", false), (128, 116, "r", true), (186, 126, "f", false), (244, 118, "r", true),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(fish.indices, id: \.self) { i in
                let f = fish[i]
                mark(f.2)
                    .scaleEffect(x: f.3 ? -1 : 1)
                    .offset(x: f.0 * sx, y: f.1)
            }
        }
    }

    @ViewBuilder private func mark(_ kind: Character) -> some View {
        switch kind {
        case "r": GoldfishMark(tint: .red, width: 28.8)
        case "k": GoldfishMark(tint: .black, width: 28.8)
        case "b": GoldfishMark(tint: .both, width: 28.8)
        case "f": GoldfishMark(tint: .faint, width: 28.8)
        default: GoldfishMark(color: Theme.ink, style: .fry, width: 28.8)
        }
    }
}

/// 書き出しの入力欄。複数行まで書けて、改行キーで放す。
/// 表示されたらすぐにカーソルを取る（SwiftUI の FocusState は全画面カバーの中で効かないことがあるため UIKit で作る）。
private struct CaptureField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> FocusingTextView {
        let view = FocusingTextView()
        view.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .heavy))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = Theme.inkUIColor
        // カーソルは紅
        view.tintColor = Theme.accentUIColor
        view.returnKeyType = .done
        view.autocapitalizationType = .none
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.placeholder = "気になっていること"
        view.accessibilityLabel = "気になっていること"
        // 長い文でも横に広がらないようにする
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: FocusingTextView, context: Context) {
        if view.text != text { view.text = text }
        view.updatePlaceholder()
        context.coordinator.parent = self
    }

    /// 幅は親に合わせ、高さは書いた行の数だけ伸ばす
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FocusingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CaptureField
        init(parent: CaptureField) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            (textView as? FocusingTextView)?.updatePlaceholder()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // 改行キーは「放す」。貼り付けた改行は空白にする
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            if text.contains("\n"), let target = textView.textRange(for: range) {
                textView.replace(target, withText: text.replacingOccurrences(of: "\n", with: " "))
                return false
            }
            return true
        }
    }
}

final class FocusingTextView: UITextView {
    /// 画面に出ている入力欄。パッドを開くときや放すとき、変換中の文字を確定させるために使う。
    static weak var current: FocusingTextView?

    private let placeholderLabel = UILabel()

    var placeholder: String? {
        get { placeholderLabel.text }
        set { placeholderLabel.text = newValue }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = Theme.inkUIColor.withAlphaComponent(0.35)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var font: UIFont? {
        didSet { placeholderLabel.font = font }
    }

    func updatePlaceholder() { placeholderLabel.isHidden = !(text ?? "").isEmpty }

    /// 変換中（未確定）の文字を、そのまま確定させる。
    func commitMarkedText() {
        guard markedTextRange != nil else { return }
        unmarkText()
        delegate?.textViewDidChange?(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        Self.current = self
        // 表示アニメーションの途中でも取れるよう、次のループで何度か試す
        func attempt(_ remaining: Int) {
            guard remaining > 0, window != nil, !isFirstResponder else { return }
            if !becomeFirstResponder() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt(remaining - 1) }
            }
        }
        DispatchQueue.main.async { attempt(10) }
    }
}

private extension UITextView {
    func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length) else { return nil }
        return textRange(from: start, to: end)
    }
}
