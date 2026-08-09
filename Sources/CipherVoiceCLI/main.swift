import AVFoundation
import CipherVoiceCore
import Foundation

private enum Command: String {
  case initialize = "init"
  case doctor
  case listen
}

@main
struct CipherVoiceCLI {
  static func main() {
    do {
      let command = Command(rawValue: CommandLine.arguments.dropFirst().first ?? "listen")
      switch command {
      case .initialize:
        try initializeConfiguration()
      case .doctor:
        try doctor()
      case .listen:
        try listen()
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
    let url = CipherVoiceConfiguration.defaultURL
    guard !FileManager.default.fileExists(atPath: url.path) else {
      print("Configuration already exists: \(url.path)")
      return
    }
    try CipherVoiceConfiguration().save(to: url)
    print("Created \(url.path)")
    print("Next: ./scripts/setup-wake-model.sh")
  }

  private static func doctor() throws {
    let config = try CipherVoiceConfiguration.load().validated()
    let model = config.modelDirectory.expandingTilde
    let checks = [
      CipherVoiceConfiguration.defaultURL.path,
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
    if failed {
      throw NSError(
        domain: "CipherVoiceDoctor",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Setup is incomplete. Run ./scripts/setup-wake-model.sh"
        ]
      )
    }
    _ = try SherpaWakeWordEngine(configuration: config)
    print("✓ sherpa-onnx loaded the wake-word model")
    print("Wake-word setup is ready.")
  }

  private static func listen() throws {
    let config = try CipherVoiceConfiguration.load().validated()
    guard requestMicrophonePermission() else { throw MicrophoneError.permissionDenied }

    let detector = try SherpaWakeWordEngine(configuration: config)
    let listener = MicrophoneListener()
    try listener.start(detector: detector) { phrase in
      let timestamp = ISO8601DateFormatter().string(from: Date())
      print("[\(timestamp)] Wake phrase detected: \(phrase)")
      fflush(stdout)
    }

    print("Listening for: \(config.wakePhrases.map(\.text).joined(separator: ", "))")
    print("Press Control-C to stop.")
    RunLoop.current.run()
  }

  private static func requestMicrophonePermission() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      let semaphore = DispatchSemaphore(value: 0)
      var granted = false
      AVCaptureDevice.requestAccess(for: .audio) {
        granted = $0
        semaphore.signal()
      }
      semaphore.wait()
      return granted
    default:
      return false
    }
  }

  private static func printUsage() {
    print(
      """
      Usage: cipher-voice [init|doctor|listen]

        init    Create ~/.config/cipher-voice/config.json
        doctor  Verify configuration, model, and keyword files
        listen  Listen continuously for configured wake phrases (default)
      """)
  }
}
