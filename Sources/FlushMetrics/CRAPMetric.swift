// CRAPMetric evaluates canonical function-level CRAP scores.

import FlushCore

/// The inputs a metric needs before it can be evaluated.
public enum MetricInputRequirement: Equatable, Hashable, Sendable {
    case coverage
}

/// The identifiers of metrics registered with Flush.
public enum MetricIdentifier: Equatable, Hashable, Sendable {
    case crap
}

/// Metadata describing a registered metric and its required inputs.
public struct MetricRegistration: Equatable, Sendable {
    /// The registered metric's identifier.
    public let identifier: MetricIdentifier

    /// The inputs required to evaluate the metric.
    public let inputRequirements: Set<MetricInputRequirement>

    /// Creates metric registration metadata.
    public init(
        identifier: MetricIdentifier,
        inputRequirements: Set<MetricInputRequirement>
    ) {
        self.identifier = identifier
        self.inputRequirements = inputRequirements
    }
}

/// The explicit threshold condition for a CRAP evaluation.
public enum CRAPThreshold: Equatable, Sendable {
    case configured(Double)
    case missing
}

/// The threshold verdict for a scored function region.
public enum CRAPVerdict: Equatable, Sendable {
    case pass
    case fail
}

/// A CRAP evaluation for one requested function region.
public struct CRAPRegionEvaluation: Equatable, Sendable {
    /// The requested function-like region.
    public let region: FunctionRegion

    /// The measured coverage or its original unavailable reason.
    public let coverage: RegionCoverageOutcome

    /// The canonical CRAP score when coverage was measured.
    public let score: Double?

    /// The threshold verdict when both a score and threshold exist.
    public let verdict: CRAPVerdict?

    /// Creates a function-region CRAP evaluation.
    public init(
        region: FunctionRegion,
        coverage: RegionCoverageOutcome,
        score: Double?,
        verdict: CRAPVerdict?
    ) {
        self.region = region
        self.coverage = coverage
        self.score = score
        self.verdict = verdict
    }
}

/// Aggregate completeness counts for a CRAP evaluation.
public struct CRAPEvaluationSummary: Equatable, Sendable {
    /// The number of function regions with a score.
    public let scoredCount: Int

    /// The number of function regions without a score.
    public let unscoredCount: Int

    /// Unscored function-region counts grouped by the original coverage reason.
    public let unscoredByReason: [CoverageUnavailableReason: Int]

    /// Creates CRAP evaluation completeness counts.
    public init(
        scoredCount: Int,
        unscoredCount: Int,
        unscoredByReason: [CoverageUnavailableReason: Int]
    ) {
        self.scoredCount = scoredCount
        self.unscoredCount = unscoredCount
        self.unscoredByReason = unscoredByReason
    }
}

/// The complete CRAP evaluation for every requested function region.
public struct CRAPEvaluation: Equatable, Sendable {
    /// One result for every requested function region.
    public let results: [CRAPRegionEvaluation]

    /// The explicit threshold condition used for verdicts.
    public let threshold: CRAPThreshold

    /// Completeness counts for scored and unscored regions.
    public let summary: CRAPEvaluationSummary

    /// Creates a complete CRAP evaluation.
    public init(
        results: [CRAPRegionEvaluation],
        threshold: CRAPThreshold,
        summary: CRAPEvaluationSummary
    ) {
        self.results = results
        self.threshold = threshold
        self.summary = summary
    }
}

/// Calculates canonical CRAP scores from complexity and function coverage.
public struct CRAPMetric: Sendable {
    /// Registration metadata for the CRAP metric.
    public static let registration = MetricRegistration(
        identifier: .crap,
        inputRequirements: [.coverage]
    )

    /// Creates a CRAP metric evaluator.
    public init() {}

    /// Evaluates every coverage-matching result without dropping unavailable regions.
    public func evaluate(
        _ coverage: CoverageMatchSummary,
        threshold: CRAPThreshold
    ) -> CRAPEvaluation {
        let results = coverage.results.map {
            evaluate($0, threshold: threshold)
        }
        return CRAPEvaluation(
            results: results,
            threshold: threshold,
            summary: summarize(results)
        )
    }

    private func evaluate(
        _ result: RegionCoverageResult,
        threshold: CRAPThreshold
    ) -> CRAPRegionEvaluation {
        switch result.outcome {
        case let .measured(measured):
            let score = score(
                complexity: result.region.cyclomaticComplexity,
                coverage: measured.coverage
            )
            return CRAPRegionEvaluation(
                region: result.region,
                coverage: result.outcome,
                score: score,
                verdict: verdict(for: score, threshold: threshold)
            )
        case .unavailable:
            return CRAPRegionEvaluation(
                region: result.region,
                coverage: result.outcome,
                score: nil,
                verdict: nil
            )
        }
    }

    private func score(complexity: Int, coverage: Double) -> Double {
        let complexity = Double(complexity)
        let uncovered = 1 - coverage
        return complexity * complexity * uncovered * uncovered * uncovered
            + complexity
    }

    private func verdict(
        for score: Double,
        threshold: CRAPThreshold
    ) -> CRAPVerdict? {
        switch threshold {
        case let .configured(value):
            score > value ? .fail : .pass
        case .missing:
            nil
        }
    }

    private func summarize(
        _ results: [CRAPRegionEvaluation]
    ) -> CRAPEvaluationSummary {
        let unscoredReasons = results.compactMap {
            if case let .unavailable(reason) = $0.coverage {
                return reason
            }
            return nil
        }
        let unscoredByReason = Dictionary(
            grouping: unscoredReasons,
            by: { $0 }
        ).mapValues(\.count)
        return CRAPEvaluationSummary(
            scoredCount: results.count - unscoredReasons.count,
            unscoredCount: unscoredReasons.count,
            unscoredByReason: unscoredByReason
        )
    }
}
