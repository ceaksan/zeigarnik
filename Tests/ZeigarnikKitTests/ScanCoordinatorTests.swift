import Foundation
import Testing
@testable import ZeigarnikKit

actor FakeScanner: Scanning {
    private(set) var calls: [Bool] = []
    private var gates: [CheckedContinuation<Void, Never>] = []
    var blocking = true

    func scan(fetch: Bool) async -> ScanReport {
        calls.append(fetch)
        if blocking { await withCheckedContinuation { gates.append($0) } }
        return ScanReport(startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 1),
                          projects: calls.count, errors: [], openNow: .unknown("test"))
    }

    func release() {
        let open = gates
        gates = []
        open.forEach { $0.resume() }
    }

    func setBlocking(_ value: Bool) { blocking = value }
    func waiting() -> Int { gates.count }
}

@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor @Suite struct ScanCoordinatorTests {
    @Test func overlappingRequestsCoalesce() async {
        let scanner = FakeScanner()
        var finished = 0
        let coordinator = ScanCoordinator(scanner: scanner, openNowProvider: nil) { _ in finished += 1 }
        coordinator.requestScan(fetch: false)
        await eventually { await scanner.waiting() == 1 }
        coordinator.requestScan(fetch: false)
        coordinator.requestScan(fetch: false)
        coordinator.requestScan(fetch: false)
        await scanner.release()
        await eventually { await scanner.waiting() == 1 }
        await scanner.release()
        await eventually { finished == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await scanner.calls.count == 2)
        #expect(!coordinator.isScanning)
    }

    @Test func followUpKeepsFetchIfAnyRequestWanted() async {
        let scanner = FakeScanner()
        let coordinator = ScanCoordinator(scanner: scanner, openNowProvider: nil) { _ in }
        coordinator.requestScan(fetch: false)
        await eventually { await scanner.waiting() == 1 }
        coordinator.requestScan(fetch: false)
        coordinator.requestScan(fetch: true)
        await scanner.release()
        await eventually { await scanner.waiting() == 1 }
        await scanner.release()
        #expect(await scanner.calls == [false, true])
    }

    @Test func tickStartsScanWhenIdleAndIsIgnoredWhileScanning() async {
        let scanner = FakeScanner()
        let coordinator = ScanCoordinator(scanner: scanner, openNowProvider: nil) { _ in }
        coordinator.tick()
        await eventually { await scanner.waiting() == 1 }
        #expect(coordinator.isScanning)
        coordinator.tick()
        await scanner.release()
        await eventually { !coordinator.isScanning }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await scanner.calls == [true])
    }

    @Test func onFinishReceivesReport() async {
        let scanner = FakeScanner()
        await scanner.setBlocking(false)
        var reports: [Int] = []
        let coordinator = ScanCoordinator(scanner: scanner, openNowProvider: nil) { reports.append($0.projects) }
        coordinator.requestScan(fetch: true)
        await eventually { reports.count == 1 }
        #expect(reports == [1])
        #expect(coordinator.lastReport?.projects == 1)
    }

    @Test func openNowComesFromProvider() async {
        let coordinator = ScanCoordinator(scanner: FakeScanner(), openNowProvider: { .unknown("x") }) { _ in }
        #expect(coordinator.openNow == nil)
        await coordinator.refreshOpenNow()
        #expect(coordinator.openNow == .unknown("x"))
    }
    @Test func replacedScannerRunsTheFollowUp() async {
        let old = FakeScanner()
        let new = FakeScanner()
        await new.setBlocking(false)
        var finished = 0
        let coordinator = ScanCoordinator(scanner: old, openNowProvider: { .unknown("old") }) { _ in finished += 1 }
        coordinator.requestScan(fetch: false)
        await eventually { await old.waiting() == 1 }
        coordinator.replaceScanner(new, openNowProvider: { .unknown("new") })
        coordinator.requestScan(fetch: true)
        await old.release()
        await eventually { finished == 2 }
        #expect(await old.calls == [false])
        #expect(await new.calls == [true])
        await coordinator.refreshOpenNow()
        #expect(coordinator.openNow == .unknown("new"))
    }
}
