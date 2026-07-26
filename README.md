# Flush

**F**unction-**L**evel **U**ncovered **S**tructural **H**azard is a quality gate
for Swift code.

Flush is under active development and is not yet ready for use.

## CRAP

Flush will evaluate the canonical Change Risk Anti-Patterns metric introduced
by Alberto Savoia and Bob Evans in 2007:

```text
CRAP(f) = CC(f)² × (1 − cov(f))³ + CC(f)
```

`CC(f)` is the cyclomatic complexity of function `f`, and `cov(f)` is its test
coverage from 0 to 1.

The name **Flush** and its expansion belong to this project. The CRAP metric
does not: Flush uses the existing Savoia/Evans definition without modifying
its formula.
