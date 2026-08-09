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

public struct RemoteConfiguration: Codable, Equatable, Sendable {
  public var baseURL: String
  public var username: String
  public var profile: String?

  public init(baseURL: String = "", username: String = "", profile: String? = nil) {
    self.baseURL = baseURL
    self.username = username
    self.profile = profile
  }
}

public struct SpeechConfiguration: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var voiceIdentifier: String?
  public var rate: Float
  public var volume: Float
  public var streamBySentence: Bool

  public init(
    enabled: Bool = true,
    voiceIdentifier: String? = nil,
    rate: Float = 0.5,
    volume: Float = 1,
    streamBySentence: Bool = true
  ) {
    self.enabled = enabled
    self.voiceIdentifier = voiceIdentifier
    self.rate = rate
    self.volume = volume
    self.streamBySentence = streamBySentence
  }
}

public struct InteractionConfiguration: Codable, Equatable, Sendable {
  public var eouDebounceMs: Int
  public var bargeInRMS: Float
  public var sessionTitle: String

  public init(
    eouDebounceMs: Int = 960,
    bargeInRMS: Float = 0.025,
    sessionTitle: String = "Voice conversation"
  ) {
    self.eouDebounceMs = eouDebounceMs
    self.bargeInRMS = bargeInRMS
    self.sessionTitle = sessionTitle
  }
}

public struct VoiceCommandConfiguration: Codable, Equatable, Sendable {
  public var newConversation: [String]
  public var stop: [String]
  public var pause: [String]
  public var resume: [String]
  public var conversationMode: [String]
  public var turnMode: [String]
  public var sleep: [String]

  public init(
    newConversation: [String] = ["new conversation", "new convo"],
    stop: [String] = ["stop", "cancel"],
    pause: [String] = ["pause", "take five", "hold on"],
    resume: [String] = ["resume", "continue", "i'm back"],
    conversationMode: [String] = ["run", "conversation mode", "keep listening"],
    turnMode: [String] = ["turn mode", "wake mode"],
    sleep: [String] = ["go to sleep", "sleep", "that's all"]
  ) {
    self.newConversation = newConversation
    self.stop = stop
    self.pause = pause
    self.resume = resume
    self.conversationMode = conversationMode
    self.turnMode = turnMode
    self.sleep = sleep
  }
}

public struct HermesWakeConfiguration: Codable, Equatable, Sendable {
  public var wakePhrases: [WakePhrase]
  public var modelDirectory: String
  public var keywordsFile: String
  public var transcriptionModelDirectory: String
  public var remote: RemoteConfiguration
  public var speech: SpeechConfiguration
  public var interaction: InteractionConfiguration
  public var commands: VoiceCommandConfiguration

  public init(
    wakePhrases: [WakePhrase] = [
      WakePhrase(text: "HEY CIPHER"),
      WakePhrase(text: "HEY SIPH"),
    ],
    modelDirectory: String = "~/.local/share/hermes-wake/models/kws-gigaspeech-3.3M",
    keywordsFile: String = "~/.config/hermes-wake/keywords.txt",
    transcriptionModelDirectory: String = "",
    remote: RemoteConfiguration = RemoteConfiguration(),
    speech: SpeechConfiguration = SpeechConfiguration(),
    interaction: InteractionConfiguration = InteractionConfiguration(),
    commands: VoiceCommandConfiguration = VoiceCommandConfiguration()
  ) {
    self.wakePhrases = wakePhrases
    self.modelDirectory = modelDirectory
    self.keywordsFile = keywordsFile
    self.transcriptionModelDirectory = transcriptionModelDirectory
    self.remote = remote
    self.speech = speech
    self.interaction = interaction
    self.commands = commands
  }

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/hermes-wake/config.json")
  }

  public static var legacyURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/cipher-voice/config.json")
  }

  public static func load(from url: URL = defaultURL) throws -> Self {
    let source = FileManager.default.fileExists(atPath: url.path) ? url : legacyURL
    let data = try Data(contentsOf: source)
    return try JSONDecoder().decode(Self.self, from: data)
  }

  public func save(to url: URL = defaultURL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
    guard interaction.eouDebounceMs >= 160 else {
      throw ConfigurationError.invalidEOUDebounce
    }
    return self
  }

  private enum CodingKeys: String, CodingKey {
    case wakePhrases, modelDirectory, keywordsFile, transcriptionModelDirectory
    case remote, speech, interaction, commands
  }

  public init(from decoder: Decoder) throws {
    let defaults = Self()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    wakePhrases =
      try values.decodeIfPresent([WakePhrase].self, forKey: .wakePhrases)
      ?? defaults.wakePhrases
    modelDirectory =
      try values.decodeIfPresent(String.self, forKey: .modelDirectory)
      ?? defaults.modelDirectory
    keywordsFile =
      try values.decodeIfPresent(String.self, forKey: .keywordsFile)
      ?? defaults.keywordsFile
    transcriptionModelDirectory =
      try values.decodeIfPresent(
        String.self, forKey: .transcriptionModelDirectory) ?? ""
    remote =
      try values.decodeIfPresent(RemoteConfiguration.self, forKey: .remote)
      ?? defaults.remote
    speech =
      try values.decodeIfPresent(SpeechConfiguration.self, forKey: .speech)
      ?? defaults.speech
    interaction =
      try values.decodeIfPresent(InteractionConfiguration.self, forKey: .interaction)
      ?? defaults.interaction
    commands =
      try values.decodeIfPresent(VoiceCommandConfiguration.self, forKey: .commands)
      ?? defaults.commands
  }
}

public enum ConfigurationError: LocalizedError {
  case noWakePhrases
  case invalidWakePhrase(String)
  case invalidThreshold(String)
  case invalidEOUDebounce

  public var errorDescription: String? {
    switch self {
    case .noWakePhrases: "At least one wake phrase is required."
    case .invalidWakePhrase(let phrase): "Wake phrase contains no letters or numbers: \(phrase)"
    case .invalidThreshold(let phrase):
      "Wake phrase threshold must be greater than 0 and at most 1: \(phrase)"
    case .invalidEOUDebounce: "End-of-utterance debounce must be at least 160 ms."
    }
  }
}

extension String {
  public var expandingTilde: String { NSString(string: self).expandingTildeInPath }
}
