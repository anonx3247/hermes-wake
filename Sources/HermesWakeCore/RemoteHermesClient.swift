import Foundation

public struct HermesEvent: Sendable {
  public let type: String
  public let sessionID: String?
  public let payload: [String: JSONValue]
}

public enum JSONValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(_ value: Any) {
    switch value {
    case let value as String: self = .string(value)
    case let value as NSNumber:
      self =
        CFGetTypeID(value) == CFBooleanGetTypeID()
        ? .bool(value.boolValue) : .number(value.doubleValue)
    case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
    case let value as [Any]: self = .array(value.map(JSONValue.init))
    default: self = .null
    }
  }

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }
}

public struct HermesSession: Codable, Equatable, Sendable {
  public let runtimeID: String
  public let storedID: String
}

public enum RemoteHermesError: LocalizedError {
  case invalidURL
  case missingCredentials
  case unauthorized
  case invalidResponse
  case disconnected
  case rpc(String)

  public var errorDescription: String? {
    switch self {
    case .invalidURL: "The remote Hermes URL is invalid."
    case .missingCredentials: "Remote Hermes username or password is missing."
    case .unauthorized: "Remote Hermes rejected the username or password."
    case .invalidResponse: "Remote Hermes returned an invalid response."
    case .disconnected: "The remote Hermes WebSocket is disconnected."
    case .rpc(let message): "Hermes RPC failed: \(message)"
    }
  }
}

public actor RemoteHermesClient {
  public typealias EventHandler = @Sendable (HermesEvent) -> Void

  private let configuration: RemoteConfiguration
  private let credentials: CredentialStoring
  private let cookieStorage = HTTPCookieStorage()
  private lazy var urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpCookieStorage = cookieStorage
    config.httpShouldSetCookies = true
    return URLSession(configuration: config)
  }()
  private var socket: URLSessionWebSocketTask?
  private var nextRequestID = 0
  private var pending: [Int: CheckedContinuation<[String: Any], any Error>] = [:]
  private var eventHandler: EventHandler?

  public init(configuration: RemoteConfiguration, credentials: CredentialStoring) {
    self.configuration = configuration
    self.credentials = credentials
  }

  public func setEventHandler(_ handler: EventHandler?) {
    eventHandler = handler
  }

  public func connect() async throws {
    guard socket == nil else { return }
    try await login()
    let ticket = try await mintWebSocketTicket()
    guard var components = URLComponents(string: configuration.baseURL),
      components.host != nil
    else { throw RemoteHermesError.invalidURL }
    components.scheme = components.scheme == "https" ? "wss" : "ws"
    let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [prefix, "api/ws"].filter { !$0.isEmpty }.joined(separator: "/")
    components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
    guard let url = components.url else { throw RemoteHermesError.invalidURL }
    let task = urlSession.webSocketTask(with: url)
    socket = task
    task.resume()
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      task.sendPing { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    Task { await self.receiveLoop() }
  }

  public func disconnect() {
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    failPending(with: RemoteHermesError.disconnected)
  }

  public func createSession(title: String, source: String = "voice") async throws -> HermesSession {
    var params: [String: Any] = ["title": title, "source": source]
    if let profile = configuration.profile { params["profile"] = profile }
    let result = try await request(method: "session.create", params: params)
    guard let runtimeID = result["session_id"] as? String,
      let storedID = result["stored_session_id"] as? String
    else { throw RemoteHermesError.invalidResponse }
    return HermesSession(runtimeID: runtimeID, storedID: storedID)
  }

  public func resumeSession(_ storedID: String, source: String = "voice") async throws
    -> HermesSession
  {
    var params: [String: Any] = ["session_id": storedID, "source": source]
    if let profile = configuration.profile { params["profile"] = profile }
    let result = try await request(method: "session.resume", params: params)
    guard let runtimeID = result["session_id"] as? String else {
      throw RemoteHermesError.invalidResponse
    }
    let durableID = (result["stored_session_id"] as? String) ?? storedID
    return HermesSession(runtimeID: runtimeID, storedID: durableID)
  }

  public func submit(_ text: String, sessionID: String) async throws {
    _ = try await request(
      method: "prompt.submit", params: ["session_id": sessionID, "text": text])
  }

  public func interrupt(sessionID: String) async throws {
    _ = try await request(method: "session.interrupt", params: ["session_id": sessionID])
  }

  private func login() async throws {
    guard let baseURL = URL(string: configuration.baseURL), !configuration.username.isEmpty,
      let password = try credentials.password(for: configuration.username), !password.isEmpty
    else { throw RemoteHermesError.missingCredentials }
    let url = baseURL.appending(path: "auth/password-login")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "provider": "basic",
      "username": configuration.username,
      "password": password,
      "next": "/",
    ])
    let (_, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw RemoteHermesError.invalidResponse }
    guard http.statusCode != 401 else { throw RemoteHermesError.unauthorized }
    guard (200..<300).contains(http.statusCode) else { throw RemoteHermesError.invalidResponse }
  }

  private func mintWebSocketTicket() async throws -> String {
    guard let baseURL = URL(string: configuration.baseURL) else {
      throw RemoteHermesError.invalidURL
    }
    var request = URLRequest(url: baseURL.appending(path: "api/auth/ws-ticket"))
    request.httpMethod = "POST"
    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let ticket = body["ticket"] as? String
    else { throw RemoteHermesError.unauthorized }
    return ticket
  }

  private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
    guard let socket else { throw RemoteHermesError.disconnected }
    nextRequestID += 1
    let id = nextRequestID
    let data = try JSONSerialization.data(withJSONObject: [
      "jsonrpc": "2.0", "id": id, "method": method, "params": params,
    ])
    guard let text = String(data: data, encoding: .utf8) else {
      throw RemoteHermesError.invalidResponse
    }

    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      Task {
        do {
          try await socket.send(.string(text))
        } catch {
          self.rejectRequest(id: id, error: error)
        }
      }
    }
  }

  private func receiveLoop() async {
    guard let socket else { return }
    do {
      while self.socket != nil {
        let message = try await socket.receive()
        switch message {
        case .string(let text): handle(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) { handle(text) }
        @unknown default: break
        }
      }
    } catch {
      self.socket = nil
      failPending(with: error)
    }
  }

  private func handle(_ text: String) {
    guard let data = text.data(using: .utf8),
      let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    if let id = frame["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
      if let error = frame["error"] as? [String: Any] {
        continuation.resume(
          throwing: RemoteHermesError.rpc(error["message"] as? String ?? "Unknown error"))
      } else {
        continuation.resume(returning: frame["result"] as? [String: Any] ?? [:])
      }
      return
    }

    guard frame["method"] as? String == "event",
      let params = frame["params"] as? [String: Any],
      let type = params["type"] as? String
    else { return }
    let payload = (params["payload"] as? [String: Any] ?? [:]).mapValues(JSONValue.init)
    eventHandler?(
      HermesEvent(type: type, sessionID: params["session_id"] as? String, payload: payload))
  }

  private func rejectRequest(id: Int, error: any Error) {
    pending.removeValue(forKey: id)?.resume(throwing: error)
  }

  private func failPending(with error: any Error) {
    let continuations = pending.values
    pending.removeAll()
    for continuation in continuations {
      continuation.resume(throwing: error)
    }
  }
}
