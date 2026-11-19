import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct LaunchOptionsTests {
    @Test func homeAfterTheFlagReplacesTheUserHome() {
        let home = LaunchOptions.home(from: ["Zeigarnik", "--home", "/Users/Shared/demo"])
        #expect(home == URL(fileURLWithPath: "/Users/Shared/demo", isDirectory: true))
    }

    @Test func missingEmptyOrRelativeValuesKeepTheUserHome() {
        #expect(LaunchOptions.home(from: ["Zeigarnik"]) == nil)
        #expect(LaunchOptions.home(from: ["Zeigarnik", "--home"]) == nil)
        #expect(LaunchOptions.home(from: ["Zeigarnik", "--home", ""]) == nil)
        #expect(LaunchOptions.home(from: ["Zeigarnik", "--home", "demo"]) == nil)
    }
}
