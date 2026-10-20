import SwiftUI
import SwiftData

/// 書き出し画面。入力欄だけを出し、入れたら返す時刻を見せて自動で閉じる。
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Axis.order) private var axes: [Axis]

    @State private var text = ""
    @State private var timing: ReturnTiming = FocusSession.shared.isActive ? .atBreak : SettingsStore.defaultTiming
    // 任意：預けるときに付けてもよい。付けなければ nil のまま
    @State private var want: Double?
    @State private var must: Double?
    @State private var confirmed: ReturnTiming?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            DotGridBackground().ignoresSafeArea().opacity(confirmed == nil ? 0.5 : 1)

            if let confirmed {
                confirmation(for: confirmed)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                editor
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.cube(.quiet))
                .accessibilityLabel("閉じる")
            }

            HStack(spacing: 12) {
                CaptureField(text: $text, onSubmit: submit)
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.turn.down.left")
                    }
                    .buttonStyle(.cube(.primary))
                    .accessibilityLabel("あとで")
                    .transition(.opacity)
                }
            }

            Rectangle().fill(Theme.faint).frame(height: 1)

            CubeSegmented(options: ReturnTiming.allCases, label: { $0.label() },
                          detail: { $0.returnDate()?.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) },
                          selection: $timing, fill: true)
            WantMustPicker(want: $want, must: $must, side: 150,
                           onTouch: { FocusingTextField.current?.commitMarkedText() })
                .padding(.top, 12)
            Spacer()
        }
        .padding(24)
    }

    private func confirmation(for timing: ReturnTiming) -> some View {
        VStack(spacing: 16) {
            if let date = timing.returnDate() {
                DotMatrixText(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()), size: .large)
            } else {
                DotMatrixText("--:--", size: .large, color: Theme.quiet)
                Text(timing.label).atype(.small, color: Theme.quiet)
            }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, confirmed == nil else { return }

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
