import AVFoundation
import Darwin
import Foundation
import HermesWakeCore

private enum Command: String {
  case initialize = "init"
  case doctor
  case listen
  case voices
  case models
  case remote
}

@main
@MainActor
struct HermesWakeCLI {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      let command = Command(rawValue: arguments.first ?? "listen")
      switch command {
      case .initialize: try initializeConfiguration()
      case .doctor: try await doctor()
      case .listen: try await listen()
      case .voices: listVoices()
      case .models: try await downloadModels()
      case .remote: try await remote(arguments: Array(arguments.dropFirst()))
      case nil:
        printUsage()
        Foundation.exit(2)
      }
    } catch {
      fputs("error: \(error.localizedDescription)\n", stderr)
      Foundation.exit(1)
    }
  }

  private static func initializeConfiguration() throws {
    let url = HermesWakeConfiguration.defaultURL
    guard !FileManager.default.fileExists(atPath: url.path) else {
      print("Configuration already exists: \(url.path)")
      return
    }
    var configuration = HermesWakeConfiguration()
    if let remoteURL = desktopRemoteURL() {
      configuration.remote.baseURL = remoteURL
    }
    try configuration.save(to: url)
    print("Created \(url.path)")
    print("Next: ./scripts/setup-wake-model.sh")
  }

  private static func remote(arguments: [String]) async throws {
    guard arguments.first == "login" else {
      print("Usage: hermes-wake remote login --username USER [--url URL]")
      return
    }
    let username = value(after: "--username", in: arguments) ?? prompt("Username: ")
    guard !username.isEmpty else { throw RemoteHermesError.missingCredentials }
    var configuration = (try? HermesWakeConfiguration.load()) ?? HermesWakeConfiguration()
    configuration.remote.username = username
    configuration.remote.baseURL =
      value(after: "--url", in: arguments)
      ?? configuration.remote.baseURL.nilIfEmpty
      ?? desktopRemoteURL()
      ?? ""
    guard !configuration.remote.baseURL.isEmpty else { throw RemoteHermesError.invalidURL }

    guard let pointer = getpass("Password (stored in macOS Keychain): ") else {
      throw RemoteHermesError.missingCredentials
    }
    let password = String(cString: pointer)
    guard !password.isEmpty else { throw RemoteHermesError.missingCredentials }
    let credentials = KeychainCredentialStore()
    try credentials.save(password: password, for: username)
    try configuration.save()
    let client = RemoteHermesClient(configuration: configuration.remote, credentials: credentials)
    try await client.connect()
    await client.disconnect()
    print("Authenticated successfully with remote Hermes.")
    print("Saved remote URL and username to \(HermesWakeConfiguration.defaultURL.path)")
    print("Saved password to macOS Keychain service ai.hermes.wake.remote")
  }

  private static func doctor() async throws {
    let config = try HermesWakeConfiguration.load().validated()
    let model = config.modelDirectory.expandingTilde
    let checks = [
      HermesWakeConfiguration.defaultURL.path,
      "\(model)/encoder.int8.onnx",
      "\(model)/decoder.onnx",
      "\(model)/joiner.int8.onnx",
      "\(model)/tokens.txt",
      "\(model)/bpe.model",
      config.keywordsFile.expandingTilde,
    ]

    var failed = false
    for path in checks {
      let exists = FileManager.default.fileExists(atPath: path)
      print("\(exists ? "✓" : "✗") \(path)")
      failed = failed || !exists
    }
    print("Wake phrases: \(config.wakePhrases.map(\.text).joined(separator: ", "))")
    print("Remote URL: \(config.remote.baseURL.isEmpty ? "not configured" : config.remote.baseURL)")
    print(
      "Remote username: \(config.remote.username.isEmpty ? "not configured" : config.remote.username)"
    )
    if !config.remote.username.isEmpty {
      let hasPassword = try KeychainCredentialStore().password(for: config.remote.username) != nil
      print("\(hasPassword ? "✓" : "✗") remote password in macOS Keychain")
      failed = failed || !hasPassword
    } else {
      failed = true
    }
    if failed {
      throw NSError(
        domain: "HermesWakeDoctor",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Setup is incomplete. Run make setup and hermes-wake remote login."
        ]
      )
    }
    _ = try SherpaWakeWordEngine(configuration: config)
    print("✓ sherpa-onnx loaded the wake-word model")
    let remote = RemoteHermesClient(
      configuration: config.remote,
      credentials: KeychainCredentialStore()
    )
    try await remote.connect()
    await remote.disconnect()
    print("✓ authenticated WebSocket connection to remote Hermes")
    print("Hermes Wake setup is ready. FluidAudio models download on first listen.")
  }

  private static func listen() async throws {
    let configuration = try HermesWakeConfiguration.load().validated()
    guard await requestMicrophonePermission() else { throw MicrophoneError.permissionDenied }

    let detector = try SherpaWakeWordEngine(configuration: configuration)
    let transcriber = StreamingTranscriber(eouDebounceMs: configuration.interaction.eouDebounceMs)
    let hermes = RemoteHermesClient(
      configuration: configuration.remote,
      credentials: KeychainCredentialStore()
    )
    let speech = SpeechOutput(configuration: configuration.speech)
    let coordinator = VoiceConversationCoordinator(
      configuration: configuration,
      transcriber: transcriber,
      hermes: hermes,
      speech: speech
    )
    coordinator.onPartialTranscript = { text in
      print("\rYou: \(text)", terminator: "")
      fflush(stdout)
    }
    coordinator.onStatus = { message in
      print("\n[Hermes Wake] \(message)")
      fflush(stdout)
    }

    print("Loading local streaming speech model and connecting to remote Hermes...")
    try await coordinator.start()

    let listener = MicrophoneListener()
    try listener.start(
      detector: detector,
      onDetection: { phrase in
        Task { @MainActor in coordinator.wake(phrase: phrase) }
      },
      onAudio: { samples in
        Task { @MainActor in coordinator.processAudio(samples) }
      }
    )
    print("Listening for: \(configuration.wakePhrases.map(\.text).joined(separator: ", "))")
    print("Press Control-C to stop.")
    dispatchMain()
  }

  private static func downloadModels() async throws {
    let configuration = (try? HermesWakeConfiguration.load()) ?? HermesWakeConfiguration()
    let transcriber = StreamingTranscriber(eouDebounceMs: configuration.interaction.eouDebounceMs)
    print("Downloading and loading FluidAudio Parakeet EOU models...")
    try await transcriber.loadModels(from: configuration.transcriptionModelDirectory)
    print("Streaming transcription model is ready.")
  }

  private static func listVoices() {
    for voice in SpeechOutput.availableVoices() {
      print("\(voice.name)\t\(voice.language)\t\(voice.identifier)")
    }
  }

  private static func requestMicrophonePermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: true
    case .notDetermined:
      await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
      }
    default: false
    }
  }

  private static func desktopRemoteURL() -> String? {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Hermes/connection.json")
    guard let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let remote = object["remote"] as? [String: Any]
    else { return nil }
    return remote["url"] as? String
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func prompt(_ text: String) -> String {
    print(text, terminator: "")
    return readLine() ?? ""
  }

  private static func printUsage() {
    print(
      """
      Usage: hermes-wake [init|doctor|listen|voices|models|remote]

        init                                  Create the configuration
        doctor                                Verify local and remote setup
        listen                                Run the voice service (default)
        voices                                List installed macOS voices
        models                                Download/load streaming STT models
        remote login --username USER [--url]  Store remote login securely
      """)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
