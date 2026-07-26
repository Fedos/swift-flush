// CyclomaticComplexityVisitor counts syntax-defined execution paths.

import SwiftSyntax

final class CyclomaticComplexityVisitor: SyntaxVisitor {
    private(set) var complexity = 1

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        node.bindings.contains { $0.accessorBlock != nil } ? .skipChildren : .visitChildren
    }

    override func visit(_: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: IfExprSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if case .case = node.label {
            return increment()
        }
        return .visitChildren
    }

    override func visit(_: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        increment()
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let decisionOperators = ["&&", "||", "??"]
        if decisionOperators.contains(node.operator.text) {
            return increment()
        }
        return .visitChildren
    }

    private func increment() -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
}
