import XCTest

@testable import HermesWakeCore

final class VoiceCommandInterpreterTests: XCTestCase {
  private let interpreter = VoiceCommandInterpreter(configuration: VoiceCommandConfiguration())

  func testConversationModeAliases() {
    XCTAssertEqual(interpreter.command(for: "run"), .conversationMode)
    XCTAssertEqual(interpreter.command(for: "please keep listening"), .conversationMode)
  }

  func testPauseAliases() {
    XCTAssertEqual(interpreter.command(for: "take five"), .pause)
    XCTAssertEqual(interpreter.command(for: "Hey Cipher, hold on!"), .pause)
  }

  func testSessionAndStopCommands() {
    XCTAssertEqual(interpreter.command(for: "new convo"), .newConversation)
    XCTAssertEqual(interpreter.command(for: "stop"), .stop)
    XCTAssertEqual(interpreter.command(for: "go to sleep"), .sleep)
  }

  func testNormalPromptIsNotACommand() {
    XCTAssertNil(interpreter.command(for: "run the unit tests"))
  }
}
