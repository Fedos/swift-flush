// CoverageModel defines normalized source coverage and test-run evidence.

import Foundation

/// The known outcome of the test run that produced coverage data.
public enum TestRunOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case unknown
}

/// Evidence about the test run that produced a coverage input.
public struct TestRunEvidence: Equatable, Sendable {
    /// The confirmed or unknown test-run outcome.
    public let outcome: TestRunOutcome

    /// The time when the test run completed, when known.
    public let completedAt: Date?

    /// Creates test-run evidence.
    public init(outcome: TestRunOutcome, completedAt: Date?) {
        self.outcome = outcome
        self.completedAt = completedAt
    }
}

/// One execution-count sample for an executable source line.
///
/// If a source line occurs more than once in coverage data, the line is
/// considered covered when any sample for that line has a nonzero count.
public struct LineExecution: Equatable, Sendable {
    /// The one-based source line number.
    public let line: Int

    /// The recorded execution count.
    public let count: Int

    /// Creates an executable-line sample.
    public init(line: Int, count: Int) {
        self.line = line
        self.count = count
    }
}

/// Normalized executable-line coverage for one source file.
public struct SourceFileCoverage: Equatable, Sendable {
    /// The source path recorded by the coverage tool.
    public let path: String

    /// All executable-line samples recorded for the source file.
    public let executableLines: [LineExecution]

    /// Creates normalized source-file coverage.
    public init(path: String, executableLines: [LineExecution]) {
        self.path = path
        self.executableLines = executableLines
    }
}

/// Normalized source coverage produced by one successful test run.
public struct CoverageReport: Equatable, Sendable {
    /// Source files and their executable-line samples.
    public let files: [SourceFileCoverage]

    /// The completion time of the successful test run.
    public let successfulRunCompletedAt: Date

    /// Creates a normalized coverage report.
    public init(
        files: [SourceFileCoverage],
        successfulRunCompletedAt: Date
    ) {
        self.files = files
        self.successfulRunCompletedAt = successfulRunCompletedAt
    }
}

/// An explicitly selected native coverage input.
public enum CoverageInput: Sendable {
    case llvm(LLVMCoverageInput)
    case xcode(XcodeCoverageInput)
}

/// Explicit inputs used to export LLVM source coverage.
public struct LLVMCoverageInput: Sendable {
    /// Instrumented binaries whose coverage mappings are exported.
    public let binaries: [URL]

    /// The merged LLVM profile data produced by the test run.
    public let profile: URL

    /// Evidence for the test run that produced the profile.
    public let testRun: TestRunEvidence

    /// Creates an explicitly selected LLVM coverage input.
    public init(
        binaries: [URL],
        profile: URL,
        testRun: TestRunEvidence
    ) {
        self.binaries = binaries
        self.profile = profile
        self.testRun = testRun
    }
}

/// An explicitly selected Xcode result-bundle coverage input.
public struct XcodeCoverageInput: Sendable {
    /// The `.xcresult` bundle produced by the test run.
    public let resultBundle: URL

    /// Evidence for the test run that produced the result bundle.
    public let testRun: TestRunEvidence

    /// Creates an explicitly selected Xcode coverage input.
    public init(resultBundle: URL, testRun: TestRunEvidence) {
        self.resultBundle = resultBundle
        self.testRun = testRun
    }
}

/// A coverage-input or native-tool failure.
public enum CoverageInputError: Error, Equatable, Sendable {
    case unconfirmedSuccessfulRun
    case missingRunCompletionTime
    case missingLLVMBinary
    case nativeToolFailed(tool: String, message: String)
    case malformedNativeOutput(tool: String)
}
