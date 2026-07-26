// CoverageReaders normalize explicitly selected LLVM and Xcode inputs.

import Foundation

protocol CommandExecuting: Sendable {
    func execute(arguments: [String]) throws -> Data
}

struct XcrunCommandExecutor: CommandExecuting {
    func execute(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CoverageInputError.nativeToolFailed(
                tool: arguments.first ?? "xcrun",
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return outputData
    }
}

/// Reads either explicitly selected native coverage input.
public struct CoverageReader: Sendable {
    private let llvmReader: LLVMCoverageReader
    private let xcodeReader: XcodeCoverageReader

    /// Creates a native coverage reader.
    public init() {
        let executor = XcrunCommandExecutor()
        llvmReader = LLVMCoverageReader(executor: executor)
        xcodeReader = XcodeCoverageReader(executor: executor)
    }

    /// Normalizes the explicitly selected input without searching for artifacts.
    public func read(_ input: CoverageInput) throws -> CoverageReport {
        switch input {
        case let .llvm(input):
            try llvmReader.read(input)
        case let .xcode(input):
            try xcodeReader.read(input)
        }
    }
}

/// Reads coverage exported by `llvm-cov`.
public struct LLVMCoverageReader: Sendable {
    private let executor: any CommandExecuting

    /// Creates an LLVM coverage reader.
    public init() {
        executor = XcrunCommandExecutor()
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
            "llvm-cov",
            "export",
            firstBinary.path,
            "-instr-profile",
            input.profile.path
        ] + remainingObjects
        let data = try executor.execute(arguments: arguments)
        let files = try LLVMCoverageParser().parse(data)
        return CoverageReport(
            files: files,
            successfulRunCompletedAt: completedAt
        )
    }
}

/// Reads raw line execution counts from an explicitly selected `.xcresult`.
public struct XcodeCoverageReader: Sendable {
    private let executor: any CommandExecuting

    /// Creates an Xcode coverage reader.
    public init() {
        executor = XcrunCommandExecutor()
    }

    init(executor: any CommandExecuting) {
        self.executor = executor
    }

    /// Uses `xccov` to normalize coverage from the selected result bundle.
    public func read(_ input: XcodeCoverageInput) throws -> CoverageReport {
        let completedAt = try TestRunValidator.validate(input.testRun)
        let fileListData = try executor.execute(
            arguments: [
                "xccov",
                "view",
                "--archive",
                "--file-list",
                input.resultBundle.path
            ]
        )
        let paths = try XcodeCoverageParser().parseFileList(fileListData)
        let files = try paths.sorted().map {
            try readFile(path: $0, resultBundle: input.resultBundle)
        }
        return CoverageReport(
            files: files,
            successfulRunCompletedAt: completedAt
        )
    }

    private func readFile(
        path: String,
        resultBundle: URL
    ) throws -> SourceFileCoverage {
        let data = try executor.execute(
            arguments: [
                "xccov",
                "view",
                "--archive",
                "--file",
                path,
                "--json",
                resultBundle.path
            ]
        )
        return try XcodeCoverageParser().parseFile(data, expectedPath: path)
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
            executableLines: expand(segments)
        )
    }

    private func parseSegment(_ values: [Any]) throws -> LLVMSegment {
        guard
            values.count >= 6,
            let line = integer(values[0]),
            let column = integer(values[1]),
            let count = integer(values[2]),
            let hasCount = values[3] as? Bool,
            let isGap = values[5] as? Bool
        else {
            throw CoverageInputError.malformedNativeOutput(tool: "llvm-cov")
        }
        return LLVMSegment(
            line: line,
            column: column,
            count: count,
            hasCount: hasCount,
            isGap: isGap
        )
    }

    private func expand(_ segments: [LLVMSegment]) -> [LineExecution] {
        segments.indices.flatMap { index -> [LineExecution] in
            let segment = segments[index]
            guard segment.hasCount, !segment.isGap else {
                return []
            }
            guard index + 1 < segments.count else {
                return [LineExecution(line: segment.line, count: segment.count)]
            }
            let next = segments[index + 1]
            let lastLine = next.column == 1 ? next.line - 1 : next.line
            guard lastLine >= segment.line else {
                return [LineExecution(line: segment.line, count: segment.count)]
            }
            return (segment.line...lastLine).map {
                LineExecution(line: $0, count: segment.count)
            }
        }
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
    let isGap: Bool
}

struct XcodeCoverageParser {
    func parseFileList(_ data: Data) throws -> [String] {
        guard let output = String(data: data, encoding: .utf8) else {
            throw CoverageInputError.malformedNativeOutput(tool: "xccov")
        }
        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    func parseFile(
        _ data: Data,
        expectedPath: String
    ) throws -> SourceFileCoverage {
        let decoder = JSONDecoder()
        guard
            let files = try? decoder.decode(
                [String: [XcodeLineExecution]].self,
                from: data
            ),
            let lines = files[expectedPath]
        else {
            throw CoverageInputError.malformedNativeOutput(tool: "xccov")
        }
        return SourceFileCoverage(
            path: expectedPath,
            executableLines: lines.compactMap {
                guard $0.isExecutable else {
                    return nil
                }
                return LineExecution(
                    line: $0.line,
                    count: $0.executionCount ?? 0
                )
            }
        )
    }
}

private struct XcodeLineExecution: Decodable {
    let line: Int
    let isExecutable: Bool
    let executionCount: Int?
}
