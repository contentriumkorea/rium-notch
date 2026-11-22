import AppKit
import CryptoKit
import Foundation
import Security

struct UpdateAsset {
    static let name = "Rium-Notch-macOS-arm64.dmg"
    let version: String
    let url: URL
    let size: Int
    let sha256: String

    init?(release: [String: Any], tag: String) {
        guard tag.hasPrefix("v"), UpdateController.version(tag) != nil,
              let assets = release["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == Self.name }),
              asset["state"] as? String == "uploaded",
              let size = asset["size"] as? Int, (1...134_217_728).contains(size),
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
              let raw = asset["browser_download_url"] as? String,
              raw == "https://github.com/contentriumkorea/rium-notch/releases/download/\(tag)/\(Self.name)",
              let url = URL(string: raw) else { return nil }
        let hash = digest.dropFirst(7)
        guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        self.version = String(tag.dropFirst())
        self.url = url
        self.size = size
        self.sha256 = String(hash)
    }

    func verify(_ archive: URL) throws {
        guard try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize == size else {
            throw UpdateInstaller.Failure.integrity
        }
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw UpdateInstaller.Failure.integrity }
    }
}

enum UpdateInstaller {
    private static let bundleID = "app.rium.notch"
    private static let stagingPrefix = ".rium-notch-update-"
    static let failureKey = "rium.update.installFailure"

    enum Failure: String, LocalizedError {
        case location = "앱을 쓰기 가능한 응용 프로그램 폴더에 복사한 뒤 업데이트해 주세요."
        case network = "업데이트를 다운로드하지 못했습니다. 잠시 후 다시 시도해 주세요."
        case integrity = "업데이트 파일이 손상되었거나 GitHub의 체크섬과 일치하지 않습니다."
        case package = "업데이트 설치 파일을 열 수 없습니다."
        case signature = "앱의 서명 또는 공증을 확인할 수 없습니다. 서명·공증된 Rium Notch 설치 파일이 필요합니다."
        case install = "업데이트 설치에 실패했습니다. 설치된 앱을 교체하지 않았습니다."
        case relaunch = "새 버전을 실행하지 못해 이전 버전으로 복구했습니다."
        case rollback = "앱을 자동으로 복구하지 못했습니다. 앱 옆의 업데이트 폴더에 이전 버전이 보관돼 있습니다."
        var errorDescription: String? { rawValue }
    }

