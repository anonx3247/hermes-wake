import Foundation

public struct WakePhrase: Codable, Equatable, Sendable {
  public var text: String
  public var score: Float
  public var threshold: Float

  public init(text: String, score: Float = 1.5, threshold: Float = 0.25) {
    self.text = text
    self.score = score
    self.threshold = threshold
  }

  public var identifier: String {
    text.lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .joined(separator: "_")
  }
}

public struct HermesConfiguration: Codable, Equatable, Sendable {
  public var baseURL: String
  public var conversation: String

  public init(
    baseURL: String = "https://your-hermes-node.your-tailnet.ts.net",
    conversation: String = "mac-voice-assistant"
  ) {
    self.baseURL = baseURL
    self.conversation = conversation
  }
}

public struct CipherVoiceConfiguration: Codable, Equatable, Sendable {
  public var wakePhrases: [WakePhrase]
  public var modelDirectory: String
  public var keywordsFile: String
  public var hermes: HermesConfiguration

  public init(
    wakePhrases: [WakePhrase] = [
      WakePhrase(text: "HEY CIPHER"),
      WakePhrase(text: "HEY SIPH"),
    ],
    modelDirectory: String = "~/.local/share/cipher-voice/models/kws-gigaspeech-3.3M",
    keywordsFile: String = "~/.config/cipher-voice/keywords.txt",
    hermes: HermesConfiguration = HermesConfiguration()
  ) {
    self.wakePhrases = wakePhrases
    self.modelDirectory = modelDirectory
    self.keywordsFile = keywordsFile
    self.hermes = hermes
  }

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/cipher-voice/config.json")
  }

  public static func load(from url: URL = defaultURL) throws -> Self {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Self.self, from: data)
  }

  public func save(to url: URL = defaultURL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(self).write(to: url, options: .atomic)
  }

  public func validated() throws -> Self {
    guard !wakePhrases.isEmpty else { throw ConfigurationError.noWakePhrases }
    for phrase in wakePhrases {
      guard !phrase.identifier.isEmpty else {
        throw ConfigurationError.invalidWakePhrase(phrase.text)
      }
      guard phrase.threshold > 0, phrase.threshold <= 1 else {
        throw ConfigurationError.invalidThreshold(phrase.text)
      }
    }
    return self
  }
}

public enum ConfigurationError: LocalizedError {
  case noWakePhrases
  case invalidWakePhrase(String)
  case invalidThreshold(String)

  public var errorDescription: String? {
    switch self {
    case .noWakePhrases:
      return "At least one wake phrase is required."
    case .invalidWakePhrase(let phrase):
      return "Wake phrase contains no letters or numbers: \(phrase)"
    case .invalidThreshold(let phrase):
      return "Wake phrase threshold must be greater than 0 and at most 1: \(phrase)"
    }
  }
}

extension String {
  public var expandingTilde: String {
    NSString(string: self).expandingTildeInPath
  }
}
