# ADR-003: Coverage input and source-region matching

## Context

Flush needs coverage for function-like regions discovered by source analysis.
SwiftPM packages expose coverage through LLVM tooling, while Xcode projects
expose it through result bundles and `xccov`. Neither representation is the
domain model that the rest of Flush should consume.

Coverage artifacts are not evidence that their test run succeeded. They may
also outlive a source edit. Treating an available artifact as current, successful
coverage would let Flush report a precise but false number.

Paths in coverage data can have build-machine prefixes that differ from paths in
the analyzed checkout. Names and symbols are not stable matching keys for Swift
declarations. A failed or ambiguous match must therefore remain visible rather
than being converted to a percentage.

## Decision

LLVM and Xcode coverage are equally supported, explicitly selected input kinds.
The caller supplies one chosen input; Flush does not search for artifacts or
pick the first file it finds.

Each input has a dedicated reader that normalizes its native data into one
source-oriented representation:

- a source file path;
- executable source lines and their execution counts;
- the successful run's completion time.

The Xcode reader obtains coverage from a specified `.xcresult` bundle through
`xccov`. The LLVM reader consumes explicitly identified LLVM coverage inputs.
Readers may use dependency-specific intermediate models, but those models do not
cross the reader boundary.

A coverage input is valid only when its associated test run is known to have
succeeded and has a known completion time. A reader may recover those facts from
its native input when the format provides them. Otherwise the caller must supply
them explicitly. Missing success or completion metadata rejects the whole input;
the existence of coverage files never implies a successful run.

Function-like regions are matched to coverage by source file and inclusive line
range. File paths are compared by path components using the longest common
suffix. A file match must be unique; an ambiguous suffix is not resolved by
arbitrary ordering. Declaration names and symbols are never matching keys.

Coverage for a matched region is calculated only from executable lines within
its range. The result for every requested region is one of:

- measured coverage, including whether it is fresh or stale;
- unavailable coverage with an explicit reason, including no unique file match
  or no executable line in the region.

No unavailable case is represented as zero, one hundred percent, file-wide
coverage, or an omitted region. Each completed matching operation reports the
number of measured and unavailable regions.

Freshness is determined from the successful test run's completion time. If the
source file's modification time is later than that time, measured coverage for
regions in the file is stale. If the source file cannot be inspected, coverage
for its regions is unavailable rather than assumed fresh.

Parsers for both native formats are tested against committed fixtures captured
from real tool output. Matching tests separately cover missing and ambiguous
files, stale sources, empty reports, missing source files, and regions without
executable lines.

LLVM segment parsing may be derived from
[JordanCoin/crap4swift](https://github.com/JordanCoin/crap4swift). Derived code
must retain the source link in its file header and the original copyright
attribution in `NOTICE`. Its artifact discovery and test-outcome assumptions are
not adopted.

## Alternatives

### Prefer LLVM and translate Xcode projects into LLVM inputs

Rejected because it makes one supported environment depend on reconstruction
outside its native coverage tool and obscures which artifact the caller chose.
Both native sources can instead meet the same explicit contract.

### Automatically discover the newest available artifact

Rejected because filesystem recency does not establish that the artifact belongs
to the analyzed source or that its test run succeeded. Discovery by arbitrary
ordering also repeats the failure mode of selecting the first coverage file.

### Match by declaration names or compiled symbols

Rejected because Swift generics, extensions, overloads, and protocol witnesses
make those identifiers unstable. File and source range are already the identity
established by ADR-002.

### Substitute a numeric value when matching fails

Rejected because zero, one hundred percent, or file-wide coverage each asserts
knowledge Flush does not have. Omitting the region hides the failure and makes
aggregate results look complete.

### Infer freshness from the coverage file's modification time

Rejected because a file may be copied, regenerated, or touched independently of
the successful test run it represents. The run completion time is the relevant
boundary for source changes.

## Status

Accepted
