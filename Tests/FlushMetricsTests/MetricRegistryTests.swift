// FlushMetricsTests exercises metric registration and CRAP evaluation.

import FlushCore
import FlushMetrics
import XCTest

final class MetricRegistryTests: XCTestCase {
    func testRegistryContainsOnlyCRAPAndRequiresCoverage() {
        let registry = MetricRegistry()

        XCTAssertEqual(registry.metrics, [CRAPMetric.registration])
        XCTAssertFalse(registry.isEmpty)
        XCTAssertTrue(registry.requires(.coverage))
        XCTAssertEqual(CRAPMetric.registration.inputRequirements, [.coverage])
    }
}

final class CRAPMetricTests: XCTestCase {
    func testManualReferenceScores() throws {
        let cases = [
            ReferenceCase(complexity: 1, coverage: 0, expectedScore: 2),
            ReferenceCase(complexity: 1, coverage: 1, expectedScore: 1),
            ReferenceCase(complexity: 10, coverage: 0, expectedScore: 110),
            ReferenceCase(complexity: 4, coverage: 0.5, expectedScore: 6),
            ReferenceCase(complexity: 7, coverage: 0.37, expectedScore: 19.252303)
        ]

        for reference in cases {
            let evaluation = CRAPMetric().evaluate(
                summary(
                    measured(
                        complexity: reference.complexity,
                        coverage: reference.coverage,
                        freshness: .fresh
                    )
                ),
                threshold: .missing
            )

            let result = try XCTUnwrap(evaluation.results.first)
            XCTAssertEqual(
                try XCTUnwrap(result.score),
                reference.expectedScore,
                accuracy: 0.000_000_001
            )
        }
    }

    func testThresholdUsesUnroundedScoreAndPassesAtEqualityOrBelow() throws {
        let coverage = summary(
            measured(complexity: 4, coverage: 0.5, freshness: .fresh)
        )
        let metric = CRAPMetric()

        let below = metric.evaluate(coverage, threshold: .configured(5.999))
        let equal = metric.evaluate(coverage, threshold: .configured(6))
        let above = metric.evaluate(coverage, threshold: .configured(6.001))

        XCTAssertEqual(try XCTUnwrap(below.results.first).verdict, .fail)
        XCTAssertEqual(try XCTUnwrap(equal.results.first).verdict, .pass)
        XCTAssertEqual(try XCTUnwrap(above.results.first).verdict, .pass)
    }

    func testThresholdComparesUnroundedFractionalScore() throws {
        let evaluation = CRAPMetric().evaluate(
            summary(measured(complexity: 7, coverage: 0.37, freshness: .fresh)),
            threshold: .configured(19.252_302_5)
        )

        XCTAssertEqual(try XCTUnwrap(evaluation.results.first).verdict, .fail)
    }

    func testMissingThresholdProducesScoresWithoutVerdicts() throws {
        let evaluation = CRAPMetric().evaluate(
            summary(measured(complexity: 4, coverage: 0.5, freshness: .fresh)),
            threshold: .missing
        )

        XCTAssertEqual(evaluation.threshold, .missing)
        XCTAssertEqual(try XCTUnwrap(evaluation.results.first).score, 6)
        XCTAssertNil(try XCTUnwrap(evaluation.results.first).verdict)
    }

    func testMeasuredCoveragePreservesFreshnessBesideScore() throws {
        let evaluation = CRAPMetric().evaluate(
            summary(measured(complexity: 3, coverage: 0.5, freshness: .stale)),
            threshold: .configured(5)
        )
        let result = try XCTUnwrap(evaluation.results.first)

        XCTAssertEqual(result.score, 4.125)
        XCTAssertEqual(
            result.coverage,
            .measured(
                MeasuredRegionCoverage(
                    coverage: 0.5,
                    coveredLineCount: 1,
                    executableLineCount: 2,
                    freshness: .stale
                )
            )
        )
    }

    func testUnavailableCoverageHasNoScoreOrVerdictAndPreservesReason() {
        let reasons: [CoverageUnavailableReason] = [
            .noSourceFileMatch,
            .ambiguousSourceFileMatch,
            .sourceFileMissing,
            .sourceFileUnreadable,
            .noExecutableLines
        ]
        let results = reasons.enumerated().map {
            unavailable(complexity: $0.offset + 1, reason: $0.element)
        }
        let evaluation = CRAPMetric().evaluate(
            summary(results),
            threshold: .configured(30)
        )

        XCTAssertEqual(evaluation.summary.scoredCount, 0)
        XCTAssertEqual(evaluation.summary.unscoredCount, reasons.count)
        XCTAssertEqual(
            evaluation.summary.unscoredByReason,
            Dictionary(uniqueKeysWithValues: reasons.map { ($0, 1) })
        )
        XCTAssertEqual(
            evaluation.results.map(\.coverage),
            reasons.map(RegionCoverageOutcome.unavailable)
        )
        XCTAssertTrue(evaluation.results.allSatisfy { $0.score == nil })
        XCTAssertTrue(evaluation.results.allSatisfy { $0.verdict == nil })
    }

    func testSummaryCountsScoredAndUnscoredRegionsByReason() {
        let evaluation = CRAPMetric().evaluate(
            summary([
                measured(complexity: 1, coverage: 1, freshness: .fresh),
                measured(complexity: 2, coverage: 0, freshness: .stale),
                unavailable(complexity: 3, reason: .noExecutableLines),
                unavailable(complexity: 4, reason: .noExecutableLines),
                unavailable(complexity: 5, reason: .noSourceFileMatch)
            ]),
            threshold: .configured(30)
        )

        XCTAssertEqual(evaluation.summary.scoredCount, 2)
        XCTAssertEqual(evaluation.summary.unscoredCount, 3)
        XCTAssertEqual(
            evaluation.summary.unscoredByReason,
            [.noExecutableLines: 2, .noSourceFileMatch: 1]
        )
    }

    private func summary(
        _ result: RegionCoverageResult
    ) -> CoverageMatchSummary {
        summary([result])
    }

    private func summary(
        _ results: [RegionCoverageResult]
    ) -> CoverageMatchSummary {
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

    private func measured(
        complexity: Int,
        coverage: Double,
        freshness: CoverageFreshness
    ) -> RegionCoverageResult {
        RegionCoverageResult(
            region: region(complexity: complexity),
            outcome: .measured(
                MeasuredRegionCoverage(
                    coverage: coverage,
                    coveredLineCount: coverage == 0 ? 0 : 1,
                    executableLineCount: coverage == 1 ? 1 : 2,
                    freshness: freshness
                )
            )
        )
    }

    private func unavailable(
        complexity: Int,
        reason: CoverageUnavailableReason
    ) -> RegionCoverageResult {
        RegionCoverageResult(
            region: region(complexity: complexity),
            outcome: .unavailable(reason)
        )
    }

    private func region(complexity: Int) -> FunctionRegion {
        FunctionRegion(
            filePath: "/checkout/Sources/Example.swift",
            lineRange: 1 ... 10,
            name: "Example.run()",
            cyclomaticComplexity: complexity
        )
    }
}

private struct ReferenceCase {
    let complexity: Int
    let coverage: Double
    let expectedScore: Double
}
