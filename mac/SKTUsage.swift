import AppKit
import SwiftUI
import WebKit
import Security
import LocalAuthentication

// Persist only SKT web session cookies in the system keychain; never change their expiry.
enum SKTSessionStore {
    private static let service = "app.rium.notch.skt-session"
    private static let account = "T world"
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
    private static func query(service: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context]
    }
    static func save(_ cookies: [HTTPCookie], service: String = service) -> Bool {
        guard let data = encode(cookies) else { return false }
        let values = [kSecValueData as String: data] as CFDictionary
        let result = SecItemUpdate(query(service: service) as CFDictionary, values)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var item = query(service: service)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func load(service: String = service) -> [HTTPCookie] {
        var item = query(service: service)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return decode(data)
    }
    @discardableResult static func clear(service: String = service) -> Bool {
        let result = SecItemDelete(query(service: service) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
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

    func startIfConnected() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        restoringSession = true
        let store = browser().configuration.websiteDataStore.httpCookieStore
        sessionQueue.async { [weak self] in
            let cookies = SKTSessionStore.load()
            DispatchQueue.main.async {
                guard let self else { return }
                let pending = DispatchGroup()
                for cookie in cookies {
                    pending.enter()
                    store.setCookie(cookie) { pending.leave() }
                }
                pending.notify(queue: .main) {
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
        let view = WKWebView(frame: .zero, configuration: configuration)
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
            disconnect.bezelStyle = .rounded
            browser.translatesAutoresizingMaskIntoConstraints = false
            close.translatesAutoresizingMaskIntoConstraints = false
            disconnect.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(browser)
            content.addSubview(close)
            content.addSubview(disconnect)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
                close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                disconnect.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                disconnect.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
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
        if let due = refreshDue, due <= Date(), UserDefaults.standard.bool(forKey: Self.enabledKey) {
            refresh()
        }
    }

    @objc private func disconnectAccount() {
        generation += 1
        timer?.invalidate(); refreshDue = nil
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
        sharedData = nil; updatedAt = nil; status = "SKT 연결"; sessionSaved = true
        sessionQueue.async { [weak self] in
            let cleared = SKTSessionStore.clear()
            DispatchQueue.main.async { if !cleared { self?.status = "SKT 저장 세션 삭제 실패" } }
        }
        guard let webView else { return }
        webView.stopLoading()
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            for cookie in cookies where SKTSessionStore.belongsToSKT(cookie.domain) { store.delete(cookie) }
        }
        webView.loadHTMLString("<html><body>SKT 연결이 해제되었습니다.</body></html>", baseURL: nil)
    }

    func refresh() {
        generation += 1
        timer?.invalidate(); refreshDue = nil
        status = "SKT 확인 중"
        browser().load(URLRequest(url: Self.balanceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, let host = url.host, SKTSessionStore.belongsToSKT(host),
           url.path.lowercased().contains("logout") {
            generation += 1
            sessionQueue.async { [weak self] in
                let cleared = SKTSessionStore.clear()
                DispatchQueue.main.async { if !cleared { self?.status = "SKT 저장 세션 삭제 실패" } }
            }
            UserDefaults.standard.removeObject(forKey: Self.enabledKey)
            sharedData = nil; updatedAt = nil; timer?.invalidate(); refreshDue = nil
            status = "SKT 연결"
            return
        }
        guard let url = webView.url, url.host?.lowercased() == "www.tworld.co.kr", url.path == "/web/myt-data/balance" else {
            if webView.url?.host?.lowercased() == "auth.skt-id.co.kr" {
                status = "SKT 로그인 필요"
                timer?.invalidate(); refreshDue = nil
            }
            if webView.url?.host?.lowercased() == "www.tworld.co.kr" {
                webView.evaluateJavaScript("Array.from(document.querySelectorAll('button')).some(b => b.innerText.trim() === '로그아웃')") { [weak self, weak webView] result, _ in
                    guard let self, let webView, result as? Bool == true, self.status == "SKT 로그인 필요" else { return }
                    webView.load(URLRequest(url: Self.balanceURL))
                }
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
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                self.scheduleRefresh()
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, generation == self.generation else { return }
                    self.sessionQueue.async { [weak self] in
                        let saved = SKTSessionStore.save(cookies)
                        DispatchQueue.main.async { self?.sessionSaved = saved }
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
