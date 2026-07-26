# ADR-004: Xcode function coverage authority

## Context

ADR-003 defines source file and inclusive line range as the identity used to
join analyzed regions with coverage. It also selects `xccov` as the native
reader for an explicitly supplied Xcode result bundle.

The Xcode archive and report views do not expose equivalent information. In a
real result bundle, `LLVMCoverageReader.read(_:)` occupied 22 executable lines.
The archive file view exposed two uncovered lines after combining top-level and
nested counts, producing 20/22. The report view exposed the enclosing function
as 21/22 and its nested closure separately as 0/3.

The same source file appeared under both `FlushCore` and `FlushCoreTests`.
Their file totals and function summaries were identical, so combining targets
did not explain the difference. The archive view also marked every line from
the function's first through last line executable, confirming that the two
views disagreed about function attribution rather than the executable-line set.

The archive's file-oriented records do not identify which function owns a line
or nested range. Reconstructing Apple's function result from those records
would therefore require undocumented assumptions. A precise number derived
from such assumptions would violate Flush's requirement to remain explicit
when coverage cannot be matched safely.

## Decision

For Xcode inputs, Apple's function summaries from `xccov view --report --json`
are authoritative. Flush consumes their covered-line and executable-line
totals directly instead of reconstructing function coverage from the archive's
file-oriented line records.

This decision refines only the Xcode normalization part of ADR-003. LLVM inputs
remain normalized to executable source lines. Xcode inputs instead normalize to
function summaries while preserving ADR-003's shared identity, freshness, and
honest-failure rules.

Apple function summaries and LLVM line-oriented coverage can produce different
numbers for the same source because Apple attributes a nested closure to a
separate function summary while LLVM line coverage remains inside the enclosing
source region. LLVM coverage defines the reference semantics for v1. Coverage
numbers produced from these different inputs must not be compared with each
other. Implementing Xcode coverage is deferred until after v1.

An Xcode function summary is joined to a `FunctionRegion` by the uniquely
matched source file and the summary's declaration line:

- a unique summary whose line equals the region's first line is selected;
- when there is no summary on the first line, a sole summary whose line lies
  inside the inclusive region may be selected;
- multiple summaries at the required line, or multiple in-range summaries
  without a first-line match, make coverage unavailable as ambiguous.

Function names and compiled symbols are not matching keys. This keeps the
source-location identity established by ADR-002 and ADR-003 while preventing a
nested closure summary from being substituted for its enclosing declaration.

Identical summaries for the same source location in multiple targets are
coalesced. Conflicting summaries for that location are unavailable rather than
combined by an invented rule.

Measured Xcode coverage is the selected summary's covered-line count divided by
its executable-line count. A zero executable-line count is unavailable. The
successful-run validation, source freshness check, measured and unavailable
totals, and explicit unavailable reasons from ADR-003 still apply.

Fixtures must retain the relevant shape from real `xccov` report output.
Regression coverage must include nested function summaries, identical
multi-target summaries, conflicting multi-target summaries, and ambiguous
in-range summaries. A live Xcode verification must compare Flush's result with
the independent `xccov` report for the same result bundle.

## Alternatives

### Reconstruct Xcode function coverage from archive line records

Rejected because the file-oriented archive view loses function ownership. The
observed nested closure produced 20/22 from line records while Apple's function
summary produced 21/22, even though both views described the same 22 executable
lines.

### Infer additional rules for nested ranges

Rejected because neither the archive format nor the observed data establishes
a complete rule that reproduces Apple's function summaries. A heuristic that
fixes one nested closure can silently fail for another language construct or
toolchain release.

### Keep line reconstruction and warn about incompatibility

Rejected because the native function summary already provides an authoritative
number that users can verify independently. Declaring avoidable incompatibility
would preserve a known mismatch in the primary Xcode workflow.

## Status

Accepted
