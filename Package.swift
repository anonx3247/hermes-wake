// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "CipherVoice",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "cipher-voice", targets: ["CipherVoiceCLI"]),
    .library(name: "CipherVoiceCore", targets: ["CipherVoiceCore"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/k2-fsa/sherpa-onnx",
      revision: "634265c9b57642fdd158120148785c89aa281c4b"
    )
  ],
  targets: [
    .target(
      name: "CipherVoiceCore",
      dependencies: [
        .product(name: "sherpa-onnx", package: "sherpa-onnx")
      ]
    ),
    .executableTarget(
      name: "CipherVoiceCLI",
      dependencies: ["CipherVoiceCore"]
    ),
    .testTarget(
      name: "CipherVoiceCoreTests",
      dependencies: ["CipherVoiceCore"]
    ),
  ]
)
