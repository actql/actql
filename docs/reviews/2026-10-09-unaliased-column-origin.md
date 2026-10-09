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

The first normal five-package producer used clean source
`d2a4432462205a456e7109f147db5cf7a3d279d0`. The existing
`--source-free-only` consumer passed the new Local diagnostics and all 23
source-free positive cases, then stopped at the old generic refusal-code check
for `SELECT *`. Receipt: `../.codex-scratch/public-query-evidence-Wts9eI`,
command `010`; bounded wrapper `local-checks/attempts/run-UpLyX1`. HTTPS was
not reached. This is retained failed evidence, not a passing campaign.

A minimal public Local probe against those normal packages (`run-2HX9x7`)
and the retained pre-origin packages from
`5552c96a9716eb40d5038c3db20f68f42fb0f09c` (`run-CLh3Mr`) independently
confirmed the same star result: undetermined, implementation-limit coverage,
and `ClientProgramImplementationLimit`. The earlier source is the reviewed
JOIN/set unit over the same main, not an assertion that it is pristine main.
The unaliased missing-column refusal remained `ClientProgramInvalidInput`
in both; only the new source carries its authored location.

The existing check owner classifies `UnsupportedProjection` as an implementation
limit. The fixture now requires that exact code for source-free star, instead
of accepting one of several unrelated generic input codes. No product category,
row/type/order expectation or resource bound was changed. Unexpected refusal
messages now identify their case. The augmented fixture checks passed 3/3
(`run-QJofqh`, `focused-test-yW5SjY`). The rerun remains necessary to establish both
entrances; no package payload is overlaid and no checker is mocked.

The second clean-source campaign at
`e221efdcd83d9ac68a30a9210667a88618dc10ee` passed all new checks and the existing
23 positive / 27 refusal cases at both Local and HTTPS, then failed its fresh
String Result process. Receipt: `../.codex-scratch/public-query-evidence-uzw0Pi`,
command `010` passed, command `011` failed; wrapper `run-z2nEJU`.
`InstalledHostInitializationFailed` retained primary
`InstalledCheckEnvironmentConflict` with cause `EnvironmentBase`.

The initial fixture explicitly selects `hostCapacityPolicy` and binds its Source
publication to it, but `string-values-restart.mjs` omitted that policy at both
reopened Hosts. The fixture now carries the same authored installation policy
alongside the retained Result references and passes it to both reopen calls.
No policy value, Host conflict check, Result row/schema expectation, owner or
recovery mechanism is changed. The failure is preserved separately from the
successful public diagnostic/Named Result checks; the full selected campaign
still required a rerun at that point.

### Completed exact-source campaign

The final source/fixture revision
`bff980342d0991f4488e4cd8b02d6e8f9cb9005c` completed the selected campaign.
The normal producer packed all five packages with prepack enabled from a clean
checkout. An independent SHA-256 pass matched every manifest entry before the
existing consumer installed outside the repository. It had no MoonBit runtime,
repository imports, adapter overlays or mocked checks.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-unaliased-origin-complete-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-unaliased-origin-complete-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-unaliased-origin-npm-cache \
  node scripts/test-packed-public-query.mjs --source-free-only
```

The commands ran sequentially in one existing `runLocalCheck` heavy slot,
with a 1200-second budget and five-second termination grace; launcher
`/private/tmp/actql-b-unaliased-origin-complete-packed.mjs`. Evidence:
`local-checks/attempts/run-89Gj9r` and
`../.codex-scratch/public-query-evidence-xJ0E27` (relative to this worktree).
The latter receipt has the exact source revision, `dirty: false`,
`status: passed` and `complete: true`. Command `010` is the public application,
and `011` is its fresh-process Result read; both exited zero.

- Local and actual trusted HTTPS each passed the 16 authored-location checks
  (eight examples in each format) and four protected-Source checks. The same
  fixture remains connected to the normal unfiltered consumer. Run/provider
  observations did not change during these checks.
- Each entrance also completed all existing 23 source-free positive and 27
  refusal cases. Positive cases compared independently authored Named Result
  rows, columns/types/order and stream completion, including NULL, duplicate,
  parameter and CTE cases. Refusals admitted no Run or source I/O.
- Fresh Local and HTTPS Host processes re-read the published exact String
  Result rows and descriptions without submitting a new Run.
- The driver's 14 profile-registration tests, README Local/HTTPS example and
  deliberate missing-generated-asset refusal also passed. They are incidental
  driver checks, not a claim of full feature coverage.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `b0dd878cde8efc0af140b5dc94da5fb2b5a1bccc85d408b83cb5a194fe90305a` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The following evidence-only commit changes this review record, not compiled
source, fixtures or package inputs. The campaign remains evidence for the
explicit tested revision, not a new-SHA pack or GitHub CI success. Full Core,
Wasm/native, proof, performance and the complete unfiltered packed corpus were
not run. This unit has no dependency on the separate common BETWEEN blocker.

E can continue using the existing `source_frontend::unknown_column_origin`
accessor and public report location contract. The B change supplies the missing
origin at `query_program::output_name`; E's diagnostic response and SDK remain
the single existing presentation path. This document is a handoff record, not
a claim that an external message was sent or that #384 is fully closed.
