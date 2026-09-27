# Frontend PR-1: generated source admission

## Unit and baseline

PR-0 was merged as `095b8b8c27c65dafb318dcfd83288595263c1ce4`.
PR-1 supplies the bounded source builder, original-source coordinates and the
checked structural admission bridge. It does not implement structural text,
SQL, the formatter or new SDK routing. Those remain later units.

The [API and accounting design](../design/program-source-builder.md) describes
the public operations, ownership, retention and error behavior. Existing
JSON/YAML fallback, Program semantics and canonical identity preimages remain
unchanged. There is no new wire schema or contract version.

## Evidence mapping

| Requirement | Executable evidence | Scope |
| --- | --- | --- |
| Original byte/scalar/UTF-16 locations, malformed input, NFC/CRLF | `src/frontend_source_map/origin_test.mbt` | Builder support for LEX-01/02/12; text/query lexer is still pending |
| Duplicate keys and normalized collisions | `src/program_source_builder/builder_test.mbt` | Builder support for LEX-04; no text parser claimed |
| Exact and one-over byte/node/depth/string/origin/output limits | Builder tests and `src/stage_syntax/generated_test.mbt` | PR-1 limits; token limits belong to the later lexer |
| Forged usage, invalid spans and foreign owners | Builder tests | SYS-07 construction/admission obligation; editable accounting is never authoritative |
| Cycles and exponential shared-node expansion | Builder tests | Bounded construction; CTE/pattern expansion in SYS-08 remains pending |
| Closed Program envelope and structural diagnostic subject | Stage syntax generated tests | Same decoder and source spans; no unchecked constructor |
| Metadata, parameters, explicit empty Effects and stage imports | Stage syntax generated tests | Generated tree equals the existing JSON/YAML tree and retains measured usage |
| Common checker and Unit identities | `src/program_check/generated_source_test.mbt` | Existing checked fixtures; the new builder is not its own oracle |
| Cross-target public API | `scripts/check-moonbit-api.mjs` | Generated JS/Wasm/native interfaces; final result is recorded in the PR |

The 140 imported cases remain pending until their full frontend scenario is
executed. This table records component evidence rather than claiming that a
builder test executes a future SQL, text, Client or Host scenario.

## Reproduction

Use the pinned toolchain. Run the four touched packages' tests for each of
`js`, `wasm` and `native`: `frontend_source_map`, `program_source_builder`,
`stage_syntax` and `program_check`. Run the current repository's `lint`, `core`
and `spec` jobs with `scripts/local-checks.mjs`; common core changes use all
three targets. Generate public interfaces with `moon info` and verify them with
`node scripts/check-moonbit-api.mjs` after staging the generated files.

Fixed source SHA, actual command results and CI are recorded in the PR's
Validation section. This document is an evidence map, not an assertion that
pending commands succeeded. Existing independent CID oracle files and the
immutable imported requirements are not regenerated from product output.
