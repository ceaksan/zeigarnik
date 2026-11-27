import Testing
@testable import ZeigarnikCore

@Suite struct FetchFailureTests {
    @Test(arguments: [
        ("fatal: 'https://user:fake-token@host.example/repo'", "fatal: 'https://<redacted>@host.example/repo'"),
        ("https://fake-token@host.example", "https://<redacted>@host.example"),
        ("ssh://git@host.example/a https://u:p@other.example/b", "ssh://<redacted>@host.example/a https://<redacted>@other.example/b"),
        ("HTTPS://user:p%40ss@host.example/a\nhttps://:secret@host.example?x=1", "HTTPS://<redacted>@host.example/a\nhttps://<redacted>@host.example?x=1"),
        ("https://u:fake; token@host.example/a", "https://<redacted>@host.example/a"),
        ("fatal: 'https://u:fake'token@host.example/a'", "fatal: 'https://<redacted>@host.example/a'"),
        ("https://host.example/a git@host.example:a", "https://host.example/a git@host.example:a"),
        ("https://host.example/path@name", "https://host.example/path@name"),
        ("plain error", "plain error"),
    ])
    func scrubsURLUserinfo(input: String, expected: String) {
        #expect(scrubDiagnosticCredentials(input) == expected)
    }

    @Test(arguments: ["could not read Username", "terminal prompts disabled", "Authentication failed"])
    func httpsAuthenticationGuidance(_ phrase: String) {
        let raw = "fatal: \(phrase) for 'https://user:fake-token@host.example/repo'; retry"
        let expected = "fetch: needs authentication. The remote uses HTTPS and git has no stored credential, so use an SSH remote or a credential helper. (git: fatal: \(phrase) for 'https://<redacted>@host.example/repo', retry)"
        #expect(formatFetchFailure(raw) == expected)
    }

    @Test(arguments: ["Permission denied (publickey)", "Host key verification failed"])
    func sshAuthenticationGuidance(_ phrase: String) {
        #expect(formatFetchFailure(phrase) == "fetch: SSH authentication failed. Check the key or known_hosts for this remote. (git: \(phrase))")
    }

    @Test func unknownFailureKeepsTextWithoutCredentialsOrSeparators() {
        #expect(formatFetchFailure("fatal: connection reset") == "fetch: fatal: connection reset")
        #expect(formatFetchFailure("fatal: https://u:secret@host.example/r; connection reset") == "fetch: fatal: https://<redacted>@host.example/r, connection reset")
    }
}
