import AppKit
import Foundation

public enum InteractionMode: String, Codable, Sendable {
  case turn
  case conversation
}

public enum ConversationState: Equatable, Sendable {
  case idle
  case listening
  case waitingForAgent
  case speaking
  case paused
}

@MainActor
public final class VoiceConversationCoordinator {
  public private(set) var state: ConversationState = .idle
  public private(set) var mode: InteractionMode = .turn
  public var onPartialTranscript: (@Sendable (String) -> Void)?
  public var onStatus: (@Sendable (String) -> Void)?

  private let configuration: HermesWakeConfiguration
  private let transcriber: StreamingTranscriber
  private let hermes: RemoteHermesClient
  private let speech: SpeechOutput
  private let commands: VoiceCommandInterpreter
  private var session: HermesSession?
  private var bargeInFrames = 0
  private var responseReceived = false

  public init(
    configuration: HermesWakeConfiguration,
    transcriber: StreamingTranscriber,
    hermes: RemoteHermesClient,
    speech: SpeechOutput
  ) {
    self.configuration = configuration
    self.transcriber = transcriber
    self.hermes = hermes
    self.speech = speech
    commands = VoiceCommandInterpreter(configuration: configuration.commands)

    speech.onSpeakingChanged = { [weak self] speaking in
      Task { @MainActor in self?.speakingChanged(speaking) }
    }
  }

  public func start() async throws {
    try await transcriber.loadModels(from: configuration.transcriptionModelDirectory)
    await transcriber.setHandlers(
      partial: { [weak self] text in
        Task { @MainActor in self?.receivePartial(text) }
      },
      endOfUtterance: { [weak self] text in
        Task { @MainActor in await self?.receiveFinal(text) }
      }
    )
    await hermes.setEventHandler { [weak self] event in
      Task { @MainActor in self?.receiveHermesEvent(event) }
    }
    try await hermes.connect()
    session = try await restoreOrCreateSession()
    status("Ready; waiting for a wake phrase")
  }

  public func wake(phrase: String) {
    guard state == .idle || state == .paused else { return }
    state = .listening
    playSound(named: "Tink")
    status("Listening after \(phrase)")
    Task { await transcriber.reset() }
  }

  public func processAudio(_ samples: [Float]) {
    switch state {
    case .listening:
      Task { try? await transcriber.process(samples: samples) }
    case .waitingForAgent where mode == .conversation:
      Task { try? await transcriber.process(samples: samples) }
    case .speaking where mode == .conversation:
      processBargeIn(samples)
    case .idle, .paused, .waitingForAgent, .speaking:
      break
    }
  }

  private func processBargeIn(_ samples: [Float]) {
    let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
    bargeInFrames = rms >= configuration.interaction.bargeInRMS ? bargeInFrames + 1 : 0
    guard bargeInFrames >= 3 else { return }
    bargeInFrames = 0
    speech.stop()
    state = .listening
    status("Barge-in detected; listening")
    if let session { Task { try? await hermes.interrupt(sessionID: session.runtimeID) } }
    Task {
      await transcriber.reset()
      try? await transcriber.process(samples: samples)
    }
  }

  private func receivePartial(_ text: String) {
    onPartialTranscript?(text)
  }

  private func receiveFinal(_ rawText: String) async {
    let text = stripWakePhrase(from: rawText).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      await transcriber.reset()
      return
    }
    playSound(named: "Pop")
    onPartialTranscript?(text)

    if let command = commands.command(for: text) {
      await execute(command)
      return
    }

    guard let session else {
      status("No Hermes session is available")
      state = .idle
      return
    }

    if mode == .conversation, state == .waitingForAgent {
      try? await hermes.interrupt(sessionID: session.runtimeID)
    }
    state = .waitingForAgent
    responseReceived = false
    await transcriber.reset()
    do {
      try await hermes.submit(text, sessionID: session.runtimeID)
      status("Sent to Hermes")
    } catch {
      status(error.localizedDescription)
      state = mode == .conversation ? .listening : .idle
    }
  }

  private func execute(_ command: VoiceCommand) async {
    switch command {
    case .newConversation:
      if let session { try? await hermes.interrupt(sessionID: session.runtimeID) }
      do {
        session = try await hermes.createSession(
          title: configuration.interaction.sessionTitle, source: "voice")
        try persistSession()
        status("Started a new conversation")
      } catch { status(error.localizedDescription) }
      state = mode == .conversation ? .listening : .idle
    case .stop:
      if let session { try? await hermes.interrupt(sessionID: session.runtimeID) }
      speech.stop()
      mode = .turn
      state = .idle
      status("Stopped; waiting for the wake phrase")
    case .pause:
      speech.stop()
      state = .paused
      status("Paused; say the wake phrase when you return")
    case .resume:
      mode = .conversation
      state = .listening
      status("Conversation resumed")
    case .conversationMode:
      mode = .conversation
      state = .listening
      status("Conversation mode; wake phrase no longer required")
    case .turnMode:
      mode = .turn
      state = .idle
      status("Turn mode; wake phrase required")
    case .sleep:
      speech.stop()
      mode = .turn
      state = .idle
      status("Sleeping; waiting for the wake phrase")
    }
    await transcriber.reset()
  }

  private func receiveHermesEvent(_ event: HermesEvent) {
    guard event.sessionID == session?.runtimeID || event.sessionID == nil else { return }
    switch event.type {
    case "message.delta":
      guard let text = event.payload["text"]?.string else { return }
      responseReceived = true
      print(text, terminator: "")
      fflush(stdout)
      if configuration.speech.enabled {
        state = .speaking
        speech.append(delta: text)
      }
    case "message.complete":
      print()
      if configuration.speech.enabled, responseReceived {
        speech.finish()
      } else {
        finishResponse()
      }
    case "approval.request", "clarify.request", "sudo.request", "secret.request":
      status("Hermes needs input in the desktop app: \(event.type)")
    case "error":
      status(event.payload["message"]?.string ?? "Hermes reported an error")
      finishResponse()
    default:
      break
    }
  }

  private func speakingChanged(_ speaking: Bool) {
    if speaking {
      state = .speaking
    } else if state == .speaking {
      finishResponse()
    }
  }

  private func finishResponse() {
    state = mode == .conversation ? .listening : .idle
    status(mode == .conversation ? "Listening for the next turn" : "Waiting for the wake phrase")
    Task { await transcriber.reset() }
  }

  private func restoreOrCreateSession() async throws -> HermesSession {
    if let stored = try? Data(contentsOf: Self.sessionURL),
      let previous = try? JSONDecoder().decode(HermesSession.self, from: stored),
      let resumed = try? await hermes.resumeSession(previous.storedID, source: "voice")
    {
      return resumed
    }
    let created = try await hermes.createSession(
      title: configuration.interaction.sessionTitle, source: "voice")
    session = created
    try persistSession()
    return created
  }

  private func persistSession() throws {
    guard let session else { return }
    try FileManager.default.createDirectory(
      at: Self.sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(session).write(to: Self.sessionURL, options: .atomic)
  }

  private static var sessionURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local/state/hermes-wake/session.json")
  }

  private func stripWakePhrase(from text: String) -> String {
    var result = text
    for phrase in configuration.wakePhrases {
      if result.lowercased().hasPrefix(phrase.text.lowercased()) {
        result.removeFirst(min(result.count, phrase.text.count))
      }
    }
    return result
  }

  private func status(_ message: String) {
    onStatus?(message)
  }

  private func playSound(named name: String) {
    NSSound(named: NSSound.Name(name))?.play()
  }
}
