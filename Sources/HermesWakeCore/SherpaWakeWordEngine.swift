import Foundation
import SherpaOnnx

public protocol WakeWordDetecting: AnyObject {
  func process(samples: [Float], sampleRate: Int) -> String?
}

public enum WakeEngineError: LocalizedError {
  case missingFile(String)

  public var errorDescription: String? {
    switch self {
    case .missingFile(let path): return "Required wake-word file is missing: \(path)"
    }
  }
}

public final class SherpaWakeWordEngine: WakeWordDetecting {
  private let spotter: SherpaOnnxKeywordSpotterWrapper

  public init(configuration: HermesWakeConfiguration) throws {
    let modelDirectory = configuration.modelDirectory.expandingTilde
    let encoder = "\(modelDirectory)/encoder.int8.onnx"
    let decoder = "\(modelDirectory)/decoder.onnx"
    let joiner = "\(modelDirectory)/joiner.int8.onnx"
    let tokens = "\(modelDirectory)/tokens.txt"
    let keywords = configuration.keywordsFile.expandingTilde

    for path in [encoder, decoder, joiner, tokens, keywords] {
      guard FileManager.default.fileExists(atPath: path) else {
        throw WakeEngineError.missingFile(path)
      }
    }

    let transducer = sherpaOnnxOnlineTransducerModelConfig(
      encoder: encoder,
      decoder: decoder,
      joiner: joiner
    )
    let model = sherpaOnnxOnlineModelConfig(
      tokens: tokens,
      transducer: transducer,
      numThreads: 1,
      provider: "cpu"
    )
    let features = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
    var config = sherpaOnnxKeywordSpotterConfig(
      featConfig: features,
      modelConfig: model,
      keywordsFile: keywords,
      maxActivePaths: 4,
      numTrailingBlanks: 1
    )
    spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)
  }

  public func process(samples: [Float], sampleRate: Int = 16_000) -> String? {
    spotter.acceptWaveform(samples: samples, sampleRate: sampleRate)
    while spotter.isReady() {
      spotter.decode()
      let keyword = spotter.getResult().keyword
      if !keyword.isEmpty {
        spotter.reset()
        return keyword.replacingOccurrences(of: "_", with: " ")
      }
    }
    return nil
  }
}
