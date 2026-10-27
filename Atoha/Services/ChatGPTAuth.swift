import Foundation
import Network
import Security
import CryptoKit
import SafariServices
import AuthenticationServices
import SwiftUI

/// ChatGPT 連携の機能フラグ。DEBUG では有効、Release では UserDefaults の "atoha.chatgpt.enabled" があるときだけ。
enum FeatureFlags {
    static var chatGPTEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "atoha.chatgpt.enabled")
        #endif
    }
}

/// ChatGPT にメモを送ることへの同意（App Store 審査ガイドライン 5.1.2(i)）と、OpenAI の表示の決まり。
enum ChatGPTConsent {
    private static let consentKey = "atoha.chatgpt.consented"
    private static let welcomeKey = "atoha.chatgpt.welcomeShown"
    /// 「Manage usage」で開く ChatGPT の設定
    static let manageUsageURL = URL(string: "https://chatgpt.com/settings/usage")!

    /// 送る前に同意をもらっているか。同意がなければ ChatGPT には何も送らない
    static var granted: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }

    /// 初めてのログインのあとに出す案内を出したか
    static var welcomeShown: Bool {
        get { UserDefaults.standard.bool(forKey: welcomeKey) }
        set { UserDefaults.standard.set(newValue, forKey: welcomeKey) }
    }
}

/// 保存する認証情報（Keychain）。
struct ChatGPTCredentials: Codable {
    var clientID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double
    var email: String?
}

enum ChatGPTError: Error {
    case notSignedIn
    case limitReached
    case unavailable
    case failed(String)
}

/// Keychain への読み書き。どのスレッドからでも呼べる。
enum ChatGPTStore {
    private static let service = "app.atoha.siwc"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func write(_ account: String, _ data: Data) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }

    static func loadCredentials() -> ChatGPTCredentials? {
        read("credentials").flatMap { try? JSONDecoder().decode(ChatGPTCredentials.self, from: $0) }
    }

    static func saveCredentials(_ c: ChatGPTCredentials) {
        if let d = try? JSONEncoder().encode(c) { write("credentials", d) }
    }

    /// インストールごとに固定の ID。
    static var hostID: String {
        if let d = read("host_id"), let s = String(data: d, encoding: .utf8) { return s }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        write("host_id", Data(id.utf8))
        return id
    }

    // 上限に達した日（画面の印用）
    private static let reachedKey = "atoha.chatgpt.reachedAt"
    static func markReached() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: reachedKey) }
    static var reachedToday: Bool {
        let t = UserDefaults.standard.double(forKey: reachedKey)
        return t > 0 && Calendar.current.isDateInToday(Date(timeIntervalSince1970: t))
    }
}

@MainActor
final class ChatGPTAuth: ObservableObject {
    static let shared = ChatGPTAuth()

    private static let authURL = "https://auth.openai.com/api/accounts/authorize"
    private static let tokenURL = "https://auth.openai.com/api/accounts/oauth/token"
    nonisolated static let api = "https://api.openai.com/v1"
    private static let port: UInt16 = 1455
    private static let redirect = "http://127.0.0.1:1455/auth/callback"
    private static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    /// Safari シートに出す URL。nil で閉じる。
    @Published var safariURL: URL?
    @Published private(set) var model: String? = UserDefaults.standard.string(forKey: "atoha.chatgpt.model")

    private var listener: NWListener?
    private var webSession: ASWebAuthenticationSession?
    private var signInTask: Task<Void, Never>?
    private var callback: CheckedContinuation<[String: String]?, Never>?

    private init() {
        let c = ChatGPTStore.loadCredentials()
        isSignedIn = c != nil
        email = c?.email
    }

    // MARK: サインイン

    func signIn() {
        guard !busy else { return }
        busy = true
        signInTask = Task { [weak self] in
            await self?.runSignIn()
            self?.busy = false
        }
    }

    func cancel() {
        signInTask?.cancel()
        finishCallback(nil)
    }

    func signOut() {
        cancel()
        ChatGPTStore.delete("credentials")
        isSignedIn = false
        email = nil
        // ログアウトしたら同意も外す（次に使うときは、もう一度たずねる）
        ChatGPTConsent.granted = false
    }

