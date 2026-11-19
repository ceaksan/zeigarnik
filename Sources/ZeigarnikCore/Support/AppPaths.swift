import Foundation

public enum AppPaths {
    public static func databaseURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Zeigarnik/zeigarnik.sqlite")
    }

    public static func ensureDatabaseDirectory(home: URL) throws -> URL {
        let url = databaseURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }
}
