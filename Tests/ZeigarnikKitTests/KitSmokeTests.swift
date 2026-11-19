import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct KitSmokeTests {
    @Test func kitReexportsCore() {
        #expect(AppPaths.databaseURL(home: URL(fileURLWithPath: "/h")).lastPathComponent == "zeigarnik.sqlite")
    }
}
