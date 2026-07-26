// CoverageMatcher maps normalized source lines to function regions.

import Foundation

/// Whether measured region coverage predates the current source file.
public enum CoverageFreshness: Equatable, Sendable {
    case fresh
    case stale
}

/// Measured executable-line coverage for one function region.
///
/// Coverage for a region is the fraction of covered executable lines within
/// its inclusive line range.
public struct MeasuredRegionCoverage: Equatable, Sendable {
    /// The covered executable-line count divided by the executable-line count.
    public let coverage: Double

    /// The number of unique covered executable lines.
    public let coveredLineCount: Int

    /// The number of unique executable lines.
    public let executableLineCount: Int

    /// Whether the source file changed after the successful test run completed.
    public let freshness: CoverageFreshness

    /// Creates measured coverage for a function region.
    public init(
        coverage: Double,
        coveredLineCount: Int,
        executableLineCount: Int,
        freshness: CoverageFreshness
    ) {
        self.coverage = coverage
        self.coveredLineCount = coveredLineCount
        self.executableLineCount = executableLineCount
        self.freshness = freshness
    }
}

/// The explicit reason coverage could not be measured for a function region.
public enum CoverageUnavailableReason: Equatable, Hashable, Sendable {
    case noSourceFileMatch
    case ambiguousSourceFileMatch
    case sourceFileMissing
    /// The source file has no read permission bit set and is unreadable regardless of the process's privileges.
    case sourceFileUnreadable
    case noExecutableLines
}

/// The coverage outcome for one requested function region.
public enum RegionCoverageOutcome: Equatable, Sendable {
    case measured(MeasuredRegionCoverage)
    case unavailable(CoverageUnavailableReason)
}

/// One requested function region and its coverage outcome.
public struct RegionCoverageResult: Equatable, Sendable {
    /// The requested function-like region.
    public let region: FunctionRegion

    /// Measured coverage or an explicit unavailable reason.
    public let outcome: RegionCoverageOutcome

    /// Creates a function-region coverage result.
    public init(region: FunctionRegion, outcome: RegionCoverageOutcome) {
        self.region = region
        self.outcome = outcome
    }
}

/// The complete outcome of matching requested regions to source coverage.
public struct CoverageMatchSummary: Equatable, Sendable {
    /// One result for every requested function region.
    public let results: [RegionCoverageResult]

    /// The number of regions with measured coverage.
    public let measuredCount: Int

    /// The number of regions with unavailable coverage.
    public let unavailableCount: Int

    /// Creates a complete coverage-matching summary.
    public init(
        results: [RegionCoverageResult],
        measuredCount: Int,
        unavailableCount: Int
    ) {
        self.results = results
        self.measuredCount = measuredCount
        self.unavailableCount = unavailableCount
    }
}

/// Matches function regions to normalized coverage by path and source range.
public struct CoverageMatcher: Sendable {
    /// Creates a source-region coverage matcher.
    public init() {}

    /// Returns exactly one measured or unavailable result per requested region.
    public func match(
        regions: [FunctionRegion],
        report: CoverageReport
    ) -> CoverageMatchSummary {
        let files = consolidatedFiles(report.files)
        let results = regions.map {
            match(region: $0, files: files, report: report)
        }
        let measuredCount = results.filter {
            if case .measured = $0.outcome {
                return true
            }
            return false
        }.count
        return CoverageMatchSummary(
            results: results,
            measuredCount: measuredCount,
            unavailableCount: results.count - measuredCount
        )
    }

    private func match(
        region: FunctionRegion,
        files: [SourceFileCoverage],
        report: CoverageReport
    ) -> RegionCoverageResult {
        switch uniqueFile(for: region.filePath, in: files) {
        case .missing:
            unavailable(region, reason: .noSourceFileMatch)
        case .ambiguous:
            unavailable(region, reason: .ambiguousSourceFileMatch)
        case let .matched(file):
            match(region: region, file: file, report: report)
        }
    }

