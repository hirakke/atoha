import SwiftUI
import SwiftData

/// 書き出し画面。入力欄だけを出し、入れたら「あとで」に置いて自動で閉じる。
/// いつ思い出すかの時間設定は、わかりやすさのため一旦なくしている（ReturnTiming は残してある）。
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Axis.order) private var axes: [Axis]

    @State private var text = ""
    /// 時間は決めない。「あとで」から自分で選んで今に入れる
    private let timing: ReturnTiming = .atBreak
    // 任意：預けるときに付けてもよい。付けなければ nil のまま
    @State private var want: Double?
    @State private var must: Double?
    @State private var confirmed: ReturnTiming?
    /// 水槽（あとで）がいっぱいで、回せない
    @State private var full = false

    var body: some View {
        ZStack {
            PaperBackground()
            DotGridBackground().ignoresSafeArea().opacity(confirmed == nil ? 0.5 : 1)

            if let confirmed {
                confirmation(for: confirmed)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                editor
            }
        }
        .onAppear { full = ReturnService.laterRoom(in: context) == 0 }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("あとでに回す").atype(.display)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.cube(.quiet))
                .accessibilityLabel("閉じる")
            }

            if full {
                // 上限まで入っているときは回せない。減らし方だけを伝える
                VStack(alignment: .leading, spacing: 6) {
                    Text("水槽がいっぱいです（\(SettingsStore.laterCapacity)匹）").atype(.title)
                    Text("「あとで」で今に入れるか、やめるものを選ぶと、また回せます。")
                        .atype(.small, color: Theme.quiet)
                }
                .onPaper()
            } else {
            HStack(spacing: 12) {
                CaptureField(text: $text, onSubmit: submit)
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: submit) {
                        Text("回す")
                    }
                    .buttonStyle(.cube(.primary))
                    .transition(.opacity)
                }
            }
            }

            Rectangle().fill(Theme.faint).frame(height: 1)

            if !full {
                Text("やりたい・やらなきゃ（つけなくてもいい）").atype(.label).padding(.top, 12)
                WantMustPicker(want: $want, must: $must, side: 150,
                               onTouch: { FocusingTextField.current?.commitMarkedText() })
            }
            Spacer()
        }
        .padding(24)
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        VStack(spacing: 16) {
            GoldfishMark(color: Theme.accent, width: 54)
            Text("水槽に放しました").atype(.title)
            Text("「あとで」から選んで、今に入れられます").atype(.small, color: Theme.quiet)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, confirmed == nil, !full else { return }

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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeOut(duration: 0.2)) { confirmed = timing }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        }
    }
}

/// 書き出しの入力欄。表示されたらすぐにカーソルを取る（SwiftUI の FocusState は全画面カバーの中で効かないことがあるため UIKit で作る）。
private struct CaptureField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.font = AType.title.uiFont
        field.attributedPlaceholder = NSAttributedString(string: "気になっていること", attributes: [.foregroundColor: Theme.inkUIColor.withAlphaComponent(0.35)])
        field.textColor = Theme.inkUIColor
        field.tintColor = Theme.inkUIColor
        field.returnKeyType = .done
        field.autocapitalizationType = .none
        // 長い文でも横に広がらないようにする
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: FocusingTextField, context: Context) {
        if field.text != text { field.text = text }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CaptureField
        init(parent: CaptureField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

final class FocusingTextField: UITextField {
    /// 画面に出ている入力欄。パッドに触れたとき、変換中の文字を確定させるために使う。
    static weak var current: FocusingTextField?

    /// 変換中（未確定）の文字を、そのまま確定させる。
    func commitMarkedText() {
        guard markedTextRange != nil else { return }
        unmarkText()
        sendActions(for: .editingChanged)
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
