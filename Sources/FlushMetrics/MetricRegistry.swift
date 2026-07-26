// FlushMetrics owns metric contracts and registration.

import FlushCore

/// The collection of metrics available to Flush.
public struct MetricRegistry: Sendable {
    public init() {}

    /// Indicates whether the registry contains any metrics.
    public var isEmpty: Bool {
        true
    }
}
