// CoverageReaderTests verifies native parsing and input validation.

@testable import FlushCore
import Foundation
import XCTest

final class CoverageReaderTests: XCTestCase {
    func testParsesRealLLVMCovExportFixture() throws {
        let files = try LLVMCoverageParser().parse(
            fixtureData(named: "llvm-cov-export")
        )

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(
            files[0].path,
            "/Users/fedor/clip/swift-flush/Sources/FlushCore/FunctionRegion.swift"
        )
        XCTAssertEqual(
            files[0].executableLines,
            (23...28).map { LineExecution(line: $0, count: 21) }
        )
    }

    func testMatchesRealLLVMLineViewForOverlappingSegments() throws {
        let files = try LLVMCoverageParser().parse(
            fixtureData(named: "llvm-cov-overlapping-segments")
        )
        let lineView = try lineViewFixture(
            named: "llvm-cov-overlapping-line-view"
        )

        XCTAssertEqual(files[0].executableLines, lineView)
    }

    func testLLVMReaderUsesOnlyExplicitInputs() throws {
        let binary = URL(fileURLWithPath: "/selected/FlushTests")
        let profile = URL(fileURLWithPath: "/selected/default.profdata")
        let executable = URL(fileURLWithPath: "/selected/llvm-cov")
        let executor = StubCommandExecutor(
            responses: [
                [
                    executable.path,
                    "export",
                    binary.path,
                    "-instr-profile",
                    profile.path
                ]: try fixtureData(named: "llvm-cov-export")
            ]
        )
        let completedAt = Date(timeIntervalSince1970: 100)

        let report = try LLVMCoverageReader(executor: executor).read(
            LLVMCoverageInput(
                llvmCovExecutable: executable,
                binaries: [binary],
                profile: profile,
                testRun: successfulRun(completedAt: completedAt)
            )
        )

        XCTAssertEqual(report.files.count, 1)
        XCTAssertEqual(report.successfulRunCompletedAt, completedAt)
    }

    func testRejectsFailedOrUnknownTestRunBeforeReadingCoverage() {
        let reader = LLVMCoverageReader(executor: RejectingCommandExecutor())

        for outcome in [TestRunOutcome.failed, .unknown] {
            XCTAssertThrowsError(
                try reader.read(
                    llvmInput(
                        evidence: TestRunEvidence(
                            outcome: outcome,
                            completedAt: Date()
                        )
                    )
                )
            ) {
                XCTAssertEqual(
                    $0 as? CoverageInputError,
                    .unconfirmedSuccessfulRun
                )
            }
        }
    }

    func testRejectsSuccessfulRunWithoutCompletionTime() {
        let reader = LLVMCoverageReader(executor: RejectingCommandExecutor())

        XCTAssertThrowsError(
            try reader.read(
                llvmInput(
                    evidence: TestRunEvidence(
                        outcome: .succeeded,
                        completedAt: nil
                    )
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? CoverageInputError,
                .missingRunCompletionTime
            )
        }
    }

    func testEmptyNativeReportsRemainEmpty() throws {
        let llvmFiles = try LLVMCoverageParser().parse(
            Data(#"{"data":[{"files":[]}]}"#.utf8)
        )

        XCTAssertTrue(llvmFiles.isEmpty)
    }

    func testProcessExecutorCapturesFailureWithoutPipeDeadlock() {
        let script = "dd if=/dev/zero bs=65536 count=2 >&2; exit 7"

        XCTAssertThrowsError(
            try ProcessCommandExecutor().execute(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script]
            )
        ) {
            guard case let CoverageInputError.nativeToolFailed(tool, message) = $0
            else {
                return XCTFail("Expected a native tool failure")
            }
            XCTAssertEqual(tool, "sh")
            XCTAssertGreaterThanOrEqual(message.utf8.count, 131_072)
        }
    }

    private func fixtureData(named name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(named: name, extension: "json"))
    }

    private func lineViewFixture(named name: String) throws -> [LineExecution] {
        let contents = try String(
            contentsOf: fixtureURL(named: name, extension: "txt"),
            encoding: .utf8
        )
        return try contents.split(separator: "\n").map { row in
            let fields = row.split(
                separator: "|",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            let line = try XCTUnwrap(Int(fields[0].trimmingCharacters(in: .whitespaces)))
            let count = try XCTUnwrap(Int(fields[1].trimmingCharacters(in: .whitespaces)))
            return LineExecution(line: line, count: count)
        }
    }

    private func fixtureURL(named name: String, extension: String) throws -> URL {
        let resourceURL = try XCTUnwrap(Bundle.module.resourceURL)
        return resourceURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .appendingPathExtension(`extension`)
    }

    private func successfulRun(completedAt: Date) -> TestRunEvidence {
        TestRunEvidence(outcome: .succeeded, completedAt: completedAt)
    }

    private func llvmInput(
        evidence: TestRunEvidence
    ) -> LLVMCoverageInput {
        LLVMCoverageInput(
            llvmCovExecutable: URL(fileURLWithPath: "/selected/llvm-cov"),
            binaries: [URL(fileURLWithPath: "/selected/FlushTests")],
            profile: URL(fileURLWithPath: "/selected/default.profdata"),
            testRun: evidence
        )
    }
}

private struct StubCommandExecutor: CommandExecuting {
    let responses: [[String]: Data]

    func execute(executable: URL, arguments: [String]) throws -> Data {
        guard let response = responses[[executable.path] + arguments] else {
            throw CoverageInputError.nativeToolFailed(
                tool: executable.lastPathComponent,
                message: "Unexpected arguments"
            )
        }
        return response
    }
}

private struct RejectingCommandExecutor: CommandExecuting {
    func execute(executable: URL, arguments: [String]) throws -> Data {
        throw CoverageInputError.nativeToolFailed(
            tool: executable.lastPathComponent,
            message: "Coverage input was read before validation"
        )
    }
}
