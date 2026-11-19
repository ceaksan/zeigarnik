import SwiftUI

enum AboutLinks {
    static let livingArchitecture = URL(string: "https://lab.ceaksan.com/architecture/")!
    static let labPage = URL(string: "https://lab.ceaksan.com/zeigarnik/")!
    static let labPageLive = true
    static let website = URL(string: "https://ceaksan.com")!
    static let x = URL(string: "https://x.com/ceaksan")!
    static let linkedIn = URL(string: "https://www.linkedin.com/in/ceaksan/")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/AoB4HUniY")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
