import AppKit
import SwiftUI
import WebKit
import Security
import LocalAuthentication

// Keep only KT's own session cookies, with their original expirations.
enum KTSessionStore {
    private static let service = "app.rium.notch.kt-session"
    static func belongsToKT(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ["kt.com", "kt.co.kr"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func encode(_ cookies: [HTTPCookie], now: Date = Date()) -> Data? {
        let rows = cookies.filter { belongsToKT($0.domain) && ($0.expiresDate == nil || $0.expiresDate! > now) }
            .compactMap { cookie -> [String: Any]? in
                guard var properties = cookie.properties else { return nil }
                if let expiry = cookie.expiresDate { properties[.expires] = expiry; properties.removeValue(forKey: .maximumAge) }
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
            guard let cookie = HTTPCookie(properties: properties), belongsToKT(cookie.domain),
                  cookie.expiresDate == nil || cookie.expiresDate! > now else { return nil }
            return cookie
        }
    }
    private static func query(_ service: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "KT", kSecUseAuthenticationContext as String: context]
    }
    static func save(_ cookies: [HTTPCookie], service: String = service) -> Bool {
        guard let data = encode(cookies) else { return false }
        let item = query(service), values = [kSecValueData as String: data]
        let result = SecItemUpdate(item as CFDictionary, values as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var newItem = item.merging(values) { _, value in value }
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }
    static func load(service: String = service) -> [HTTPCookie] {
        var item = query(service); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return [] }
        return decode(data)
    }
    @discardableResult static func clear(service: String = service) -> Bool {
        let result = SecItemDelete(query(service) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

struct KTLoginCredentials: Codable {
    private static let service = "app.rium.notch.kt-login"
    let loginID: String
    let password: String

    init?(loginID: String, password: String) {
        let id = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.utf16.count <= 50, !password.isEmpty, password.utf16.count <= 16 else { return nil }
        self.loginID = id; self.password = password
    }
    private static func query() -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "KT", kSecUseAuthenticationContext as String: context]
    }
    func save() -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        let item = Self.query(); let values = [kSecValueData as String: data]
        let result = SecItemUpdate(item as CFDictionary, values as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var newItem = item.merging(values) { _, value in value }
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }
    static func load() -> Self? {
        var item = query(); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return Self(loginID: decoded.loginID, password: decoded.password)
    }
    static func clear() -> Bool {
        let result = SecItemDelete(query() as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

struct KTSharedData: Equatable {
    let remaining: String
    let used: String?
    let allowance: String?

    static func parse(_ row: [String: String]) -> KTSharedData? {
        let remaining = (row["remaining"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let allowance = (row["allowance"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty, remaining.range(of: #"^(?:[0-9]+(?:\.[0-9]+)?\s*(?:KB|MB|GB|TB)|기본제공|무제한)$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return KTSharedData(remaining: remaining, used: nil, allowance: allowance.isEmpty ? nil : allowance)
    }
}

final class KTUsageController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var onSelectCarrier: ((String) -> Void)?
    private static let balanceURL = URL(string: "https://m.my.kt.com/s_main.jsp")!
    private static let enabledKey = "rium.kt.connected"
    private static let credentialsKey = "rium.kt.savedLogin"
    private static let retryBlockedKey = "rium.kt.autoLoginNeedsReview"
    private let sessionQueue = DispatchQueue(label: "app.rium.notch.kt-session", qos: .utility)
    @Published private(set) var sharedData: KTSharedData?
    @Published private(set) var status = "KT 연결"
    @Published private(set) var updatedAt: Date?
    @Published private(set) var sessionSaved = true
    private var webView: WKWebView?
    private var window: NSWindow?
    private var timer: Timer?
    private var generation = 0
    private var restoringSession = false
    private var refreshDue: Date?
    private var autoLoginPending = false
    private var loginPollSequence = 0
    private var hasSavedAccount: Bool { UserDefaults.standard.bool(forKey: Self.credentialsKey) }

    func startIfConnected() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) || hasSavedAccount else { return }
        let current = generation
        restoringSession = true
        let store = browser().configuration.websiteDataStore.httpCookieStore
        sessionQueue.async { [weak self] in
            let cookies = KTSessionStore.load()
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                let pending = DispatchGroup()
                for cookie in cookies { pending.enter(); store.setCookie(cookie) { pending.leave() } }
                pending.notify(queue: .main) {
                    guard self.generation == current else { return }
                    self.restoringSession = false; self.refresh()
                }
            }
        }
    }
    private func browser() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 720), configuration: config)
        view.navigationDelegate = self; view.uiDelegate = self; webView = view
        return view
    }
    func open() {
        let browser = browser()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "KT 공유·테더링 데이터"; w.isReleasedWhenClosed = false; w.delegate = self
            let content = NSView()
            let close = NSButton(title: "닫기", target: self, action: #selector(closeWindow))
            let disconnect = NSButton(title: "연결 해제", target: self, action: #selector(disconnectAccount))
            let account = NSButton(title: "저장 계정 관리…", target: self, action: #selector(editSavedAccount))
            let retry = NSButton(title: "자동 로그인 다시 시도", target: self, action: #selector(retryAutoLogin))
            let carrier = NSPopUpButton(frame: .zero, pullsDown: false)
            carrier.addItems(withTitles: ["SKT", "KT"]); carrier.selectItem(at: 1)
            carrier.target = self; carrier.action = #selector(selectCarrier(_:)); carrier.setAccessibilityLabel("통신사 선택")
            close.bezelStyle = .rounded; disconnect.bezelStyle = .rounded; account.bezelStyle = .rounded
            for view in [browser, close, disconnect, account, carrier, retry] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
                close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                disconnect.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                disconnect.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
                account.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                account.trailingAnchor.constraint(equalTo: disconnect.leadingAnchor, constant: -8),
                carrier.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                carrier.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                retry.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                retry.trailingAnchor.constraint(equalTo: account.leadingAnchor, constant: -8),
                browser.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 6),
                browser.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                browser.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                browser.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
            w.contentView = content; w.center(); window = w
        }
        if (browser.url == nil || browser.url?.scheme == "about") && !restoringSession { refresh() }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func selectCarrier(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem == 0 else { return }
        window?.orderOut(nil); onSelectCarrier?("skt")
        sender.selectItem(at: 1)
    }
    @objc private func closeWindow() { window?.orderOut(nil); refreshIfDue() }
    @objc private func retryAutoLogin() {
        guard hasSavedAccount else { accountMessage("먼저 저장 계정 관리에서 KT 계정을 저장해 주세요."); return }
        UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
        refresh()
    }
    @objc private func editSavedAccount() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "KT 저장 계정 관리"
        alert.informativeText = "계정은 이 Mac의 키체인에 저장됩니다. KT 로그인 화면에서 자동 입력과 로그인을 시도합니다."
        alert.addButton(withTitle: "저장"); alert.addButton(withTitle: "취소")
        if hasSavedAccount { alert.addButton(withTitle: "저장 계정 삭제") }
        let id = NSTextField(); id.placeholderString = "KT 아이디 또는 이메일"; id.setAccessibilityLabel("KT 아이디")
        let password = NSSecureTextField(); password.placeholderString = "비밀번호"; password.setAccessibilityLabel("KT 비밀번호")
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 58))
        id.frame = NSRect(x: 0, y: 34, width: 284, height: 24); password.frame = NSRect(x: 0, y: 2, width: 284, height: 24)
        fields.addSubview(id); fields.addSubview(password); id.nextKeyView = password
        alert.accessoryView = fields; alert.window.initialFirstResponder = id
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            if result == .alertThirdButtonReturn {
                self.generation += 1; self.browser().stopLoading(); self.autoLoginPending = false
                self.sessionQueue.async { [weak self] in
                    let removed = KTLoginCredentials.clear()
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if removed { UserDefaults.standard.removeObject(forKey: Self.credentialsKey); UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey) }
                        else { self.accountMessage("저장 계정을 삭제하지 못했습니다.") }
                    }
                }
            } else if result == .alertFirstButtonReturn {
                let credentials = KTLoginCredentials(loginID: id.stringValue, password: password.stringValue)
                password.stringValue = ""
                guard let credentials else { self.accountMessage("아이디와 비밀번호를 확인해 주세요."); return }
                self.generation += 1; self.browser().stopLoading(); self.autoLoginPending = false
                self.sessionQueue.async { [weak self] in
                    let saved = credentials.save()
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard saved else { self.accountMessage("키체인에 계정을 저장하지 못했습니다."); return }
                        UserDefaults.standard.set(true, forKey: Self.credentialsKey)
                        UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
                        self.refresh()
                    }
                }
            }
        }
    }
    private func accountMessage(_ message: String) {
        guard let window, window.isVisible else { return }
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "확인")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
    func windowWillClose(_ notification: Notification) { DispatchQueue.main.async { [weak self] in self?.refreshIfDue() } }
    private func refreshIfDue() {
        if let due = refreshDue, due <= Date(), UserDefaults.standard.bool(forKey: Self.enabledKey) { refresh() }
    }
    @objc private func disconnectAccount() {
        generation += 1; let current = generation
        timer?.invalidate(); timer = nil; refreshDue = nil
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
        UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
        sharedData = nil; updatedAt = nil; sessionSaved = true; status = "KT 연결"
        let browser = browser(); browser.stopLoading()
        browser.loadHTMLString("<html lang='ko'><body>KT 연결이 해제되었습니다.</body></html>", baseURL: nil)
        let store = browser.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self] cookies in
            guard let self, self.generation == current else { return }
            for cookie in cookies where KTSessionStore.belongsToKT(cookie.domain) { store.delete(cookie) }
        }
        sessionQueue.async { [weak self] in
            let removed = KTSessionStore.clear()
            let accountRemoved = KTLoginCredentials.clear()
            DispatchQueue.main.async {
                guard self?.generation == current else { return }
                if accountRemoved { UserDefaults.standard.removeObject(forKey: Self.credentialsKey) }
                if !removed || !accountRemoved { self?.status = "KT 저장 정보 삭제 실패" }
            }
        }
    }
    func refresh() {
        generation += 1; timer?.invalidate(); refreshDue = nil
        loginPollSequence += 1
        autoLoginPending = false
        status = "KT 확인 중"
        browser().load(URLRequest(url: Self.balanceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }
    private func scheduleRefresh(after interval: TimeInterval = 900) {
        timer?.invalidate(); refreshDue = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.window?.isVisible != true else { return }; self.refresh()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.scheme == "https", let host = url.host?.lowercased() else { return }
        if host == "accounts.kt.com" {
            timer?.invalidate(); refreshDue = nil; sharedData = nil; status = "KT 로그인 필요"
            if hasSavedAccount && !UserDefaults.standard.bool(forKey: Self.retryBlockedKey) {
                loginPollSequence += 1
                pollLoginPage(in: webView, generation: generation, sequence: loginPollSequence, attempts: 60)
            }
            return
        }
        guard host == "m.my.kt.com", url.path == "/s_main.jsp" else { return }
        loginPollSequence += 1
        generation += 1; checkRows(in: webView, generation: generation, attempts: 12)
    }
    private func pollLoginPage(in webView: WKWebView, generation: Int, sequence: Int, attempts: Int) {
        guard generation == self.generation, sequence == loginPollSequence, hasSavedAccount,
              !UserDefaults.standard.bool(forKey: Self.retryBlockedKey), let url = webView.url,
              url.scheme == "https", url.host == "accounts.kt.com", url.port == nil || url.port == 443 else { return }
        let script = """
        (() => {
          if (window !== window.top || location.origin !== 'https://accounts.kt.com') return 'unavailable';
          if (location.pathname === '/login/id') {
            return document.querySelector('input#id[name=id][type=text]') &&
                   document.querySelector('input#password[name=password][type=password]') &&
                   document.querySelector('button[type=submit][aria-label="로그인"]') ? 'ready' : 'wait';
          }
          if (location.pathname === '/wamui/AthMobile.do') {
            const button = Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === '아이디 로그인');
            if (button && !button.disabled) { button.click(); return 'opening'; }
          }
          return 'wait';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] value, _ in
            guard let self, let webView, generation == self.generation, sequence == self.loginPollSequence else { return }
            if value as? String == "ready" { self.attemptAutoLogin(in: webView); return }
            guard attempts > 1 else { self.status = "KT 로그인 확인 필요"; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.pollLoginPage(in: webView, generation: generation, sequence: sequence, attempts: attempts - 1)
            }
        }
    }
    private func checkRows(in webView: WKWebView, generation: Int, attempts: Int) {
        guard generation == self.generation, webView.url?.host?.lowercased() == "m.my.kt.com",
              webView.url?.path == "/s_main.jsp" else { return }
        let script = """
        (() => {
          const row = document.querySelector('ul.ngraph-list > li.tethering');
          if (!row || !row.querySelector('.data-name')?.textContent.includes('테더링')) return document.querySelector('#loginPage') ? {login: 'required'} : null;
          return { remaining: row.querySelector('.ngroup-info-item strong')?.textContent.trim() || '',
                   allowance: row.querySelector('.ngrap-maxgroup .employ')?.textContent.trim() || '' };
        })()
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
            guard let self, let webView, generation == self.generation,
                  webView.url?.host?.lowercased() == "m.my.kt.com", webView.url?.path == "/s_main.jsp" else { return }
            if let row = result as? [String: String], let data = KTSharedData.parse(row) {
                self.sharedData = data; self.updatedAt = Date(); self.status = "테더링 데이터 잔여 \(data.remaining)"
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                UserDefaults.standard.removeObject(forKey: Self.retryBlockedKey)
                self.scheduleRefresh()
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, generation == self.generation else { return }
                    self.sessionQueue.async { [weak self] in
                        let saved = KTSessionStore.save(cookies)
                        DispatchQueue.main.async { if self?.generation == generation { self?.sessionSaved = saved } }
                    }
                }
            } else if let row = result as? [String: String], row["login"] == "required" {
                self.sharedData = nil; self.status = "KT 로그인 필요"
                if self.hasSavedAccount && !UserDefaults.standard.bool(forKey: Self.retryBlockedKey) {
                    webView.evaluateJavaScript("document.querySelector('#loginPage')?.click()")
                }
            } else if attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak webView] in
                    guard let self, let webView else { return }; self.checkRows(in: webView, generation: generation, attempts: attempts - 1)
                }
            } else { self.sharedData = nil; self.status = "KT 항목 확인 필요"; self.scheduleRefresh(after: 300) }
        }
    }
    private func attemptAutoLogin(in webView: WKWebView) {
        guard !autoLoginPending, hasSavedAccount, let url = webView.url,
              url.scheme == "https", url.host == "accounts.kt.com", url.path == "/login/id",
              url.port == nil || url.port == 443 else { return }
        autoLoginPending = true
        let current = generation
        sessionQueue.async { [weak self, weak webView] in
            let credentials = KTLoginCredentials.load()
            DispatchQueue.main.async {
                guard let self, let webView, self.generation == current, webView.url == url else { return }
                guard let credentials else { self.autoLoginPending = false; self.status = "KT 저장 계정 확인 필요"; return }
                UserDefaults.standard.set(true, forKey: Self.retryBlockedKey)
                self.status = "KT 자동 로그인 중"
                let script = """
                if (window !== window.top || location.origin !== 'https://accounts.kt.com' || location.pathname !== '/login/id') return 'manual';
                let id = document.querySelector('input#id[name=id][type=text]');
                let secret = document.querySelector('input#password[name=password][type=password]');
                if (!id || !secret || id.disabled || secret.disabled || secret.value || (id.value && id.value !== loginID)) return 'manual';
                const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                const update = (input, value) => {
                    set.call(input, value);
                    input.dispatchEvent(new Event('input', {bubbles: true}));
                    input.dispatchEvent(new Event('change', {bubbles: true}));
                    input.dispatchEvent(new FocusEvent('focusout', {bubbles: true}));
                };
                update(id, loginID);
                await new Promise(resolve => setTimeout(resolve, 150));
                id = document.querySelector('input#id[name=id][type=text]');
                secret = document.querySelector('input#password[name=password][type=password]');
                if (!id || id.value !== loginID || !secret || secret.disabled || secret.value) return 'manual';
                update(secret, password);
                await new Promise(resolve => setTimeout(resolve, 400));
                id = document.querySelector('input#id[name=id][type=text]');
                secret = document.querySelector('input#password[name=password][type=password]');
                const submit = document.querySelector('button[type=submit][aria-label="로그인"]');
                if (location.origin !== 'https://accounts.kt.com' || location.pathname !== '/login/id' || !id || !secret || !submit || submit.disabled || id.value !== loginID || secret.value !== password) return 'manual';
                submit.click(); return 'submitted';
                """
                webView.callAsyncJavaScript(script, arguments: ["loginID": credentials.loginID, "password": credentials.password], in: nil,
                    in: .page) { [weak self] result in
                    guard let self, self.generation == current else { return }
                    if case .success(let value) = result, value as? String == "submitted" { return }
                    self.status = "KT 로그인 확인 필요"; self.autoLoginPending = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
                    guard let self, self.generation == current, self.status == "KT 자동 로그인 중" else { return }
                    self.status = "KT 로그인 확인 필요"
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        status = "KT 조회 실패"; scheduleRefresh(after: 300)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { self.webView(webView, didFailProvisionalNavigation: navigation, withError: error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { status = "KT 조회 실패"; scheduleRefresh(after: 300) }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }; return nil
    }
}

struct KTUsageButton: View {
    @ObservedObject var controller: KTUsageController
    private var detail: String {
        let saved = controller.sessionSaved ? "" : " · 로그인 복원 저장 실패"
        guard let updated = controller.updatedAt, controller.sharedData != nil else { return controller.status + saved }
        return "\(controller.status) · 마지막 조회 \(updated.formatted(date: .omitted, time: .standard))" + saved
    }
    var body: some View {
        Button { controller.open() } label: {
            HStack(spacing: 4) {
                Image(systemName: "personalhotspot")
                Text(controller.sharedData.map { "KT \($0.remaining)" } ?? controller.status).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).help(detail).accessibilityLabel("KT 공유·테더링 데이터").accessibilityValue(detail)
    }
}

struct CarrierUsageControl: View {
    @ObservedObject var skt: SKTUsageController
    @ObservedObject var kt: KTUsageController
    @AppStorage("rium.carrier.active") private var active = "skt"
    var body: some View {
        if active == "kt" { KTUsageButton(controller: kt) } else { SKTUsageButton(controller: skt) }
    }
}
