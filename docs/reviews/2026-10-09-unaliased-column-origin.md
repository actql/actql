# Unaliased unresolved-column origin

Date: 2026-10-09. Base: `b40818e09295dba39de6b570b977610e95c75b1e`.
Related request: [#384](https://github.com/actql/actql/issues/384).

## Defect and boundary

`SELECT missing` rejected an unknown reference without retaining its authored
location, whereas `SELECT missing AS n` retained bytes 7..14. The fast
unaliased-column path in `query_program::output_name` checked the existing
column resolver and then raised an unlocated `UnknownColumn`. The query AST
already owned the exact original occurrence; no text search was necessary.

The repair keeps the same resolver, ambiguity and longest-prefix rules. When
that occurrence has an origin, the unresolved projection now returns the existing
`Expression(UnknownReference)` issue with that origin. The existing
`source_frontend::unknown_column_origin` and Host check projection carry it to
the public report. No SDK diagnostic reconstruction or new public API is added.
Unlocated errors remain unlocated; generated origins remain excluded from public
authored locations. This is not a claim that every `UnknownColumn` path is fixed.

Successful Program values, identity, scope, predicates, limits, order and type
checking are unchanged. Disclosed Source lookup still precedes column resolution.
Protected absent/denied/closed/delegated Source contexts remain equivalent and
do not disclose a column failure. The SDK, check response and Source authorization
implementations are unchanged.

## Independent examples

The selected MoonBit regression and packed fixture specify original UTF-8 byte
ranges independently of product origin/canonicalization helpers:

| Submitted text | Expected failed range |
|---|---|
| `SELECT missing` | 7..14 |
| emoji block comment, CRLF, then `SELECT missing` | 17..24 |
| `SELECT` followed by backtick-quoted composed accent and emoji | 7..15 |
| `SELECT` followed by backtick-quoted decomposed accent and emoji | 7..16 |
| `SELECT missing FROM records` | 7..14 |
| `SELECT records.missing FROM records` | 7..22 |
| `SELECT id, missing FROM records` | 11..18 |
| `/* missing */ SELECT missing` | 21..28 |

Both `sql` and `aql-text` use the existing source boundary. Copied reports and
edited input cannot acquire the SDK's location custody. Protected Source cases
must stay undetermined without reasons. The normal packed public-check application
executes the fixture at both entrances and compares Run/provider observations
before and after; these checks must admit no Run and perform no provider I/O.

## Focused verification

Use the pinned Node 22.22.0 and MoonBit `0.10.12+1634b282e` toolchain.
Commands below run from this worktree. Evidence directories are under `_build`.

Before the repair, the new MoonBit origin test failed 0/1:
`local-checks/attempts/run-Z5IVq6`, `focused-evidence/focused-test-JUsaLq`.
After the repair, two old exact `UnknownColumn` expectations failed as expected;
they now require the specific located `Expression(UnknownReference)` refusal.
Missing or displaced receivers remain inaccessible and ambiguous receivers remain
ambiguous. The selected five files passed 28/28:
`local-checks/attempts/run-kTzhtV`, `focused-evidence/focused-test-QbrTIs`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 240 -- --target js \
  src/source_frontend/unaliased_column_origin_test.mbt \
  src/source_frontend/lower_test.mbt \
  src/query_program/implicit_property_projection_test.mbt \
  src/query_program/grouped_implicit_property_name_test.mbt \
  src/query_program/aggregate_signed_order_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/unaliased-column-origin.test.mjs
node scripts/build-runtime-packages.mjs local-node
node scripts/local-checks.mjs test node --timeout-seconds 240 -- \
  --test-name-pattern 'unresolved column expressions retain authored source positions|bare unresolved columns retain owned explanations and authored locations|bare column explanations preserve protected Source equivalence' \
  adapters/host-node/client-check.test.mjs
```

The fixture checks passed 2/2: `local-checks/attempts/run-U5bn9o`,
`focused-evidence/focused-test-WM7Hxw`. The selected public Node checks passed
6/6: `local-checks/attempts/run-uRo24z`,
`focused-evidence/focused-test-CSc4dc`. They exercised Local and trusted HTTPS,
including the unchanged protected-Source equivalence regression.

Earlier preparation failures are not passes: `run-FFJzZ5` completed runtime
preparation but nested a second worktree lock; `run-NAomVs` could not load the
optional pinned DuckDB dependency; `run-0DAxWM` used a borrowed root dependency
link resolving another worktree's client-wire and rejected requests before Host
checking. The root link was removed without modifying its donor, and `npm ci`
installed the current lockfile. The optional DuckDB dependency remains a protected
borrow of the matching pinned `1.5.5-r.4` installation.

Formatting and `git diff --check` passed. These are focused JS/Node results,
not full Core, Wasm/native, proof, performance or GitHub CI results.

## Packed verification and E handoff

Normal five-package production and the existing `--source-free-only` consumer
are the next check. Until their receipt is recorded, external tarball acceptance
is unverified. No package payload is overlaid and no checker is mocked.

E can continue using the existing `source_frontend::unknown_column_origin`
accessor and public report location contract. The B change supplies the missing
origin at `query_program::output_name`; E's diagnostic response and SDK remain
the single existing presentation path. This document is a handoff record, not
a claim that an external message was sent or that #384 is fully closed.
