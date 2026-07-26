// SwiftSourceAnalyzer coordinates source loading and syntax analysis.

import Foundation
import SwiftParser
import SwiftSyntax

/// Analyzes executable function-like regions in Swift source files.
public struct SwiftSourceAnalyzer: Sendable {
    /// Creates a Swift source analyzer.
    public init() {}

    /// Returns every executable function-like region in the supplied Swift files.
    public func analyze(files: Set<URL>) throws -> [FunctionRegion] {
        try files
            .sorted { $0.path < $1.path }
            .flatMap(analyze(file:))
    }

    private func analyze(file: URL) throws -> [FunctionRegion] {
        let source = try String(contentsOf: file, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file.path, tree: tree)
        let collector = FunctionRegionCollector(
            filePath: file.path,
            converter: converter,
            viewMode: .sourceAccurate
        )

        collector.walk(tree)
        return collector.regions.sorted {
            $0.lineRange.lowerBound < $1.lineRange.lowerBound
                || (
                    $0.lineRange.lowerBound == $1.lineRange.lowerBound
                        && $0.name < $1.name
                )
        }
    }
}
