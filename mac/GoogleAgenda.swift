import Foundation
import AppKit
import CryptoKit
import LocalAuthentication
import Network
import Security

struct GoogleAgendaClient: Codable, Equatable {
    let client_id: String
    let client_secret: String

    static func configuration(from data: Data) throws -> Self {
        struct Download: Decodable { let installed: GoogleAgendaClient }
        let client = try JSONDecoder().decode(Download.self, from: data).installed
        guard client.client_id.hasSuffix(".apps.googleusercontent.com"), !client.client_secret.isEmpty
        else { throw GoogleAgendaError.configuration }
        return client
    }

    static let scopes = [
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/tasks"
    ]
    private static let http: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    func authorizationURL(redirect: String, state: String, verifier: String) -> URL {
        let challenge = googleBase64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            .init(name: "client_id", value: client_id), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account")
        ]
        return url.url!
    }

    func exchange(code: String, redirect: String, verifier: String) async throws -> GoogleAgendaToken {
        try await token(["grant_type": "authorization_code", "code": code,
                         "redirect_uri": redirect, "code_verifier": verifier], fallbackRefresh: nil)
    }

    func refresh(_ previous: GoogleAgendaToken) async throws -> GoogleAgendaToken {
        guard previous.expiresAt.timeIntervalSinceNow <= 60 else { return previous }
        return try await token(["grant_type": "refresh_token", "refresh_token": previous.refreshToken],
                               fallbackRefresh: previous.refreshToken)
    }

    private func token(_ fields: [String: String], fallbackRefresh: String?) async throws -> GoogleAgendaToken {
        struct Response: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
            let scope: String?
        }
        let fields = fields.merging(["client_id": client_id, "client_secret": client_secret]) { old, _ in old }
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }.joined(separator: "&")
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await Self.http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAgendaError.response }
        if http.statusCode == 400,
           (try? JSONDecoder().decode([String: String].self, from: data))?["error"] == "invalid_grant" {
            throw GoogleAgendaError.expired
        }
        guard http.statusCode == 200 else { throw GoogleAgendaError.http(http.statusCode) }
        let result = try JSONDecoder().decode(Response.self, from: data)
        if let scope = result.scope, !Set(Self.scopes).isSubset(of: Set(scope.split(separator: " ").map(String.init))) {
            throw GoogleAgendaError.permissions
        }
        guard let refresh = result.refresh_token ?? fallbackRefresh, !refresh.isEmpty else { throw GoogleAgendaError.expired }
        return GoogleAgendaToken(accessToken: result.access_token, refreshToken: refresh,
                                 expiresAt: Date().addingTimeInterval(result.expires_in))
    }

    static func request<T: Decodable>(_ type: T.Type, host: String, path: [String], token: String,
                                      query: [URLQueryItem] = [], method: String = "GET",
                                      body: [String: Any]? = nil) async throws -> T {
        let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~@")
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.percentEncodedPath = "/" + path.map { $0.addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? "" }.joined(separator: "/")
        url.queryItems = query.isEmpty ? nil : query
        guard let target = url.url else { throw GoogleAgendaError.response }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAgendaError.response }
        if http.statusCode == 401 { throw GoogleAgendaError.expired }
        guard (200..<300).contains(http.statusCode) else { throw GoogleAgendaError.http(http.statusCode) }
        return try JSONDecoder().decode(type, from: data)
    }

    static func pages<T: Decodable>(_ type: T.Type, host: String, path: [String], token: String,
                                    query: [URLQueryItem] = []) async throws -> [T] {
        var rows: [T] = []
        var next: String?
        var seen = Set<String>()
        repeat {
            var parameters = query
            if let next { parameters.append(.init(name: "pageToken", value: next)) }
            let page = try await request(GoogleAgendaPage<T>.self, host: host, path: path, token: token, query: parameters)
            rows.append(contentsOf: page.items ?? [])
            next = page.nextPageToken
            if let next, !seen.insert(next).inserted { throw GoogleAgendaError.response }
        } while next != nil
        return rows
    }
}

private struct GoogleAgendaPage<Row: Decodable>: Decodable {
    let items: [Row]?
    let nextPageToken: String?
}

