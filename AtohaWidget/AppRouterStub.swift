import Foundation

/// CaptureIntent が参照する AppRouter の置き場所。
/// CaptureIntent は openAppWhenRun なのでアプリ本体のプロセスで動き、この実体は使われない。
final class AppRouter {
    static let shared = AppRouter()
    var showCapture = false
}
