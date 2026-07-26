// FunctionRegionCollector finds executable declarations in a Swift syntax tree.

import SwiftSyntax

final class FunctionRegionCollector: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    private(set) var regions: [FunctionRegion] = []

    init(
        filePath: String,
        converter: SourceLocationConverter,
        viewMode: SyntaxTreeViewMode
    ) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            append(
                node: node,
                body: body,
                name: qualified(
                    signature: functionSignature(node),
                    from: Syntax(node).parent
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            append(
                node: node,
                body: body,
                name: qualified(
                    signature: initializerSignature(node),
                    from: Syntax(node).parent
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .visitChildren
        }
        append(
            node: node,
            body: body,
            name: qualified(
                signature: "deinit",
                from: Syntax(node).parent
            )
        )
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let accessorBlock = node.accessorBlock else {
            return .visitChildren
        }
        let ownerName = qualified(
            signature: subscriptSignature(node),
            from: Syntax(node).parent
        )
        switch accessorBlock.accessors {
        case .getter(let statements):
            append(
                node: node,
                body: statements,
                name: ownerName
            )
        case .accessors(let accessors):
            append(accessors: accessors, ownerName: ownerName)
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let accessorBlock = binding.accessorBlock else {
                continue
            }
            let ownerName = qualified(
                signature: variableSignature(node, binding: binding),
                from: Syntax(node).parent
            )
            switch accessorBlock.accessors {
            case .getter(let statements):
                append(
                    node: node,
                    body: statements,
                    name: ownerName
                )
            case .accessors(let accessors):
                append(accessors: accessors, ownerName: ownerName)
            }
        }
        return .visitChildren
    }

    private func append(
        node: some SyntaxProtocol,
        body: some SyntaxProtocol,
        name: String
    ) {
        let visitor = CyclomaticComplexityVisitor(viewMode: .sourceAccurate)
        visitor.walk(body)
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        regions.append(
            FunctionRegion(
                filePath: filePath,
                lineRange: start.line...end.line,
                name: name,
                cyclomaticComplexity: visitor.complexity
            )
        )
    }

    private func append(
        accessors: AccessorDeclListSyntax,
        ownerName: String
    ) {
        for accessor in accessors {
            if let body = accessor.body {
                append(
                    node: accessor,
                    body: body,
                    name: "\(ownerName) [\(accessor.accessorSpecifier.text)]"
                )
            }
        }
    }

    private func qualified(signature: String, from parent: Syntax? = nil) -> String {
        let contexts = lexicalContexts(startingAt: parent)
        return (contexts + [normalized(signature)]).joined(separator: ".")
    }

    private func lexicalContexts(startingAt explicitParent: Syntax? = nil) -> [String] {
        var ancestor = explicitParent
        var contexts: [String] = []

        while let current = ancestor {
            if let context = lexicalContext(current) {
                contexts.append(context)
            }
            ancestor = current.parent
        }
        return contexts.reversed()
    }

    private func lexicalContext(_ syntax: Syntax) -> String? {
        namedDeclarationContext(syntax) ?? executableDeclarationContext(syntax)
    }

    private func namedDeclarationContext(_ syntax: Syntax) -> String? {
        if let node = syntax.as(StructDeclSyntax.self) {
            return node.name.text
        }
        if let node = syntax.as(ClassDeclSyntax.self) {
            return node.name.text
        }
        if let node = syntax.as(EnumDeclSyntax.self) {
            return node.name.text
        }
        if let node = syntax.as(ActorDeclSyntax.self) {
            return node.name.text
        }
        if let node = syntax.as(ProtocolDeclSyntax.self) {
            return node.name.text
        }
        if let node = syntax.as(ExtensionDeclSyntax.self) {
            return normalized(node.extendedType.description)
        }
        return nil
    }

    private func executableDeclarationContext(_ syntax: Syntax) -> String? {
        if let node = syntax.as(FunctionDeclSyntax.self) {
            return functionSignature(node)
        }
        if let node = syntax.as(InitializerDeclSyntax.self) {
            return initializerSignature(node)
        }
        if let node = syntax.as(SubscriptDeclSyntax.self) {
            return subscriptSignature(node)
        }
        if let binding = syntax.as(PatternBindingSyntax.self),
           let variable = syntax.parent?.as(VariableDeclSyntax.self) {
            return variableSignature(variable, binding: binding)
        }
        if let node = syntax.as(AccessorDeclSyntax.self) {
            return node.accessorSpecifier.text
        }
        return nil
    }

    private func functionSignature(_ node: FunctionDeclSyntax) -> String {
        normalized(
            "func \(node.name.text)"
                + description(node.genericParameterClause)
                + node.signature.description
                + description(node.genericWhereClause)
        )
    }

    private func initializerSignature(_ node: InitializerDeclSyntax) -> String {
        normalized(
            "init"
                + description(node.optionalMark)
                + description(node.genericParameterClause)
                + node.signature.description
                + description(node.genericWhereClause)
        )
    }

    private func subscriptSignature(_ node: SubscriptDeclSyntax) -> String {
        normalized(
            "subscript"
                + description(node.genericParameterClause)
                + node.parameterClause.description
                + node.returnClause.description
                + description(node.genericWhereClause)
        )
    }

    private func variableSignature(
        _ node: VariableDeclSyntax,
        binding: PatternBindingSyntax
    ) -> String {
        normalized(
            node.bindingSpecifier.text
                + " "
                + binding.pattern.description
                + description(binding.typeAnnotation)
        )
    }

    private func description(_ syntax: (some SyntaxProtocol)?) -> String {
        syntax?.description ?? ""
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
