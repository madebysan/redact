import Foundation
import Testing
@testable import Redact

@Test func retiredVoiceCredentialsAreRemovedFromUserDefaults() throws {
    let suiteName = "redact-settings-security-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("secret", forKey: "elevenLabsApiKey")
    defaults.set("voice", forKey: "elevenLabsVoiceId")

    Settings.removeRetiredCredentialValues(from: defaults)

    #expect(defaults.string(forKey: "elevenLabsApiKey") == nil)
    #expect(defaults.string(forKey: "elevenLabsVoiceId") == nil)
}
