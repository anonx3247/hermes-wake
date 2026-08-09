@preconcurrency import AVFoundation
import Foundation

@MainActor
public final class SpeechOutput: NSObject {
  public var onSpeakingChanged: (@Sendable (Bool) -> Void)?

  private let configuration: SpeechConfiguration
  private let synthesizer = AVSpeechSynthesizer()
  private var buffer = ""
  private var queuedChunks = 0

  public init(configuration: SpeechConfiguration) {
    self.configuration = configuration
    super.init()
    synthesizer.delegate = self
  }

  public static func availableVoices() -> [(name: String, language: String, identifier: String)] {
    AVSpeechSynthesisVoice.speechVoices()
      .map { ($0.name, $0.language, $0.identifier) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func append(delta: String) {
    guard configuration.enabled else { return }
    buffer += delta
    guard configuration.streamBySentence else { return }
    while let boundary = sentenceBoundary(in: buffer) {
      let chunk = String(buffer[...boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
      buffer.removeSubrange(...boundary)
      enqueue(chunk)
    }
  }

  public func finish() {
    let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    buffer = ""
    enqueue(remainder)
  }

  public func speak(_ text: String) {
    stop()
    enqueue(text)
  }

  public func stop() {
    buffer = ""
    queuedChunks = 0
    synthesizer.stopSpeaking(at: .immediate)
    onSpeakingChanged?(false)
  }

  public var isSpeaking: Bool { synthesizer.isSpeaking }

  private func enqueue(_ text: String) {
    guard configuration.enabled, !text.isEmpty else { return }
    let utterance = AVSpeechUtterance(string: text)
    if let identifier = configuration.voiceIdentifier {
      utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
    }
    utterance.rate = configuration.rate
    utterance.volume = configuration.volume
    queuedChunks += 1
    synthesizer.speak(utterance)
  }

  private func sentenceBoundary(in text: String) -> String.Index? {
    for index in text.indices where ".!?\n".contains(text[index]) {
      let next = text.index(after: index)
      if next == text.endIndex || text[next].isWhitespace { return index }
    }
    return nil
  }

}

extension SpeechOutput: @preconcurrency AVSpeechSynthesizerDelegate {
  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
  ) {
    onSpeakingChanged?(true)
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    queuedChunks = max(0, queuedChunks - 1)
    if queuedChunks == 0 { onSpeakingChanged?(false) }
  }

  public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    queuedChunks = 0
    onSpeakingChanged?(false)
  }
}
