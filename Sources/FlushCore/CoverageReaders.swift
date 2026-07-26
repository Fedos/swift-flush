// Derived from https://github.com/pproenca/crap4swift and https://github.com/JordanCoin/crap4swift.

import Dispatch
import Foundation

protocol CommandExecuting: Sendable {
    func execute(executable: URL, arguments: [String]) throws -> Data
}

struct ProcessCommandExecutor: CommandExecuting {
    func execute(executable: URL, arguments: [String]) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? error.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }
        try process.run()
        completion.wait()
        try output.close()
        try error.close()

        guard process.terminationStatus == 0 else {
            let message = String(data: try Data(contentsOf: errorURL), encoding: .utf8)
                ?? ""
            throw CoverageInputError.nativeToolFailed(
                tool: executable.lastPathComponent,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try Data(contentsOf: outputURL)
    }
}

/// Reads coverage exported by `llvm-cov`.
public struct LLVMCoverageReader: Sendable {
    private let executor: any CommandExecuting

    /// Creates an LLVM coverage reader.
    public init() {
        executor = ProcessCommandExecutor()
    }

    init(executor: any CommandExecuting) {
        self.executor = executor
    }

    /// Exports and normalizes the explicitly identified LLVM inputs.
    public func read(_ input: LLVMCoverageInput) throws -> CoverageReport {
        let completedAt = try TestRunValidator.validate(input.testRun)
        guard let firstBinary = input.binaries.first else {
            throw CoverageInputError.missingLLVMBinary
        }
        let remainingObjects = input.binaries.dropFirst().flatMap {
            ["-object", $0.path]
        }
        let arguments = [
            "export",
            firstBinary.path,
            "-instr-profile",
            input.profile.path
        ] + remainingObjects
        let data = try executor.execute(
            executable: input.llvmCovExecutable,
            arguments: arguments
        )
        let files = try LLVMCoverageParser().parse(data)
        return CoverageReport(
            files: files,
            successfulRunCompletedAt: completedAt
        )
    }
}

enum TestRunValidator {
    static func validate(_ evidence: TestRunEvidence) throws -> Date {
        guard evidence.outcome == .succeeded else {
            throw CoverageInputError.unconfirmedSuccessfulRun
        }
        guard let completedAt = evidence.completedAt else {
            throw CoverageInputError.missingRunCompletionTime
        }
        return completedAt
    }
}

struct LLVMCoverageParser {
    func parse(_ data: Data) throws -> [SourceFileCoverage] {
        guard
            let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let dataSets = root["data"] as? [[String: Any]]
        else {
            throw CoverageInputError.malformedNativeOutput(tool: "llvm-cov")
        }

        var linesByPath: [String: [LineExecution]] = [:]
        for dataSet in dataSets {
            guard let files = dataSet["files"] as? [[String: Any]] else {
                throw CoverageInputError.malformedNativeOutput(tool: "llvm-cov")
            }
            for file in files {
                let parsed = try parseFile(file)
                linesByPath[parsed.path, default: []]
                    .append(contentsOf: parsed.executableLines)
            }
        }
        return linesByPath
            .map(SourceFileCoverage.init(path:executableLines:))
            .sorted { $0.path < $1.path }
    }

    private func parseFile(
        _ object: [String: Any]
    ) throws -> SourceFileCoverage {
        guard
            let path = object["filename"] as? String,
            let rawSegments = object["segments"] as? [[Any]]
        else {
            throw CoverageInputError.malformedNativeOutput(tool: "llvm-cov")
        }
        let segments = try rawSegments.map(parseSegment)
        return SourceFileCoverage(
            path: path,
            executableLines: lineExecutions(segments)
        )
    }

    private func parseSegment(_ values: [Any]) throws -> LLVMSegment {
        guard
            values.count >= 6,
            let line = integer(values[0]),
            let column = integer(values[1]),
            let count = integer(values[2]),
            let hasCount = values[3] as? Bool,
            let isRegionEntry = values[4] as? Bool,
            let isGap = values[5] as? Bool
        else {
            throw CoverageInputError.malformedNativeOutput(tool: "llvm-cov")
        }
        return LLVMSegment(
            line: line,
            column: column,
            count: count,
            hasCount: hasCount,
            isRegionEntry: isRegionEntry,
            isGap: isGap
        )
    }

    private func lineExecutions(
        _ segments: [LLVMSegment]
    ) -> [LineExecution] {
        guard !segments.isEmpty else {
            return []
        }
        let sorted = segments.sorted {
            ($0.line, $0.column) < ($1.line, $1.column)
        }
        var executions: [LineExecution] = []
        var segmentIndex = 0
        var activeSegment: LLVMSegment?
        for line in sorted[0].line...sorted[sorted.count - 1].line {
            let lineSegments = segmentsForLine(
                on: line,
                in: sorted,
                index: &segmentIndex
            )
            if let count = executionCount(
                activeSegment: activeSegment,
                lineSegments: lineSegments
            ) {
                executions.append(LineExecution(line: line, count: count))
            }
            if let last = lineSegments.last {
                activeSegment = last
            }
        }
        return executions
    }

    private func segmentsForLine(
        on line: Int,
        in segments: [LLVMSegment],
        index: inout Int
    ) -> [LLVMSegment] {
        var lineSegments: [LLVMSegment] = []
        while index < segments.count, segments[index].line == line {
            lineSegments.append(segments[index])
            index += 1
        }
        return lineSegments
    }

    private func executionCount(
        activeSegment: LLVMSegment?,
        lineSegments: [LLVMSegment]
    ) -> Int? {
        let activeCount = activeSegment.flatMap {
            $0.hasCount && !$0.isGap ? $0.count : nil
        }
        let regionCounts = lineSegments.filter {
            $0.hasCount && $0.isRegionEntry && !$0.isGap
        }.map(\.count)
        if let count = ([activeCount].compactMap { $0 } + regionCounts).max() {
            return count
        }
        guard
            lineSegments.first.map({
                $0.hasCount || !$0.isRegionEntry
            }) ?? true
        else {
            return nil
        }
        return lineSegments.filter {
            $0.hasCount && !$0.isGap
        }.map(\.count).max()
    }

    private func integer(_ value: Any) -> Int? {
        (value as? NSNumber)?.intValue
    }
}

private struct LLVMSegment {
    let line: Int
    let column: Int
    let count: Int
    let hasCount: Bool
    let isRegionEntry: Bool
    let isGap: Bool
}
