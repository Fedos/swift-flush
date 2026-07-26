// FlushMetrics owns metric contracts and registration.

import FlushCore

/// The collection of metrics available to Flush.
public struct MetricRegistry: Sendable {
    /// Metrics registered for evaluation.
    public let metrics: [MetricRegistration]

    /// Creates the v1 registry containing the CRAP metric.
    public init() {
        metrics = [CRAPMetric.registration]
    }

    /// Indicates whether the registry contains any metrics.
    public var isEmpty: Bool {
        metrics.isEmpty
    }

    /// Returns whether any registered metric requires the given input.
    public func requires(_ input: MetricInputRequirement) -> Bool {
        metrics.contains {
            $0.inputRequirements.contains(input)
        }
    }
}
