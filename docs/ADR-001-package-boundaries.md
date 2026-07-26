# ADR-001: Package boundaries

## Context

Flush must run locally during the build cycle while keeping the canonical CRAP
metric separate from source analysis and coverage data. The first milestone must
establish boundaries that allow a command-line product now and a build-phase
plugin later, without implementing either analysis or the metric.

The package therefore needs stable responsibilities before implementation begins.
In particular, the analysis foundation must not depend on CRAP, and adding a
metric must not require changing that foundation.

## Decision

The Swift package is divided into these responsibilities:

- `FlushCore` owns source analysis and coverage data. It does not know which
  metrics consume those data.
- `FlushMetrics` owns metric contracts and the metric registry. Metric
  implementations depend on the data exposed by `FlushCore` and register with
  this module.
- The `flush` executable owns command-line coordination and presentation. It
  composes the core and registry without moving their work into the executable.
- Tests mirror the module boundaries so each responsibility can be exercised
  without going through the command line.

A future build-phase plugin will be a thin package integration that invokes the
executable product. Its implementation is deferred, but the executable remains a
separate product so the plugin does not need analysis or metric logic of its own.

The v1 registry will contain only CRAP. The registry is an extension point in the
package structure, not permission to add other metrics to v1.

## Alternatives

### One executable target

Rejected because analysis, metric selection, and presentation would share one
boundary. That would make CRAP part of the foundation by accident and leave the
future plugin coupled to command-line details.

### A target for every pipeline stage and data source

Rejected for the initial package because separate targets for syntax analysis,
coverage ingestion, matching, reporting, and each metric would create boundaries
before their contracts are known. The chosen split preserves the required
independence without premature fragmentation.

### Put the build integration in a separate package

Rejected because the integration and executable must evolve together. Keeping
them in one package lets SwiftPM resolve the executable tool directly and avoids
version drift between the build integration and the tool it runs.

## Status

Accepted
