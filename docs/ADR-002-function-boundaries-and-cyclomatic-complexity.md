# ADR-002: Function boundaries and cyclomatic complexity

## Context

CRAP requires cyclomatic complexity for every executable function-like region.
The source analysis must therefore find more than `func` declarations: computed
properties and accessors are especially important because they often contain the
main logic of SwiftUI types.

The result must also remain meaningful when declarations are nested, overloaded,
or written in extensions. Coverage will be joined later by file and source range,
so a display name must not become an accidental matching key.

Cyclomatic complexity has several Swift-specific interpretation points. Flush
needs one explicit rule set so its numbers are reproducible and comparable rather
than dependent on incidental visitor behavior.

## Decision

Flush produces one record for each executable:

- function, including generic and nested functions;
- initializer and deinitializer;
- subscript;
- implicit getter of a computed property;
- explicit `get`, `set`, `willSet`, and `didSet` accessor.

Declarations without an executable body do not produce records. An explicit
accessor produces its own record; its property does not produce a duplicate
aggregate record. Declarations in extensions follow the same rules.

Each record contains its file path and the inclusive line range from the first
non-trivia token to the last non-trivia token of that declaration or accessor.
That location is its identity for later coverage matching. Its human-readable
name includes its lexical declaration context, declaration signature, and an
accessor suffix where applicable. Names are presentation data and are never used
as matching keys.

A nested function is a separate record. Branches inside it contribute only to
that nested record, never to the enclosing function. A closure is not a separate
record; branches in its body contribute to the innermost enclosing function-like
record.

Cyclomatic complexity starts at 1 and increases by 1 for every occurrence of:

- `if`, including every `else if`; a plain `else` adds nothing;
- `guard`;
- `for`, `while`, and `repeat`;
- `catch`;
- each non-`default` switch case clause, regardless of the number of patterns in
  that clause; `default` adds nothing;
- a ternary conditional;
- each short-circuiting `&&`, `||`, and `??` operator.

Other condition-list elements, optional chaining, `try?`, and `as?` do not add
complexity unless they contain one of the constructs above. This keeps the rule
syntax-based and reproducible while counting explicit alternative execution
paths. In particular, `default` is the remaining route after the preceding case
tests, not another independent decision.

This rule intentionally differs from SwiftLint's `cyclomatic_complexity` rule:
Flush counts the nil-coalescing operator `??`, while SwiftLint does not. Flush
counts it because evaluation selects between the optional value and a
conditionally evaluated fallback, creating an alternative execution path. As a
result, Flush and SwiftLint cyclomatic-complexity numbers are not directly
comparable, even when both analyze the same source file.

The source walk may be derived from
[SlopGuard-Swift](https://github.com/JeevanThandi/SlopGuard-Swift), whose
function-like coverage and cyclomatic rules match this decision. Only the
cyclomatic analysis is in scope. Derived code must retain the source link in its
file header and the original copyright attribution in `NOTICE`.

Every listed declaration form and complexity increment must have a fixture that
asserts the exact record and number. Completeness fixtures must also cover
computed `body` properties, extensions, generics, overloads, nested functions,
closures, and explicit and implicit accessors.

## Alternatives

### Count nested functions in both their own and their parent's complexity

Rejected because it double-counts the same branches and makes the parent's number
depend on whether a helper is nested or moved to type scope.

### Emit closures as independent function records

Rejected because the milestone defines closures as part of the function where
they are written. Treating them as separate records would also introduce a new
coverage-matching boundary without a source declaration identity.

### Count `default` as another switch decision

Rejected because `default` does not test a new predicate. Counting only
non-default case clauses preserves the base path as the unmatched route.

### Ignore ternaries and short-circuiting operators

Rejected because each can avoid evaluating part of an expression and therefore
creates another execution path. Omitting them would systematically understate
the complexity used by CRAP.

## Status

Accepted
