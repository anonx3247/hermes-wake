import AVFoundation
import CoreML
import FluidAudio
import Foundation

public actor StreamingTranscriber {
  public typealias TranscriptHandler = @Sendable (String) -> Void

  private let manager: StreamingEouAsrManager
  private var partialHandler: TranscriptHandler?
  private var endHandler: TranscriptHandler?

  public init(eouDebounceMs: Int) {
    let modelConfiguration = MLModelConfiguration()
    modelConfiguration.computeUnits = .all
    manager = StreamingEouAsrManager(
      configuration: modelConfiguration,
      chunkSize: .ms160,
      eouDebounceMs: eouDebounceMs
    )
  }

  public func loadModels(from configuredDirectory: String = "") async throws {
    if configuredDirectory.isEmpty {
      try await manager.loadModels()
    } else {
      try await manager.loadModels(from: URL(fileURLWithPath: configuredDirectory.expandingTilde))
    }
    await manager.setPartialCallback { [weak self] transcript in
      Task { await self?.emitPartial(transcript) }
    }
    await manager.setEouCallback { [weak self] transcript in
      Task { await self?.emitEnd(transcript) }
    }
  }

  public func setHandlers(partial: TranscriptHandler?, endOfUtterance: TranscriptHandler?) {
    partialHandler = partial
    endHandler = endOfUtterance
  }

  public func process(samples: [Float]) async throws {
    guard !samples.isEmpty,
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let destination = buffer.floatChannelData?.pointee
    else { return }
    destination.update(from: samples, count: samples.count)
    buffer.frameLength = AVAudioFrameCount(samples.count)
    _ = try await manager.process(audioBuffer: buffer)
  }

  public func reset() async {
    await manager.reset()
  }

  private func emitPartial(_ transcript: String) {
    partialHandler?(transcript)
  }

  private func emitEnd(_ transcript: String) {
    endHandler?(transcript)
  }
}
