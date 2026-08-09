import XCTest

@testable import HermesWakeCore

final class ConfigurationTests: XCTestCase {
  func testDefaultPhrasesIncludeCipherAliases() throws {
    let config = try HermesWakeConfiguration().validated()
    XCTAssertEqual(config.wakePhrases.map(\.identifier), ["hey_cipher", "hey_siph"])
  }

  func testConfigurationRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let expected = HermesWakeConfiguration()
    try expected.save(to: url)
    XCTAssertEqual(try HermesWakeConfiguration.load(from: url), expected)
  }

  func testRejectsEmptyPhraseList() {
    let config = HermesWakeConfiguration(wakePhrases: [])
    XCTAssertThrowsError(try config.validated())
  }

  func testLegacyConfigurationReceivesNewDefaults() throws {
    let data = Data(
      #"{"wakePhrases":[{"text":"HEY CIPHER","score":1.5,"threshold":0.25}],"modelDirectory":"~/old-model","keywordsFile":"~/old-keywords"}"#
        .utf8)
    let config = try JSONDecoder().decode(HermesWakeConfiguration.self, from: data)
    XCTAssertTrue(config.speech.enabled)
    XCTAssertEqual(config.commands.pause, ["pause", "take five", "hold on"])
    XCTAssertEqual(config.interaction.eouDebounceMs, 960)
  }
}