struct GoogleAgendaToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum GoogleAgendaError: LocalizedError {
    case configuration, expired, permissions, response, listener, canceled, timedOut, storage, http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Google Cloud의 데스크톱 앱 OAuth JSON을 선택해 주세요."
        case .expired: return "Google 연결이 만료됐습니다. 다시 로그인해 주세요."
        case .permissions: return "Google 로그인에서 Calendar와 Tasks 권한을 모두 허용해 주세요."
        case .response: return "Google 응답을 읽지 못했습니다."
        case .listener: return "Google 로그인 창을 열 수 없습니다."
        case .canceled: return "Google 로그인이 취소됐습니다."
        case .timedOut: return "Google 로그인 시간이 초과됐습니다. 다시 시도해 주세요."
        case .storage: return "Google 연결 정보를 키체인에 저장하지 못했습니다."
        case .http(403): return "Google Cloud에서 API 활성화와 계정 권한을 확인해 주세요."
        case .http(let status): return "Google 요청을 완료하지 못했습니다 (\(status))."
        }
    }
}

private func googleBase64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

final class GoogleAgendaLogin {
    private var listener: NWListener?
    private var completion: ((Result<(String, String, String), Error>) -> Void)?
    private var timeout: DispatchWorkItem?

    func start(_ client: GoogleAgendaClient, open: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
               completion: @escaping (Result<(String, String, String), Error>) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let state = UUID().uuidString
        let verifier = googleBase64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
        self.listener = listener
        self.completion = completion
        listener.stateUpdateHandler = { [weak self, weak listener] status in
            switch status {
            case .ready:
                guard let port = listener?.port,
                      open(client.authorizationURL(redirect: Self.redirect(port), state: state, verifier: verifier))
                else { self?.finish(.failure(GoogleAgendaError.listener)); return }
            case .failed: self?.finish(.failure(GoogleAgendaError.listener))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            guard let self, let port = listener?.port else { connection.cancel(); return }
            connection.start(queue: .main)
            self.receive(connection, redirect: Self.redirect(port), state: state, verifier: verifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(GoogleAgendaError.timedOut)) }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)
        listener.start(queue: .main)
    }

    private static func redirect(_ port: NWEndpoint.Port) -> String { "http://127.0.0.1:\(port.rawValue)/google-oauth" }

    private func receive(_ connection: NWConnection, redirect: String, state: String, verifier: String, received: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - received.count) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            let buffer = received + (data ?? Data())
            guard let range = buffer.range(of: Data("\r\n".utf8)) else {
                if complete || buffer.count >= 8192 { connection.cancel() }
                else { self.receive(connection, redirect: redirect, state: state, verifier: verifier, received: buffer) }
                return
            }
            let line = String(decoding: buffer[..<range.lowerBound], as: UTF8.self).split(separator: " ")
            guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/google-oauth?"),
                  let request = URLComponents(string: String(line[1])),
                  request.queryItems?.first(where: { $0.name == "state" })?.value == state
            else { self.reply(connection, "Invalid request.", valid: false); return }
            if let code = request.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                self.reply(connection, "Google sign-in received. Return to Rium Notch.", valid: true)
                self.finish(.success((code, redirect, verifier)))
            } else {
                self.reply(connection, "Google sign-in canceled. Return to Rium Notch.", valid: true)
                self.finish(.failure(GoogleAgendaError.canceled))
            }
        }
    }

    private func reply(_ connection: NWConnection, _ message: String, valid: Bool) {
        let status = valid ? "200 OK" : "400 Bad Request"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(message.utf8.count)\r\nConnection: close\r\n\r\n\(message)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<(String, String, String), Error>) {
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
    deinit { listener?.cancel(); timeout?.cancel() }
}

enum GoogleAgendaKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.rium.notch.google-agenda",
         kSecAttrAccount as String: account]
    }
    static func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        var request = query(account)
        request[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = query(account)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        var item = query.merging(values) { old, _ in old }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard status == errSecItemNotFound, SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        else { throw GoogleAgendaError.storage }
    }
    static func disconnect() throws {
        let status = SecItemDelete(query("session") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GoogleAgendaError.storage }
    }
}
