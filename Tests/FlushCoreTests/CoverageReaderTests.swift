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

    func testParsesRealXccovArchiveFixture() throws {
        let path =
            "/Users/fedor/clip/swift-flush/Sources/FlushCore/FunctionRegion.swift"
        let file = try XcodeCoverageParser().parseFile(
            fixtureData(named: "xccov-file"),
            expectedPath: path
        )

        XCTAssertEqual(file.path, path)
        XCTAssertEqual(
            file.executableLines,
            (23...28).map { LineExecution(line: $0, count: 21) }
        )
    }

    func testLLVMReaderUsesOnlyExplicitInputs() throws {
        let binary = URL(fileURLWithPath: "/selected/FlushTests")
        let profile = URL(fileURLWithPath: "/selected/default.profdata")
        let executor = StubCommandExecutor(
            responses: [
                [
                    "llvm-cov",
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
                binaries: [binary],
                profile: profile,
                testRun: successfulRun(completedAt: completedAt)
            )
        )

        XCTAssertEqual(report.files.count, 1)
        XCTAssertEqual(report.successfulRunCompletedAt, completedAt)
    }

    func testXcodeReaderUsesOnlySelectedResultBundle() throws {
        let bundle = URL(fileURLWithPath: "/selected/Test.xcresult")
        let path =
            "/Users/fedor/clip/swift-flush/Sources/FlushCore/FunctionRegion.swift"
        let executor = StubCommandExecutor(
            responses: [
                [
                    "xccov",
                    "view",
                    "--archive",
                    "--file-list",
                    bundle.path
                ]: Data("\(path)\n".utf8),
                [
                    "xccov",
                    "view",
                    "--archive",
                    "--file",
                    path,
                    "--json",
                    bundle.path
                ]: try fixtureData(named: "xccov-file")
            ]
        )

        let report = try XcodeCoverageReader(executor: executor).read(
            XcodeCoverageInput(
                resultBundle: bundle,
                testRun: successfulRun(completedAt: Date())
            )
        )

        XCTAssertEqual(report.files.count, 1)
        XCTAssertEqual(report.files[0].executableLines.count, 6)
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
        let reader = XcodeCoverageReader(executor: RejectingCommandExecutor())

        XCTAssertThrowsError(
            try reader.read(
                XcodeCoverageInput(
                    resultBundle: URL(fileURLWithPath: "/selected/Test.xcresult"),
                    testRun: TestRunEvidence(
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
        let bundle = URL(fileURLWithPath: "/selected/Empty.xcresult")
        let xcodeReport = try XcodeCoverageReader(
            executor: StubCommandExecutor(
                responses: [
                    [
                        "xccov",
                        "view",
                        "--archive",
                        "--file-list",
                        bundle.path
                    ]: Data()
                ]
            )
        ).read(
            XcodeCoverageInput(
                resultBundle: bundle,
                testRun: successfulRun(completedAt: Date())
            )
        )

        XCTAssertTrue(llvmFiles.isEmpty)
        XCTAssertTrue(xcodeReport.files.isEmpty)
    }

    private func fixtureData(named name: String) throws -> Data {
        let resourceURL = try XCTUnwrap(Bundle.module.resourceURL)
        let url = resourceURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
            .appendingPathExtension("json")
        return try Data(contentsOf: url)
    }

    private func successfulRun(completedAt: Date) -> TestRunEvidence {
        TestRunEvidence(outcome: .succeeded, completedAt: completedAt)
    }

    private func llvmInput(
        evidence: TestRunEvidence
    ) -> LLVMCoverageInput {
        LLVMCoverageInput(
            binaries: [URL(fileURLWithPath: "/selected/FlushTests")],
            profile: URL(fileURLWithPath: "/selected/default.profdata"),
            testRun: evidence
        )
    }
}

private struct StubCommandExecutor: CommandExecuting {
    let responses: [[String]: Data]

    func execute(arguments: [String]) throws -> Data {
        guard let response = responses[arguments] else {
            throw CoverageInputError.nativeToolFailed(
                tool: arguments.first ?? "xcrun",
                message: "Unexpected arguments"
            )
        }
        return response
    }
}

private struct RejectingCommandExecutor: CommandExecuting {
    func execute(arguments: [String]) throws -> Data {
        throw CoverageInputError.nativeToolFailed(
            tool: arguments.first ?? "xcrun",
            message: "Coverage input was read before validation"
        )
    }
}
