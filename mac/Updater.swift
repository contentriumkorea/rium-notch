import AppKit
import Foundation
import Combine

final class UpdateController: ObservableObject {
    private static let api = URL(string: "https://api.github.com/repos/contentriumkorea/rium-notch/releases/latest")!
    private static let releasePrefix = "/contentriumkorea/rium-notch/releases/tag/"
    @Published private(set) var status = "GitHub에서 업데이트를 확인합니다."
    @Published private(set) var checking = false
    @Published private(set) var installing = false
    @Published private(set) var releaseURL: URL?
    @Published private(set) var autoCheck: Bool
    typealias Fetch = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void
    private let defaults: UserDefaults
    private let fetch: Fetch
    private let currentVersion: String
    private let installUpdate: (UpdateAsset, @escaping (String) -> Void, @escaping (String) -> Void) -> Void
    private var timer: Timer?
    private var recoveredInstall = false

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        fetch: @escaping Fetch = { request, done in URLSession.shared.dataTask(with: request, completionHandler: done).resume() },
        installUpdate: @escaping (UpdateAsset, @escaping (String) -> Void, @escaping (String) -> Void) -> Void = UpdateInstaller.install
    ) {
        self.defaults = defaults
        self.fetch = fetch
        self.installUpdate = installUpdate
        self.currentVersion = currentVersion ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
        self.autoCheck = defaults.object(forKey: "rium.update.autoCheck") as? Bool ?? true
        if let cached = defaults.data(forKey: "rium.update.cachedRelease") {
            let result = Self.parse(cached, current: self.currentVersion)
            if result.1 != nil { self.status = result.0; self.releaseURL = result.1 }
        }
        if let failure = defaults.string(forKey: UpdateInstaller.failureKey) {
            status = failure
            recoveredInstall = true
            defaults.removeObject(forKey: UpdateInstaller.failureKey)
        }
    }
    func start() {
        if autoCheck && !recoveredInstall { checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self = self, self.autoCheck else { return }
            self.checkIfDue()
        }
    }
    func setAutoCheck(_ value: Bool) {
        autoCheck = value
        defaults.set(value, forKey: "rium.update.autoCheck")
        if value { checkIfDue() }
    }
    private func checkIfDue() {
        if defaults.string(forKey: "rium.update.lastCheckedAppVersion") != currentVersion ||
            Self.isDue(last: defaults.double(forKey: "rium.update.lastCheck"), now: Date().timeIntervalSince1970) { check() }
    }
    static func isDue(last: Double, now: Double) -> Bool {
        !last.isFinite || last <= 0 || last > now || now - last >= 86400
    }
    func check(install: Bool = false) {
        guard !checking, !installing else { return }
        checking = true
        status = "업데이트 확인 중…"
        var request = URLRequest(url: Self.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Rium-Notch", forHTTPHeaderField: "User-Agent")
        fetch(request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer { self.checking = false }
                guard error == nil, let http = response as? HTTPURLResponse else {
                    self.status = "업데이트 확인에 실패했습니다. 네트워크를 확인해 주세요."
                    return
                }
                if http.statusCode == 404 {
                    self.status = "아직 공개된 릴리스가 없습니다."
                    self.releaseURL = nil
                    self.defaults.removeObject(forKey: "rium.update.cachedRelease")
                    self.defaults.set(Date().timeIntervalSince1970, forKey: "rium.update.lastCheck")
                    self.defaults.set(self.currentVersion, forKey: "rium.update.lastCheckedAppVersion")
                    return
                }
                guard http.statusCode == 200, let data = data, data.count <= 1_048_576 else {
                    self.status = "업데이트 정보를 확인할 수 없습니다."
                    return
                }
                let result = Self.parse(data, current: self.currentVersion)
                guard let url = result.1,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let cached = try? JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url.absoluteString, "draft": false, "prerelease": false]) else {
                    self.status = "릴리스 정보를 읽을 수 없습니다."
                    return
                }
                self.status = result.0; self.releaseURL = url
                self.defaults.set(cached, forKey: "rium.update.cachedRelease")
                self.defaults.set(Date().timeIntervalSince1970, forKey: "rium.update.lastCheck")
                self.defaults.set(self.currentVersion, forKey: "rium.update.lastCheckedAppVersion")
                guard let local = Self.version(self.currentVersion), let remote = Self.version(tag),
                      local.lexicographicallyPrecedes(remote) else { return }
                guard let asset = UpdateAsset(release: json, tag: tag) else {
                    if install { self.status = "\(tag) · 서명·공증된 업데이트 파일이 아직 없습니다." }
                    return
                }
                if install {
                    self.installing = true
                    self.status = "\(tag) 다운로드 중…"
                    self.installUpdate(asset, { [weak self] message in
                        self?.status = message
                    }, { [weak self] failure in
                        self?.installing = false
                        self?.status = failure
                    })
                }
            }
        }
    }

    static func parse(_ data: Data, current: String) -> (String, URL?) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["draft"] as? Bool == false, json["prerelease"] as? Bool == false,
              let tag = json["tag_name"] as? String, let remote = version(tag), let local = version(current),
              let raw = json["html_url"] as? String, let url = URL(string: raw),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.lowercased() == "github.com", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.fragment == nil,
              parts.path == releasePrefix + tag else { return ("릴리스 정보를 읽을 수 없습니다.", nil) }
        if remote.lexicographicallyPrecedes(local) || remote == local { return ("최신 릴리스: \(tag)", url) }
        return ("새 릴리스: \(tag)", url)
    }
    static func version(_ raw: String) -> [Int]? {
        let text = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let items = text.split(separator: ".", omittingEmptySubsequences: false)
        guard items.count == 3 else { return nil }
        var result: [Int] = []
        for item in items {
            guard !item.isEmpty, item.count <= 9, item.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(item) else { return nil }
            result.append(n)
        }
        return result
    }
    func openRelease() { if let url = releaseURL { NSWorkspace.shared.open(url) } }
}
