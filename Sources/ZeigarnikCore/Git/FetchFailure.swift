import Foundation

public func scrubDiagnosticCredentials(_ text: String) -> String {
    text.replacingOccurrences(of: #"([A-Za-z][A-Za-z0-9+.-]*://)[^\r\n/?#<>"]*@"#,
                              with: "$1<redacted>@", options: .regularExpression)
}

public func formatFetchFailure(_ text: String) -> String {
    let raw = scrubDiagnosticCredentials(text).replacingOccurrences(of: "; ", with: ", ")
    let lower = raw.lowercased()
    let guidance: String
    if ["permission denied (publickey)", "host key verification failed"].contains(where: lower.contains) {
        guidance = "SSH authentication failed. Check the key or known_hosts for this remote."
    } else if ["could not read username", "terminal prompts disabled", "authentication failed"].contains(where: lower.contains) {
        guidance = "needs authentication. The remote uses HTTPS and git has no stored credential, so use an SSH remote or a credential helper."
    } else {
        return "fetch: \(raw)"
    }
    return "fetch: \(guidance) (git: \(raw))"
}
