// SwiftSourceAnalyzerTests verifies Swift function discovery and complexity rules.

import FlushCore
import Foundation
import XCTest

final class SwiftSourceAnalyzerTests: XCTestCase {
    func testDiscoversEveryRequiredFunctionLikeRegion() throws {
        let regions = try analyze(discoverySource)

        XCTAssertEqual(regions.count, 12)
        XCTAssertEqual(
            regions.map(\.name),
            [
                "Example.init(value: Int)",
                "Example.deinit",
                "Example.func transform<T>(_ value: T) -> T",
                "Example.func transform<T>(_ value: T) -> T.func nested(_ input: T) -> T",
                "Example.func transform(_ value: Int) -> Int",
                "Example.var body: Int",
                "Example.var observed [willSet]",
                "Example.var observed [didSet]",
                "Example.var explicit: Int? [get]",
                "Example.var explicit: Int? [set]",
                "Example.subscript(index: Int) -> Int",
                "Example.func extended()"
            ]
        )
        XCTAssertEqual(
            regions.map(\.cyclomaticComplexity),
            [1, 1, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2]
        )
        XCTAssertEqual(
            regions.map(\.lineRange),
            [
                2...4,
                6...8,
                10...24,
                11...16,
                26...28,
                30...35,
                38...42,
                43...47,
                51...53,
                54...56,
                59...64,
                68...70
            ]
        )
    }

    func testCountsEveryCyclomaticConstructExactly() throws {
        let source = """
        func decisions(_ value: Int?, flags: (Bool, Bool)) {
            if flags.0 {
            } else if flags.1 {
            } else {
            }
            guard let value else { return }
            for index in 0..<value {
                while index > 0 {
                    repeat {
                        print(index)
                    } while false
                }
            }
            do {
                try work()
            } catch {
                print(error)
            }
            switch value {
            case 0, 1:
                break
            case 2:
                break
            default:
                break
            }
            _ = flags.0 ? value : 0
            _ = flags.0 && flags.1 || false
            _ = value ?? 0
            _ = value?.description
            _ = try? work()
            _ = value as? Int
        }
        """
        let regions = try analyze(source)

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].cyclomaticComplexity, 14)
        XCTAssertEqual(regions[0].lineRange, 1...33)
    }

    func testNestedFunctionDoesNotIncreaseParentAndClosureDoes() throws {
        let source = """
        func outer() {
            func nested() {
                if Bool.random() {}
            }
            let closure = {
                guard Bool.random() else { return }
            }
            closure()
        }
        """
        let regions = try analyze(source)

        XCTAssertEqual(regions.map(\.cyclomaticComplexity), [2, 2])
        XCTAssertEqual(regions.map(\.lineRange), [1...9, 2...4])
    }

    func testIgnoresDeclarationsWithoutExecutableBodies() throws {
        let source = """
        protocol Requirement {
            func function()
            init()
            subscript(index: Int) -> Int { get }
            var property: Int { get set }
        }
        """

        XCTAssertTrue(try analyze(source).isEmpty)
    }

    func testAnalyzesMultipleFilesInPathOrder() throws {
        let directory = makeSourceDirectory()
        let first = try makeSourceFile(
            name: "A.swift",
            source: "func first() {}\n",
            directory: directory
        )
        let second = try makeSourceFile(
            name: "B.swift",
            source: "func second() {}\n",
            directory: directory
        )

        let regions = try SwiftSourceAnalyzer().analyze(files: [second, first])

        XCTAssertEqual(regions.map(\.name), ["func first()", "func second()"])
        XCTAssertEqual(regions.map(\.filePath), [first.path, second.path])
    }

    private func analyze(_ source: String) throws -> [FunctionRegion] {
        let file = try makeSourceFile(name: "Fixture.swift", source: source)
        return try SwiftSourceAnalyzer().analyze(files: [file])
    }

    private func makeSourceDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeSourceFile(
        name: String,
        source: String,
        directory: URL? = nil
    ) throws -> URL {
        let directory = directory ?? makeSourceDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent(name)
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private var discoverySource: String {
        """
        final class Example {
            init(value: Int) {
                _ = value
            }

            deinit {
                print("done")
            }

            func transform<T>(_ value: T) -> T {
                func nested(_ input: T) -> T {
                    if Bool.random() {
                        return input
                    }
                    return input
                }
                let closure = { (flag: Bool) in
                    if flag {
                        print(flag)
                    }
                }
                closure(true)
                return nested(value)
            }

            func transform(_ value: Int) -> Int {
                value
            }

            var body: Int {
                if Bool.random() {
                    return 1
                }
                return 0
            }

            var observed = 0 {
                willSet {
                    if newValue > 0 {
                        print(newValue)
                    }
                }
                didSet {
                    guard observed >= 0 else {
                        return
                    }
                }
            }

            var explicit: Int? {
                get {
                    Bool.random() ? 1 : 0
                }
                set {
                    _ = newValue ?? 0
                }
            }

            subscript(index: Int) -> Int {
                if index > 0 {
                    return index
                }
                return 0
            }
        }

        extension Example {
            func extended() {
                while Bool.random() {}
            }
        }
        """
    }
}
