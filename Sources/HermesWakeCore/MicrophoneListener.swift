@preconcurrency import AVFoundation
import Foundation

public enum MicrophoneError: LocalizedError {
  case permissionDenied
  case unsupportedInputFormat
  case converterCreationFailed
  case convertedBufferCreationFailed

  public var errorDescription: String? {
    switch self {
    case .permissionDenied: return "Microphone access was denied in System Settings."
    case .unsupportedInputFormat: return "The selected microphone has an unsupported audio format."
    case .converterCreationFailed: return "Could not create the 16 kHz audio converter."
    case .convertedBufferCreationFailed: return "Could not allocate a converted audio buffer."
    }
  }
}

public final class MicrophoneListener: @unchecked Sendable {
  private let audioEngine = AVAudioEngine()
  private let processingQueue = DispatchQueue(label: "ai.hermes.wake.audio-processing")
  private var converter: AVAudioConverter?
  private var detector: WakeWordDetecting?
  private var onDetection: (@Sendable (String) -> Void)?
  private var onAudio: (@Sendable ([Float]) -> Void)?

  public init() {}

  public func start(
    detector: WakeWordDetecting,
    onDetection: @escaping @Sendable (String) -> Void,
    onAudio: @escaping @Sendable ([Float]) -> Void = { _ in }
  ) throws {
    self.detector = detector
    self.onDetection = onDetection
    self.onAudio = onAudio

    let input = audioEngine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw MicrophoneError.unsupportedInputFormat
    }
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    else {
      throw MicrophoneError.unsupportedInputFormat
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw MicrophoneError.converterCreationFailed
    }
    self.converter = converter

    input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
      self?.convertAndProcess(buffer, outputFormat: outputFormat)
    }
    audioEngine.prepare()
    try audioEngine.start()
  }

  public func stop() {
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    detector = nil
    onDetection = nil
    onAudio = nil
    converter = nil
  }

  private func convertAndProcess(_ input: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
    guard let converter else { return }
    let ratio = outputFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      return
    }

    let supplier = ConverterInputSupplier(buffer: input)
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      supplier.next(status: status)
    }
    guard error == nil,
      output.frameLength > 0,
      let channel = output.floatChannelData?.pointee
    else { return }

    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    processingQueue.async { [weak self] in
      guard let self, let detector = self.detector else { return }
      self.onAudio?(samples)
      if let phrase = detector.process(samples: samples, sampleRate: 16_000) {
        self.onDetection?(phrase)
      }
    }
  }
}

private final class ConverterInputSupplier: @unchecked Sendable {
  private let buffer: AVAudioPCMBuffer
  private var supplied = false

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    guard !supplied else {
      status.pointee = .noDataNow
      return nil
    }
    supplied = true
    status.pointee = .haveData
    return buffer
  }
}
