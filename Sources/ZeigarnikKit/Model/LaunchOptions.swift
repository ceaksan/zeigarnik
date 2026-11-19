import Foundation

/// Debug launch arguments for running the app on a separate data set, such as synthetic data for screenshots.
public enum LaunchOptions {
    public static func home(from arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "--home"), flag + 1 < arguments.count else { return nil }
        let path = arguments[flag + 1]
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
