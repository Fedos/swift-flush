// FlushMetricsTests exercises the metric-registry boundary.

import FlushMetrics
import XCTest

final class MetricRegistryTests: XCTestCase {
    func testRegistryCanBeCreatedWithoutMetrics() {
        let registry = MetricRegistry()

        XCTAssertTrue(registry.isEmpty)
    }
}
