// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "HermesWake",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "hermes-wake", targets: ["HermesWakeCLI"]),
    .library(name: "HermesWakeCore", targets: ["HermesWakeCore"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/k2-fsa/sherpa-onnx",
      revision: "634265c9b57642fdd158120148785c89aa281c4b"
    ),
    .package(
      url: "https://github.com/FluidInference/FluidAudio",
      revision: "00a9aa771900ea09c485659663be31019e293e47"
    ),
  ],
  targets: [
    .target(
      name: "HermesWakeCore",
      dependencies: [
        .product(name: "sherpa-onnx", package: "sherpa-onnx"),
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      linkerSettings: [
        .linkedFramework("Security"),
        .linkedFramework("AppKit"),
      ]
    ),
    .executableTarget(
      name: "HermesWakeCLI",
      dependencies: ["HermesWakeCore"]
    ),
    .testTarget(
      name: "HermesWakeCoreTests",
      dependencies: ["HermesWakeCore"]
    ),
  ]
)
