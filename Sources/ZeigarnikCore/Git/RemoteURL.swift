import Foundation

/// Removes userinfo (user, password, token) from URL-style remotes. scp-style remotes are returned unchanged.
public func sanitizeRemoteURL(_ url: String) -> String {
    guard let schemeRange = url.range(of: "://") else { return url }
    let afterScheme = url[schemeRange.upperBound...]
    let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
    let authority = afterScheme[..<authorityEnd]
    guard let at = authority.lastIndex(of: "@") else { return url }
    return String(url[..<schemeRange.upperBound]) + String(afterScheme[afterScheme.index(after: at)...])
}
