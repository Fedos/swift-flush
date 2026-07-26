# ADR-005: CRAP evaluation and threshold semantics

## Context

ADR-001 assigns metric contracts and implementations to `FlushMetrics`, while
ADR-002 and ADR-003 provide cyclomatic complexity and an explicit measured-or-
unavailable coverage result for every function-like region.

CRAP requires both values. Treating unavailable coverage as zero coverage would
produce a precise but invented score, and dropping the region would make a run
appear more complete than it is. Measured coverage may also be stale; calculating
a score must not erase that fact.

The metric registry must express which inputs each metric requires. CRAP needs
coverage, but a future syntax-only metric must not force coverage ingestion merely
because it shares the registry. The v1 registry still contains only CRAP.

A threshold controls verdicts, but v1 has no default threshold. The boundary
behavior must be explicit so the same score cannot pass in one integration and
fail in another.

## Decision

`FlushMetrics` owns CRAP evaluation and its registration. CRAP declares that it
requires function-region coverage. The registry exposes metric input
requirements so coordination can obtain coverage only when a selected metric
needs it. This requirement is metric metadata, not an assumption embedded in
source analysis or coverage reading.

For measured coverage, Flush calculates the canonical score:

`CC² × (1 − coverage)³ + CC`

`CC` is the region's cyclomatic complexity from ADR-002, and `coverage` is the
measured executable-line fraction from ADR-003 in the closed interval from zero
through one. The calculation does not round intermediate values. Presentation
may format a score later, but verdicts use the unrounded value.

Every requested region remains present in the evaluation result:

- measured coverage produces a score and retains its freshness;
- unavailable coverage produces no score and preserves the unavailable reason
  unchanged.

The run summary reports the number of scored regions and the number of unscored
regions grouped by unavailable reason. An unscored region never receives a
verdict and never counts as passed.

A threshold is an explicit evaluation input. When it is present, a score violates
the threshold only when `score > threshold`; a score equal to or below the
threshold passes. The threshold is therefore the highest accepted score.
Comparison uses the unrounded score.

When no threshold is supplied, scores may still be calculated, but no regional
verdict is produced. The evaluation result exposes the missing threshold as an
explicit run-level condition. FlushMetrics provides no default or recommended
threshold.

Reference tests use manually calculated values for fully covered, fully
uncovered, trivial, and boundary-coverage cases. Contract tests also preserve
unavailable reasons and freshness, verify summary counts, cover values below,
equal to, and above a threshold, and verify the explicit no-threshold condition.

## Alternatives

### Require coverage whenever the registry is used

Rejected because it would make future syntax-only metrics depend on coverage
artifacts and successful test-run evidence they do not need. Input requirements
belong to each metric.

### Substitute zero coverage when coverage is unavailable

Rejected because it converts missing knowledge into a large CRAP score. The
result would accuse a function of risk when Flush only knows that matching or
measurement failed.

### Omit regions without scores

Rejected because omission hides incomplete evaluation and makes summary totals
look authoritative. Preserving each region and its reason keeps the failure
visible to later reporting and gate decisions.

### Treat equality as a threshold violation

Rejected because a configured threshold represents the highest accepted score.
Failing at equality would make the effective allowed maximum smaller than the
value the caller supplied.

### Place CRAP evaluation in `FlushCore`

Rejected because it would reverse ADR-001's dependency direction by teaching
source analysis and coverage infrastructure about a specific metric.

## Status

Accepted