    private func match(
        region: FunctionRegion,
        file: SourceFileCoverage,
        report: CoverageReport
    ) -> RegionCoverageResult {
        switch sourceModificationDate(path: region.filePath) {
        case .missing:
            unavailable(region, reason: .sourceFileMissing)
        case .unreadable:
            unavailable(region, reason: .sourceFileUnreadable)
        case let .readable(modificationDate):
            measure(
                region: region,
                file: file,
                modificationDate: modificationDate,
                completedAt: report.successfulRunCompletedAt
            )
        }
    }

    private func measure(
        region: FunctionRegion,
        file: SourceFileCoverage,
        modificationDate: Date,
        completedAt: Date
    ) -> RegionCoverageResult {
        let relevant = Dictionary(
            grouping: file.executableLines.filter {
                region.lineRange.contains($0.line)
            },
            by: \.line
        )
        guard !relevant.isEmpty else {
            return unavailable(region, reason: .noExecutableLines)
        }
        let coveredLineCount = relevant.values.filter {
            $0.contains { $0.count > 0 }
        }.count
        let executableLineCount = relevant.count
        let coverage = Double(coveredLineCount) / Double(executableLineCount)
        let freshness: CoverageFreshness =
            modificationDate > completedAt ? .stale : .fresh
        return RegionCoverageResult(
            region: region,
            outcome: .measured(
                MeasuredRegionCoverage(
                    coverage: coverage,
                    coveredLineCount: coveredLineCount,
                    executableLineCount: executableLineCount,
                    freshness: freshness
                )
            )
        )
    }

    private func unavailable(
        _ region: FunctionRegion,
        reason: CoverageUnavailableReason
    ) -> RegionCoverageResult {
        RegionCoverageResult(
            region: region,
            outcome: .unavailable(reason)
        )
    }

    private func consolidatedFiles(
        _ files: [SourceFileCoverage]
    ) -> [SourceFileCoverage] {
        Dictionary(grouping: files, by: \.path)
            .map { path, files in
                SourceFileCoverage(
                    path: path,
                    executableLines: files.flatMap(\.executableLines)
                )
            }
            .sorted { $0.path < $1.path }
    }

    private func uniqueFile(
        for sourcePath: String,
        in files: [SourceFileCoverage]
    ) -> FileMatch {
        let sourceComponents = pathComponents(sourcePath)
        let scored = files.map {
            ($0, commonSuffixLength(sourceComponents, pathComponents($0.path)))
        }
        guard let longest = scored.map(\.1).max(), longest > 0 else {
            return .missing
        }
        let matches = scored.filter { $0.1 == longest }.map(\.0)
        guard matches.count == 1, let match = matches.first else {
            return .ambiguous
        }
        return .matched(match)
    }

    private func pathComponents(_ path: String) -> [String] {
        URL(fileURLWithPath: path)
            .standardized
            .pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
    }

    private func commonSuffixLength(
        _ first: [String],
        _ second: [String]
    ) -> Int {
        zip(first.reversed(), second.reversed())
            .prefix { $0 == $1 }
            .count
    }

    private func sourceModificationDate(path: String) -> SourceInspection {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else {
            return .missing
        }
        guard
            let attributes = try? manager.attributesOfItem(atPath: path),
            hasReadablePermissions(attributes),
            manager.isReadableFile(atPath: path),
            let handle = FileHandle(forReadingAtPath: path)
        else {
            return .unreadable
        }
        try? handle.close()
        guard
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return .unreadable
        }
        return .readable(modificationDate)
    }

    private func hasReadablePermissions(
        _ attributes: [FileAttributeKey: Any]
    ) -> Bool {
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            return true
        }
        return permissions.intValue & 0o444 != 0
    }
}

private enum FileMatch {
    case matched(SourceFileCoverage)
    case missing
    case ambiguous
}

private enum SourceInspection {
    case readable(Date)
    case missing
    case unreadable
}
