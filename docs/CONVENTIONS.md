# Conventions

## Comments

Inline comments inside functions are prohibited. If a function needs an
explanation of what or why it does, rewrite its names and structure until that
intent is clear.

Exactly two forms of source comment are allowed:

1. A single-line header at the beginning of a file.
2. A `///` documentation comment immediately above public API.

Compiler and dependency workarounds belong in the commit message or issue, not
in source comments.

`TODO` and `FIXME` entries must include an expiry date in `[yyyy-MM-dd]` format.
The expiry must be no later than two iterations after the entry is introduced.

## Design

SOLID principles are mandatory.

IOSP is mandatory: a method either performs work or coordinates calls to other
methods. It must not combine those responsibilities.

A dependency contract is declared by its consumer. Its implementation is named
an adapter or a `Service`.

The architecture terms `port`, `ports & adapters`, and `hexagonal architecture`,
including translations of these terms, are prohibited in source code, type names,
file names, architecture decision records, and issue comments.

## Attribution

When code is derived from an MIT-licensed project:

- preserve the original author's copyright in `NOTICE`;
- include a source link in the file header.

Rewriting borrowed code does not remove the attribution requirement.
