import Foundation

public enum VoiceCommand: Equatable, Sendable {
  case newConversation
  case stop
  case pause
  case resume
  case conversationMode
  case turnMode
  case sleep
}

public struct VoiceCommandInterpreter: Sendable {
  private let phrases: [(String, VoiceCommand)]

  public init(configuration: VoiceCommandConfiguration) {
    phrases = [
      (configuration.newConversation, .newConversation),
      (configuration.stop, .stop),
      (configuration.pause, .pause),
      (configuration.resume, .resume),
      (configuration.conversationMode, .conversationMode),
      (configuration.turnMode, .turnMode),
      (configuration.sleep, .sleep),
    ].flatMap { entries, command in
      entries.map { (Self.normalize($0), command) }
    }
  }

  public func command(for transcript: String) -> VoiceCommand? {
    let normalized = Self.normalize(transcript)
    return phrases.first { phrase, _ in
      normalized == phrase || normalized.hasSuffix(" \(phrase)")
    }?.1
  }

  public static func normalize(_ text: String) -> String {
    text.lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
      .reduce(into: "") { $0.append($1) }
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}