    static func install(
        _ asset: UpdateAsset,
        progress: @escaping (String) -> Void,
        failed: @escaping (String) -> Void
    ) {
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard current.pathExtension == "app", !current.pathComponents.contains("AppTranslocation"),
              Bundle.main.bundleIdentifier == bundleID, let executable = Bundle.main.executableURL,
              FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            failed(Failure.location.rawValue)
            return
        }
        var request = URLRequest(url: asset.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Rium-Notch", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: request) { archive, response, error in
            DispatchQueue.main.async { progress("설치 파일 확인 중…") }
            do {
                guard error == nil, let archive, let http = response as? HTTPURLResponse,
                      http.statusCode == 200, http.url?.scheme == "https",
                      ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(http.url?.host ?? "") else {
                    throw Failure.network
                }
                let staging = try prepare(archive, asset: asset, current: current)
                do {
                    let helper = Process()
                    helper.executableURL = executable
                    helper.arguments = ["--finish-update", String(getpid()), staging.path, asset.version]
                    try helper.run()
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    throw Failure.install
                }
                DispatchQueue.main.async {
                    progress("\(asset.version) 설치 후 다시 실행합니다…")
                    NSApp.terminate(nil)
                }
            } catch {
                let message = (error as? Failure)?.rawValue ?? Failure.install.rawValue
                DispatchQueue.main.async { failed(message) }
            }
        }.resume()
    }

    static func prepare(_ archive: URL, asset: UpdateAsset, current: URL) throws -> URL {
        try asset.verify(archive)
        let files = FileManager.default
        let mount = files.temporaryDirectory.appendingPathComponent("rium-notch-mount-\(UUID())", isDirectory: true)
        try files.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var mounted = false
        defer {
            if !mounted || run("/usr/bin/hdiutil", ["detach", mount.path]) {
                try? files.removeItem(at: mount)
            }
        }
        mounted = run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, archive.path])
        guard mounted else { throw Failure.package }

        let staging = current.deletingLastPathComponent().appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let candidate = staging.appendingPathComponent(current.lastPathComponent, isDirectory: true)
            let source = mount.appendingPathComponent("Rium Notch.app", isDirectory: true)
            guard source.resolvingSymlinksInPath().deletingLastPathComponent().path == mount.resolvingSymlinksInPath().path else {
                throw Failure.package
            }
            try files.copyItem(at: source, to: candidate)
            try verify(candidate, replacing: current, version: asset.version)
            return staging
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }

    private static func verify(_ candidate: URL, replacing current: URL, version: String) throws {
        guard candidate.resolvingSymlinksInPath().path == candidate.path,
              let installed = Bundle(url: current), installed.bundleIdentifier == bundleID,
              let local = installed.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let localVersion = UpdateController.version(local), let remoteVersion = UpdateController.version(version),
              localVersion.lexicographicallyPrecedes(remoteVersion),
              let updated = Bundle(url: candidate), updated.bundleIdentifier == bundleID,
              updated.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              updated.executableArchitectures?.contains(NSNumber(value: NSBundleExecutableArchitectureARM64)) == true else {
            throw Failure.package
        }
        var oldCode: SecStaticCode?
        var requirement: SecRequirement?
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &oldCode) == errSecSuccess, let oldCode,
              SecCodeCopyDesignatedRequirement(oldCode, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(candidate as CFURL, [], &newCode) == errSecSuccess, let newCode,
              SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess,
              run("/usr/bin/syspolicy_check", ["distribution", candidate.path]) else {
            throw Failure.signature
        }
    }

    static func finish() {
        let args = CommandLine.arguments
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard args.count == 5, let parent = Int32(args[2]), parent > 1,
              getppid() == parent || (getppid() == 1 && kill(parent, 0) == -1 && errno == ESRCH),
              Bundle.main.bundleIdentifier == bundleID else { return }
        let staging = URL(fileURLWithPath: args[3], isDirectory: true).standardizedFileURL
        let folder = staging.lastPathComponent
        guard staging.deletingLastPathComponent().path == current.deletingLastPathComponent().path,
              staging.resolvingSymlinksInPath().path == staging.path,
              folder.hasPrefix(stagingPrefix),
              UUID(uuidString: String(folder.dropFirst(stagingPrefix.count))) != nil else { return }
        let waitUntil = ProcessInfo.processInfo.systemUptime + 20
        while getppid() == parent && ProcessInfo.processInfo.systemUptime < waitUntil {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard getppid() != parent else {
            try? FileManager.default.removeItem(at: staging)
            return
        }

        let candidate = staging.appendingPathComponent(current.lastPathComponent, isDirectory: true)
        let failure: Failure?
        do {
            try verify(candidate, replacing: current, version: args[4])
            failure = replace(current: current, candidate: candidate, launch: launch)
        } catch {
            failure = (error as? Failure) ?? .install
        }
        if failure != .rollback { try? FileManager.default.removeItem(at: staging) }
        if let failure {
            UserDefaults.standard.set(failure.rawValue, forKey: failureKey)
            UserDefaults.standard.synchronize()
            _ = launch(current)
        }
    }

    static func replace(current: URL, candidate: URL, launch: (URL) -> Bool) -> Failure? {
        guard renameatx_np(AT_FDCWD, current.path, AT_FDCWD, candidate.path, UInt32(RENAME_SWAP)) == 0 else {
            return .install
        }
        if launch(current) { return nil }
        return renameatx_np(AT_FDCWD, current.path, AT_FDCWD, candidate.path, UInt32(RENAME_SWAP)) == 0 ? .relaunch : .rollback
    }

    private static func launch(_ app: URL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        config.promptsUserIfNeeded = false
        var opened: NSRunningApplication?
        var completed = false
        NSWorkspace.shared.openApplication(at: app, configuration: config) { application, _ in
            DispatchQueue.main.async {
                opened = application
                completed = true
            }
        }
        while !completed { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let opened else { return false }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        return !opened.isTerminated
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
