// FlushCLI coordinates the command-line product.

import FlushCore
import FlushMetrics

@main
struct FlushCLI {
    static func main() {
        _ = MetricRegistry()
    }
}
