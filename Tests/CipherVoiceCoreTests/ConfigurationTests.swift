import XCTest

@testable import CipherVoiceCore

final class ConfigurationTests: XCTestCase {
  func testDefaultPhrasesIncludeCipherAliases() throws {
    let config = try CipherVoiceConfiguration().validated()
    XCTAssertEqual(config.wakePhrases.map(\.identifier), ["hey_cipher", "hey_siph"])
  }

  func testConfigurationRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let expected = CipherVoiceConfiguration()
    try expected.save(to: url)
    XCTAssertEqual(try CipherVoiceConfiguration.load(from: url), expected)
  }

  func testRejectsEmptyPhraseList() {
    let config = CipherVoiceConfiguration(wakePhrases: [])
    XCTAssertThrowsError(try config.validated())
  }
}
