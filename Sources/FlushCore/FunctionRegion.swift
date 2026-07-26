// FunctionRegion describes one executable Swift source region.

/// An executable function-like source region and its cyclomatic complexity.
public struct FunctionRegion: Equatable, Sendable {
    /// The analyzed file's path.
    public let filePath: String

    /// The inclusive source lines occupied by the declaration or accessor.
    public let lineRange: ClosedRange<Int>

    /// A human-readable name containing the lexical context and declaration signature.
    public let name: String

    /// The syntax-based cyclomatic complexity, starting at one.
    public let cyclomaticComplexity: Int

    /// Creates a function-like source region.
    public init(
        filePath: String,
        lineRange: ClosedRange<Int>,
        name: String,
        cyclomaticComplexity: Int
    ) {
        self.filePath = filePath
        self.lineRange = lineRange
        self.name = name
        self.cyclomaticComplexity = cyclomaticComplexity
    }
}
