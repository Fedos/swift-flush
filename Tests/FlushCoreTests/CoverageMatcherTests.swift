// CoverageMatcherTests verifies honest path, range, and freshness outcomes.

import FlushCore
import Foundation
import XCTest

final class CoverageMatcherTests: XCTestCase {
    func testMeasuresInclusiveExecutableLineCoverageAndFreshness() throws {
        let source = try makeSourceFile()
        let completedAt = Date(timeIntervalSinceNow: 60)
        let report = CoverageReport(
            files: [
                SourceFileCoverage(
                    path: "/build/checkout\(source.path)",
                    executableLines: [
                        LineExecution(line: 2, count: 1),
                        LineExecution(line: 3, count: 0),
                        LineExecution(line: 4, count: 2),
                        LineExecution(line: 5, count: 0)
                    ]
                )
            ],
            successfulRunCompletedAt: completedAt
        )

        let summary = CoverageMatcher().match(
            regions: [region(path: source.path, range: 2...4)],
            report: report
        )

        XCTAssertEqual(summary.measuredCount, 1)
        XCTAssertEqual(summary.unavailableCount, 0)
        XCTAssertEqual(
            summary.results[0].outcome,
            .measured(
                MeasuredRegionCoverage(
                    coverage: 2.0 / 3.0,
                    coveredLineCount: 2,
                    executableLineCount: 3,
                    freshness: .fresh
                )
            )
        )
    }

    func testMarksCoverageStaleRelativeToSuccessfulRunCompletion() throws {
        let source = try makeSourceFile()
        let completedAt = Date(timeIntervalSinceNow: -60)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: source.path
        )

        let outcome = match(
            path: source.path,
            coveragePath: source.path,
            lines: [LineExecution(line: 2, count: 1)],
            completedAt: completedAt
        )

        XCTAssertEqual(
            outcome,
            .measured(
                MeasuredRegionCoverage(
                    coverage: 1,
                    coveredLineCount: 1,
                    executableLineCount: 1,
                    freshness: .stale
                )
            )
        )
    }

    func testRepeatedLineIsCoveredWhenAnyCountIsNonzero() throws {
        let source = try makeSourceFile()

        let outcome = match(
            path: source.path,
            coveragePath: source.path,
            lines: [
                LineExecution(line: 2, count: 0),
                LineExecution(line: 2, count: 4),
                LineExecution(line: 3, count: 0)
            ]
        )

        XCTAssertEqual(
            outcome,
            .measured(
                MeasuredRegionCoverage(
                    coverage: 0.5,
                    coveredLineCount: 1,
                    executableLineCount: 2,
                    freshness: .fresh
                )
            )
        )
    }

    func testReportsMissingPathMatchWithoutNumericSubstitution() {
        let outcome = match(
            path: "/checkout/Sources/Expected.swift",
            coveragePath: "/build/Sources/Other.swift",
            lines: [LineExecution(line: 2, count: 1)]
        )

        XCTAssertEqual(outcome, .unavailable(.noSourceFileMatch))
    }

    func testReportsAmbiguousLongestComponentSuffix() {
        let path = "/checkout/Sources/Example.swift"
        let report = CoverageReport(
            files: [
                SourceFileCoverage(
                    path: "/build/one/Sources/Example.swift",
                    executableLines: [LineExecution(line: 2, count: 1)]
                ),
                SourceFileCoverage(
                    path: "/build/two/Sources/Example.swift",
                    executableLines: [LineExecution(line: 2, count: 1)]
                )
            ],
            successfulRunCompletedAt: Date()
        )

        let summary = CoverageMatcher().match(
            regions: [region(path: path)],
            report: report
        )

        XCTAssertEqual(
            summary.results[0].outcome,
            .unavailable(.ambiguousSourceFileMatch)
        )
    }

    func testSelectsUniqueLongestComponentSuffix() throws {
        let source = try makeSourceFile()
        let report = CoverageReport(
            files: [
                SourceFileCoverage(
                    path: "/build\(source.path)",
                    executableLines: [LineExecution(line: 2, count: 1)]
                ),
                SourceFileCoverage(
                    path: "/other/Example.swift",
                    executableLines: [LineExecution(line: 2, count: 0)]
                )
            ],
            successfulRunCompletedAt: Date(timeIntervalSinceNow: 60)
        )

        let summary = CoverageMatcher().match(
            regions: [region(path: source.path)],
            report: report
        )

        XCTAssertEqual(summary.measuredCount, 1)
        XCTAssertEqual(
            summary.results[0].outcome,
            .measured(
                MeasuredRegionCoverage(
                    coverage: 1,
                    coveredLineCount: 1,
                    executableLineCount: 1,
                    freshness: .fresh
                )
            )
        )
    }

    func testReportsMissingSourceFile() {
        let path = "/missing/\(UUID().uuidString)/Example.swift"

        let outcome = match(
            path: path,
            coveragePath: path,
            lines: [LineExecution(line: 2, count: 1)]
        )

        XCTAssertEqual(outcome, .unavailable(.sourceFileMissing))
    }

    func testReportsUnreadableSourceFile() throws {
        let source = try makeSourceFile()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: source.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: source.path
            )
        }

        let outcome = match(
            path: source.path,
            coveragePath: source.path,
            lines: [LineExecution(line: 2, count: 1)]
        )

        XCTAssertEqual(outcome, .unavailable(.sourceFileUnreadable))
    }

    func testReportsRegionWithoutExecutableLines() throws {
        let source = try makeSourceFile()

        let outcome = match(
            path: source.path,
            coveragePath: source.path,
            lines: [LineExecution(line: 10, count: 1)]
        )

        XCTAssertEqual(outcome, .unavailable(.noExecutableLines))
    }

    func testSummaryCountsMeasuredAndUnavailableRegions() throws {
        let source = try makeSourceFile()
        let report = CoverageReport(
            files: [
                SourceFileCoverage(
                    path: source.path,
                    executableLines: [LineExecution(line: 2, count: 1)]
                )
            ],
            successfulRunCompletedAt: Date(timeIntervalSinceNow: 60)
        )

        let summary = CoverageMatcher().match(
            regions: [
                region(path: source.path, range: 2...2),
                region(path: source.path, range: 5...6)
            ],
            report: report
        )

        XCTAssertEqual(summary.results.count, 2)
        XCTAssertEqual(summary.measuredCount, 1)
        XCTAssertEqual(summary.unavailableCount, 1)
    }

    private func match(
        path: String,
        coveragePath: String,
        lines: [LineExecution],
        completedAt: Date = Date(timeIntervalSinceNow: 60)
    ) -> RegionCoverageOutcome {
        let report = CoverageReport(
            files: [
                SourceFileCoverage(
                    path: coveragePath,
                    executableLines: lines
                )
            ],
            successfulRunCompletedAt: completedAt
        )
        return CoverageMatcher().match(
            regions: [region(path: path)],
            report: report
        ).results[0].outcome
    }

    private func region(
        path: String,
        range: ClosedRange<Int> = 2...3
    ) -> FunctionRegion {
        FunctionRegion(
            filePath: path,
            lineRange: range,
            name: "func example()",
            cyclomaticComplexity: 1
        )
    }

    private func makeSourceFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("Example.swift")
        try "func example() {\n    print(\"example\")\n}\n"
            .write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
