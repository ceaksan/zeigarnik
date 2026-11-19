import Foundation
import Observation

public protocol Scanning: Sendable {
    func scan(fetch: Bool) async -> ScanReport
}

extension ProjectScanner: Scanning {}

/// Runs one scan at a time: on start, every `interval`, and on request. Requests during a scan collapse into one follow-up.
@MainActor @Observable
public final class ScanCoordinator {
    public private(set) var isScanning = false
    public private(set) var lastReport: ScanReport?
    public private(set) var openNow: OpenNowState?

    @ObservationIgnored private var scanner: any Scanning
    @ObservationIgnored private var interval: Duration
    @ObservationIgnored private let step: Duration
    @ObservationIgnored private var openNowProvider: (@Sendable () async -> OpenNowState)?
    @ObservationIgnored private let onFinish: @MainActor (ScanReport) -> Void
    @ObservationIgnored private var pendingFetch: Bool?
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(scanner: any Scanning, interval: Duration = .seconds(7200), step: Duration = .seconds(60),
                openNowProvider: (@Sendable () async -> OpenNowState)?, onFinish: @escaping @MainActor (ScanReport) -> Void) {
        self.scanner = scanner
        self.interval = interval
        self.step = step
        self.openNowProvider = openNowProvider
        self.onFinish = onFinish
    }

    public func start() {
        guard loop == nil else { return }
        requestScan(fetch: true)
        let step = self.step
        loop = Task { [weak self] in
            var elapsed = Duration.zero
            while !Task.isCancelled {
                try? await Task.sleep(for: step)
                guard let self, !Task.isCancelled else { return }
                await self.refreshOpenNow()
                elapsed += step
                if elapsed >= self.interval {
                    elapsed = .zero
                    self.tick()
                }
            }
        }
    }

    /// Takes effect at the next timer step; time already elapsed counts toward the new interval.
    public func setInterval(_ interval: Duration) {
        self.interval = interval
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Later runs use `scanner`; a scan already running finishes on the old one.
    public func replaceScanner(_ scanner: any Scanning, openNowProvider: (@Sendable () async -> OpenNowState)?) {
        self.scanner = scanner
        self.openNowProvider = openNowProvider
    }

    public func requestScan(fetch: Bool) {
        if isScanning {
            pendingFetch = (pendingFetch ?? false) || fetch
            return
        }
        run(fetch: fetch)
    }

    public func refreshOpenNow() async {
        guard let openNowProvider else { return }
        openNow = await openNowProvider()
    }

    /// Timer entry point: starts a fetching scan when idle, does nothing while a scan runs.
    func tick() {
        guard !isScanning else { return }
        run(fetch: true)
    }

    private func run(fetch: Bool) {
        isScanning = true
        let scanner = self.scanner
        Task { [weak self] in
            let report = await scanner.scan(fetch: fetch)
            self?.finish(report)
        }
    }

    private func finish(_ report: ScanReport) {
        lastReport = report
        openNow = report.openNow
        isScanning = false
        onFinish(report)
        if let fetch = pendingFetch {
            pendingFetch = nil
            run(fetch: fetch)
        }
    }
}
