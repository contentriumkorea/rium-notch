import AppKit
import SwiftUI
import WebKit
import Security
import LocalAuthentication

// Persist only SKT web session cookies in the system keychain; never change their expiry.
enum SKTSessionStore {
    private static let service = "app.rium.notch.skt-session"
    static func belongsToSKT(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ["tworld.co.kr", "skt-id.co.kr"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func encode(_ cookies: [HTTPCookie], now: Date = Date()) -> Data? {
        let rows = cookies.filter { belongsToSKT($0.domain) && ($0.expiresDate == nil || $0.expiresDate! > now) }
            .compactMap { cookie -> [String: Any]? in
                guard var properties = cookie.properties else { return nil }
                if let expires = cookie.expiresDate {
                    properties[.expires] = expires
                    properties.removeValue(forKey: .maximumAge)
                }
                return Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) })
            }
        guard !rows.isEmpty, PropertyListSerialization.propertyList(rows, isValidFor: .binary) else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: rows, format: .binary, options: 0)
    }
    static func decode(_ data: Data, now: Date = Date()) -> [HTTPCookie] {
        guard data.count <= 512_000,
              let rows = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let properties = Dictionary(uniqueKeysWithValues: row.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard let cookie = HTTPCookie(properties: properties), belongsToSKT(cookie.domain),
                  cookie.expiresDate == nil || cookie.expiresDate! > now else { return nil }
            return cookie
        }
    }
    static func save(_ cookies: [HTTPCookie], service: String = service) -> Bool {
        guard let data = encode(cookies) else { return false }
        return SKTKeychain.save(data, service: service)
    }
    static func load(service: String = service) -> [HTTPCookie] {
        SKTKeychain.load(service: service).map { decode($0) } ?? []
    }
    @discardableResult static func clear(service: String = service) -> Bool {
        SKTKeychain.clear(service: service)
    }
}