    private func runSignIn() async {
        let old = ChatGPTStore.loadCredentials()
        let clientID = old?.clientID ?? "dynamic_agent_client"
        let verifier = Self.randomURLSafe(48)
        let challenge = Self.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(16), nonce = Self.randomURLSafe(16)
        var params: [(String, String)] = [
            ("client_id", clientID), ("ext_agent_host_id", ChatGPTStore.hostID), ("response_type", "code"),
            ("redirect_uri", Self.redirect), ("scope", Self.scope), ("resource", Self.api),
            ("state", state), ("nonce", nonce), ("code_challenge_method", "S256"), ("code_challenge", challenge),
        ]
        if clientID == "dynamic_agent_client" {
            params.append(("agent_name_hint", "atoha"))
        } else if let idt = old?.idToken {
            params.append(("id_token_hint", idt))
        }
        var comps = URLComponents(string: Self.authURL)!
        comps.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = comps.url else { return }

        // ブラウザを開く前に待ち受ける
        guard startListener() else { return }
        defer { stopListener() }
        // Apple 推奨のログイン画面。Safari の Cookie を共有するので、ChatGPT にログイン済みなら早い。
        // 戻り先は http://127.0.0.1 なので画面側では完了を検知できず、アプリ内の待ち受けが受け取ったら閉じる。
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "atoha-siwc") { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.finishCallback(nil) } }
        }
        session.presentationContextProvider = AuthPresentation.shared
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        session.start()

        // 3分で打ち切る
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            if !Task.isCancelled { self?.finishCallback(nil) }
        }
        let result = await withCheckedContinuation { (c: CheckedContinuation<[String: String]?, Never>) in
            self.callback = c
        }
        timeout.cancel()
        webSession?.cancel()
        webSession = nil
        guard let result, result["state"] == state, result["error"] == nil, let code = result["code"] else { return }
        let issued = result["client_id"] ?? (clientID != "dynamic_agent_client" ? clientID : nil)
        guard let issued else { return }

        do {
            let tok = try await Self.postForm(Self.tokenURL, [
                "grant_type": "authorization_code", "client_id": issued, "code": code,
                "code_verifier": verifier, "redirect_uri": Self.redirect, "resource": Self.api])
            guard let idToken = tok["id_token"] as? String, let access = tok["access_token"] as? String,
                  let claims = Self.claims(idToken),
                  claims["nonce"] as? String == nonce,
                  Self.audMatches(claims["aud"], issued),
                  (tok["scope"] as? String ?? "").contains("chatgpt.tokens.use.direct")
            else { return }
            let creds = ChatGPTCredentials(
                clientID: issued, idToken: idToken, accessToken: access,
                refreshToken: tok["refresh_token"] as? String,
                expiresAt: Date().timeIntervalSince1970 + (tok["expires_in"] as? Double ?? 3600),
                email: claims["email"] as? String)
            ChatGPTStore.saveCredentials(creds)
            email = creds.email
            isSignedIn = true
            _ = try? await refreshModel(token: access)
        } catch {}
    }

    private func finishCallback(_ r: [String: String]?) {
        guard let c = callback else { return }
        callback = nil
        c.resume(returning: r)
    }

    // MARK: ローカルの待ち受け（127.0.0.1:1455）

    private func startListener() -> Bool {
        stopListener()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return false }
        l.newConnectionHandler = { [weak self] conn in
            let owner = self
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                var query: [String: String]?
                if let data, let text = String(data: data, encoding: .utf8),
                   let line = text.components(separatedBy: "\r\n").first {
                    let parts = line.split(separator: " ")
                    if parts.count >= 2, parts[0] == "GET",
                       let u = URLComponents(string: String(parts[1])), u.path == "/auth/callback" {
                        query = Dictionary((u.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                                           uniquingKeysWith: { a, _ in a })
                    }
                }
                let body = query == nil ? "" : "atoha: ログインしました。アプリに戻ってください。"
                let head = "HTTP/1.1 \(query == nil ? "404 Not Found" : "200 OK")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
                if let q = query { Task { @MainActor in owner?.finishCallback(q) } }
            }
        }
        l.start(queue: .main)
        listener = l
        return true
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    // MARK: トークン

    func validAccessToken() async throws -> String {
        guard var c = ChatGPTStore.loadCredentials() else { throw ChatGPTError.notSignedIn }
        if c.expiresAt > Date().timeIntervalSince1970 + 60 { return c.accessToken }
        guard let refresh = c.refreshToken else { signOutQuietly(); throw ChatGPTError.notSignedIn }
        do {
            let tok = try await Self.postForm(Self.tokenURL, [
                "grant_type": "refresh_token", "client_id": c.clientID, "refresh_token": refresh, "resource": Self.api])
            guard let access = tok["access_token"] as? String else { throw ChatGPTError.failed("no token") }
            c.accessToken = access
            c.refreshToken = tok["refresh_token"] as? String ?? refresh
            c.expiresAt = Date().timeIntervalSince1970 + (tok["expires_in"] as? Double ?? 3600)
            if let idt = tok["id_token"] as? String { c.idToken = idt }
            ChatGPTStore.saveCredentials(c)
            return access
        } catch ChatGPTError.notSignedIn {
            signOutQuietly()
            throw ChatGPTError.notSignedIn
        }
    }

    /// 呼び出し側（401 など）からサインアウトさせる。
    func signOutQuietly() {
        ChatGPTStore.delete("credentials")
        isSignedIn = false
        email = nil
    }

    // MARK: モデル

    @discardableResult
    func refreshModel(token: String) async throws -> String? {
        var req = URLRequest(url: URL(string: Self.api + "/models")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = (body?["models"] ?? body?["data"]) as? [[String: Any]] ?? []
        let slugs = items.filter { ($0["visibility"] as? String ?? "list") == "list" }
            .compactMap { ($0["slug"] ?? $0["id"]) as? String }
        if let first = slugs.first {
            model = first
            UserDefaults.standard.set(first, forKey: "atoha.chatgpt.model")
        }
        return slugs.first
    }

    func currentModel(token: String) async throws -> String {
        if let m = model { return m }
        if let m = try await refreshModel(token: token) { return m }
        throw ChatGPTError.unavailable
    }

    // MARK: 補助

    nonisolated static func postForm(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            if json["error"] as? String == "invalid_grant" || status == 401 { throw ChatGPTError.notSignedIn }
            throw ChatGPTError.failed("HTTP \(status)")
        }
        return json
    }

    nonisolated private static func randomURLSafe(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b64url(Data(b))
    }

    nonisolated private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated private static func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    nonisolated private static func audMatches(_ aud: Any?, _ id: String) -> Bool {
        if let s = aud as? String { return s == id }
        if let a = aud as? [String] { return a.contains(id) }
        return false
    }
}

/// ログイン用の Safari シート。
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// ASWebAuthenticationSession を出す画面。
final class AuthPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentation()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
