import Foundation

/// 決めた秒数で待つのをやめる。キャンセルに応じない処理（モデルの準備など）でも先へ進めるよう、
/// 子タスクの終わりを待たずに nil を返す。
@MainActor
func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @MainActor () async -> T?) async -> T? {
    let once = TimeoutOnce()
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
    let result: T? = await withCheckedContinuation { continuation in
        work = Task { @MainActor in
            let value = await operation()
            if once.claim() { continuation.resume(returning: value) }
        }
        timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.claim() { continuation.resume(returning: nil) }
        }
    }
    work?.cancel()
    timer?.cancel()
    return result
}

/// 1回だけ再開するための印。
private final class TimeoutOnce: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if resumed { return false }; resumed = true; return true }
}