private enum SKTKeychain {
    private static func query(_ service: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "T world", kSecUseAuthenticationContext as String: context]
    }

    static func save(_ data: Data, service: String) -> Bool {
        let item = query(service)
        let values = [kSecValueData as String: data]
        let result = SecItemUpdate(item as CFDictionary, values as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var newItem = item.merging(values) { _, data in data }
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    static func load(service: String) -> Data? {
        var item = query(service)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &value) == errSecSuccess else { return nil }
        return value as? Data
    }

    static func clear(service: String) -> Bool {
        let result = SecItemDelete(query(service) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

struct SKTLoginCredentials: Codable, Equatable {
    private static let service = "app.rium.notch.skt-login"
    let loginID: String
    let password: String

    init?(loginID: String, password: String) {
        let loginID = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loginID.isEmpty, loginID.utf16.count <= 50, !password.isEmpty, password.utf16.count <= 50 else { return nil }
        self.loginID = loginID
        self.password = password
    }

    func save(service: String = Self.service) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        return SKTKeychain.save(data, service: service)
    }

    static func load(service: String = service) -> Self? {
        guard let data = SKTKeychain.load(service: service),
              let result = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return Self(loginID: result.loginID, password: result.password)
    }

    @discardableResult static func clear(service: String = service) -> Bool {
        SKTKeychain.clear(service: service)
    }

    static func isLoginPage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "auth.skt-id.co.kr" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.path == "/v2/login"
    }

    static let loginScript = """
    const visible = control => control && control.getBoundingClientRect().width > 0 &&
        control.getBoundingClientRect().height > 0 && getComputedStyle(control).visibility === "visible";
    const active = control => visible(control) && !control.disabled && !control.readOnly;
    const challengeVisible = () => Array.from(document.querySelectorAll(
        "#recaptcha-container:not(.g-invisible), .recaptcha-info, [role=dialog][aria-modal=true]")).some(visible);
    for (let attempt = 0; attempt < 20; attempt++) {
        if (window !== window.top || location.origin !== "https://auth.skt-id.co.kr" ||
            location.pathname !== "/v2/login") return "unavailable";
        if (challengeVisible()) return "manual";
        const id = document.querySelector("input#inputId[type=text]");
        const secret = document.querySelector("input#inputPassword[type=password]");
        const submit = document.querySelector('button[data-click-id="login"]');
        const page = id?.getAttribute("page-id");
        if (page && active(id) && active(secret) && visible(submit) &&
            submit.getAttribute("page-id") === page && secret.getAttribute("page-id") === page) {
            if ((id.value && id.value !== loginID) || secret.value) return "manual";
            const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
            for (const [input, value] of [[id, loginID], [secret, password]]) {
                setValue.call(input, value);
                input.dispatchEvent(new Event("input", { bubbles: true }));
            }
            await Promise.resolve();
            if (challengeVisible() || !submit.isConnected || submit.disabled || secret.value !== password || id.value !== loginID ||
                location.origin !== "https://auth.skt-id.co.kr" || location.pathname !== "/v2/login") return "manual";
            submit.click();
            return "submitted";
        }
        await new Promise(resolve => setTimeout(resolve, 300));
    }
    return "unavailable";
    """
}

struct SKTSharedData: Equatable {
    let remaining: String
    let used: String
    let allowance: String

    static func parse(rows: [[String]]) -> SKTSharedData? {
        let matches = rows.filter { $0.count >= 3 && $0[0].contains("통합공유 데이터") }
        guard matches.count == 1 else { return nil }
        let row = matches[0]
        let pattern = #"(?i)^\s*\d+(?:\.\d+)?\s*(?:KB|MB|GB|TB)\s*$"#
        func amount(_ value: String) -> String? {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.range(of: pattern, options: .regularExpression) == nil ? nil : clean
        }
        let title = row[0].replacingOccurrences(of: "통합공유 데이터", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let allowance = amount(title), let used = amount(row[1]), let remaining = amount(row[2]) else { return nil }
        return SKTSharedData(remaining: remaining, used: used, allowance: allowance)
    }
}

final class SKTUsageController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private static let balanceURL = URL(string: "https://www.tworld.co.kr/web/myt-data/balance")!
    private static let enabledKey = "rium.skt.connected"
    private static let credentialsKey = "rium.skt.savedLogin"
    private static let retryBlockedKey = "rium.skt.autoLoginNeedsReview"
    private let sessionQueue = DispatchQueue(label: "app.rium.notch.skt-session", qos: .utility)
    @Published private(set) var sharedData: SKTSharedData?
    @Published private(set) var status = "SKT 연결"
    @Published private(set) var updatedAt: Date?
    @Published private(set) var sessionSaved = true
    private var webView: WKWebView?
    private var window: NSWindow?
    private var timer: Timer?
    private var generation = 0
    private var restoringSession = false
    private var refreshDue: Date?
    private var inLoginFlow = false
    private var autoLoginPending = false
    private var accountChangeInProgress = false

    private var hasSavedAccount: Bool { UserDefaults.standard.bool(forKey: Self.credentialsKey) }

    func startIfConnected() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) || hasSavedAccount else { return }
        let generation = generation
        restoringSession = true
        let store = browser().configuration.websiteDataStore.httpCookieStore
        sessionQueue.async { [weak self] in
            let cookies = SKTSessionStore.load()
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                let pending = DispatchGroup()
                for cookie in cookies {
                    pending.enter()
                    store.setCookie(cookie) { pending.leave() }
                }
                pending.notify(queue: .main) {
                    guard self.generation == generation else { return }
                    self.restoringSession = false
                    self.refresh()
                }
            }
        }
    }

    private func browser() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 720), configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        webView = view
        return view
    }

    func open() {
        let browser = browser()
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 760),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            newWindow.title = "SKT 통합공유 데이터"
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            let content = NSView()
            let close = NSButton(title: "닫기", target: self, action: #selector(closeWindow))
            let disconnect = NSButton(title: "연결 해제", target: self, action: #selector(disconnectAccount))
            close.bezelStyle = .rounded
            let account = NSButton(title: "자동 로그인 설정…", target: self, action: #selector(editSavedAccount))
            disconnect.bezelStyle = .rounded
            account.bezelStyle = .rounded
            account.translatesAutoresizingMaskIntoConstraints = false
            browser.translatesAutoresizingMaskIntoConstraints = false
            close.translatesAutoresizingMaskIntoConstraints = false
            disconnect.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(browser)
            content.addSubview(close)
            content.addSubview(disconnect)
            content.addSubview(account)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
                close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                disconnect.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                disconnect.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
                account.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                account.trailingAnchor.constraint(equalTo: disconnect.leadingAnchor, constant: -8),
                browser.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 6),
                browser.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                browser.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                browser.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
            newWindow.contentView = content
            newWindow.center()
            window = newWindow
        }
        if (browser.url == nil || browser.url?.scheme == "about") && !restoringSession { refresh() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
        refreshIfDue()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.refreshIfDue() }
    }

    private func refreshIfDue() {
        if let due = refreshDue, due <= Date(), UserDefaults.standard.bool(forKey: Self.enabledKey) || hasSavedAccount {
            refresh()
        }
    }

    @objc private func editSavedAccount() {
        guard let window, !accountChangeInProgress, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "SKT 자동 로그인"
        alert.informativeText = "이 Mac의 키체인에 저장하고, T world 로그인이 필요할 때 입력과 로그인을 자동으로 시도합니다."
        alert.addButton(withTitle: "저장 및 로그인")
        alert.addButton(withTitle: "취소")
        if hasSavedAccount { alert.addButton(withTitle: "저장 계정 삭제") }

        let id = NSTextField()
        id.placeholderString = "T아이디"
        id.setAccessibilityLabel("T아이디")
        let password = NSSecureTextField()
        password.placeholderString = "비밀번호"
        password.setAccessibilityLabel("비밀번호")
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 58))
        id.frame = NSRect(x: 0, y: 34, width: 284, height: 24)
        password.frame = NSRect(x: 0, y: 2, width: 284, height: 24)
        fields.addSubview(id)
        fields.addSubview(password)
        alert.accessoryView = fields
        id.nextKeyView = password
        alert.window.initialFirstResponder = id
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            if result == .alertThirdButtonReturn {
                self.removeSavedAccount()
            } else if result == .alertFirstButtonReturn {
                let credentials = SKTLoginCredentials(loginID: id.stringValue, password: password.stringValue)
                password.stringValue = ""
                guard let credentials else {
                    DispatchQueue.main.async { self.showAccountMessage("T아이디와 비밀번호를 확인해 주세요.") }
                    return
                }
                self.saveAccount(credentials)
            }
        }
    }

    private func showAccountMessage(_ message: String) {
        guard let window, window.isVisible else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "확인")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    private func saveAccount(_ credentials: SKTLoginCredentials) {
        accountChangeInProgress = true
        sessionQueue.async { [weak self] in
            let saved = credentials.save()
            if saved { SKTSessionStore.clear() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.accountChangeInProgress = false
                guard saved else {
                    self.showAccountMessage("키체인에 SKT 계정을 저장하지 못했습니다.")
                    return
                }
                let preferences = UserDefaults.standard
                preferences.set(true, forKey: Self.credentialsKey)
                preferences.removeObject(forKey: Self.retryBlockedKey)
                preferences.removeObject(forKey: Self.enabledKey)
                self.status = "SKT 확인 중"
                self.resetSession { [weak self] in self?.refresh() }
            }
        }
    }

    private func removeSavedAccount(cancelLogin: Bool = true) {
        accountChangeInProgress = true
        UserDefaults.standard.removeObject(forKey: Self.credentialsKey)
        UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
        if cancelLogin && autoLoginPending { refresh() }
        sessionQueue.async { [weak self] in
            let removed = SKTLoginCredentials.clear()
            DispatchQueue.main.async {
                guard let self else { return }
                self.accountChangeInProgress = false
                if !removed { self.showAccountMessage("자동 로그인은 꺼졌습니다. 키체인의 저장 계정을 삭제하지 못했습니다.") }
            }
        }
    }

    private func resetSession(completion: @escaping () -> Void) {
        generation += 1
        let generation = generation
        timer?.invalidate(); refreshDue = nil
        restoringSession = true
        inLoginFlow = false
        autoLoginPending = false
        sharedData = nil; updatedAt = nil; sessionSaved = true
        let browser = browser()
        browser.stopLoading()
        browser.loadHTMLString("<html lang='ko'></html>", baseURL: nil)
        let store = browser.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self] cookies in
            guard let self, self.generation == generation else { return }
            let pending = DispatchGroup()
            for cookie in cookies {
                let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard SKTSessionStore.belongsToSKT(host) || host == "t-id.co.kr" || host.hasSuffix(".t-id.co.kr") else { continue }
                pending.enter()
                store.delete(cookie) { pending.leave() }
            }
            pending.notify(queue: .main) {
                guard self.generation == generation else { return }
                self.restoringSession = false
                completion()
            }
        }
    }

    @objc private func disconnectAccount() {
        guard !accountChangeInProgress else { return }
        let preferences = UserDefaults.standard
        preferences.removeObject(forKey: Self.enabledKey)
        removeSavedAccount(cancelLogin: false)
        sessionQueue.async { [weak self] in
            let cleared = SKTSessionStore.clear()
            DispatchQueue.main.async { if !cleared { self?.status = "SKT 저장 세션 삭제 실패" } }
        }
        status = "SKT 연결"
        resetSession { [weak self] in
            self?.webView?.loadHTMLString("<html lang='ko'><body>SKT 연결이 해제되었습니다.</body></html>", baseURL: nil)
        }
    }

    func refresh() {
        generation += 1
        timer?.invalidate(); refreshDue = nil
        inLoginFlow = true
        autoLoginPending = false
        status = "SKT 확인 중"
        browser().load(URLRequest(url: Self.balanceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func attemptAutoLogin(in browser: WKWebView) {
        let preferences = UserDefaults.standard
        guard hasSavedAccount, inLoginFlow, !accountChangeInProgress, !autoLoginPending else { return }
        guard !preferences.bool(forKey: Self.retryBlockedKey) else {
            status = "SKT 로그인 확인 필요"
            return
        }
        autoLoginPending = true
        let generation = generation
        sessionQueue.async { [weak self, weak browser] in
            let credentials = SKTLoginCredentials.load()
            DispatchQueue.main.async {
                guard let self, let browser, self.generation == generation,
                      self.inLoginFlow, self.hasSavedAccount, !self.accountChangeInProgress,
                      let url = browser.url, SKTLoginCredentials.isLoginPage(url) else { return }
                guard let credentials else {
                    self.autoLoginPending = false
                    self.status = "SKT 저장 계정 확인 필요"
                    return
                }
                self.status = "SKT 자동 로그인 중"
                // Keep the guard across restarts if an attempt did not reach a successful login.
                preferences.set(true, forKey: Self.retryBlockedKey)
                browser.callAsyncJavaScript(SKTLoginCredentials.loginScript,
                    arguments: ["loginID": credentials.loginID, "password": credentials.password],
                    in: nil, in: WKContentWorld.world(name: "app.rium.notch.skt-login")
                ) { [weak self] result in
                    guard let self, self.generation == generation else { return }
                    if case .success(let disposition) = result, let value = disposition as? String, value != "submitted" {
                        preferences.removeObject(forKey: Self.retryBlockedKey)
                        self.status = "SKT 로그인 확인 필요"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
                    guard let self, self.generation == generation, self.status == "SKT 자동 로그인 중" else { return }
                    self.status = "SKT 로그인 확인 필요"
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.scheme == "https", let host = url.host else { return }
        if (host == "www.tworld.co.kr" && url.path == "/web/login/tid-logout") ||
            (host == "auth.skt-id.co.kr" && url.path == "/v2/logout") {
            disconnectAccount()
            return
        }
        if host == "auth.skt-id.co.kr" {
            timer?.invalidate(); refreshDue = nil
            if !autoLoginPending { status = "SKT 로그인 필요" }
            if SKTLoginCredentials.isLoginPage(url) {
                attemptAutoLogin(in: webView)
            } else {
                status = "SKT 로그인 확인 필요"
            }
            return
        }
        guard host == "www.tworld.co.kr" else {
            if host != "tapi.t-id.co.kr" { inLoginFlow = false }
            return
        }
        guard url.path == "/web/myt-data/balance" else {
            guard status.hasPrefix("SKT 로그인") || status == "SKT 자동 로그인 중" else { return }
            webView.evaluateJavaScript("Array.from(document.querySelectorAll('button')).some(b => b.innerText.trim() === '로그아웃')") { [weak self, weak webView] result, _ in
                guard let self, let webView, webView.url == url, result as? Bool == true else { return }
                self.refresh()
            }
            return
        }
        generation += 1
        checkRows(in: webView, generation: generation, attempts: 12)
    }

    private func checkRows(in webView: WKWebView, generation: Int, attempts: Int) {
        guard generation == self.generation, webView.url?.host?.lowercased() == "www.tworld.co.kr",
              webView.url?.path == "/web/myt-data/balance" else { return }
        let script = "Array.from(document.querySelectorAll('tr')).map(r => Array.from(r.querySelectorAll('td')).map(c => c.innerText.trim())).filter(c => c[0] && c[0].includes('통합공유 데이터'))"
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self, let webView, generation == self.generation else { return }
            if let rows = result as? [[String]], let data = SKTSharedData.parse(rows: rows) {
                self.sharedData = data
                self.updatedAt = Date()
                self.status = "통합공유 데이터 잔여 \(data.remaining)"
                self.inLoginFlow = false
                self.autoLoginPending = false
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
                self.scheduleRefresh()
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, generation == self.generation, !self.accountChangeInProgress else { return }
                    self.sessionQueue.async { [weak self] in
                        let saved = SKTSessionStore.save(cookies)
                        DispatchQueue.main.async {
                            guard let self, self.generation == generation else { return }
                            self.sessionSaved = saved
                        }
                    }
                }
            } else if attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.checkRows(in: webView, generation: generation, attempts: attempts - 1)
                }
            } else {
                self.status = "SKT 항목 확인 필요"
                self.scheduleRefresh(after: 300)
            }
        }
    }

    private func scheduleRefresh(after interval: TimeInterval = 900) {
        timer?.invalidate()
        refreshDue = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard self.window?.isVisible != true else { return }
            self.refresh()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        status = "SKT 조회 실패"
        scheduleRefresh(after: 300)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        status = "SKT 조회 실패"
        scheduleRefresh(after: 300)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct SKTUsageButton: View {
    @ObservedObject var controller: SKTUsageController
    private var detail: String {
        let saved = controller.sessionSaved ? "" : " · 로그인 복원 저장 실패"
        guard let updated = controller.updatedAt, controller.sharedData != nil else { return controller.status + saved }
        return "\(controller.status) · 마지막 조회 \(updated.formatted(date: .omitted, time: .standard))" + saved
    }
    var body: some View {
        Button { controller.open() } label: {
            HStack(spacing: 4) {
                Image(systemName: "personalhotspot")
                Text(controller.status.hasPrefix("통합공유 데이터 잔여") ? (controller.sharedData.map { "SKT \($0.remaining)" } ?? "SKT 연결") : controller.status)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(detail)
        .accessibilityLabel("SKT 통합공유 데이터")
        .accessibilityValue(detail)
    }
}
