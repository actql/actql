# Pipe alias and column scope evidence

## Completion unit and agreement

The adopted frontend semantics are authoritative. Incompatible legacy alias
behavior is not retained for compatibility. This unit covers Pipe AS replacement
and the distinction between current columns and original range values across
SET, DROP and RENAME. JSON/YAML Program remains public machine input through the
same checker, planner and Host.

KEEP implementation and retirement of the public STEP/OP surface are separate
units. The adopted INFER/NEAREST output scope is recorded as unimplemented;
operator attempts receive an original-source frontend diagnostic and a typed
Host input refusal before Run acceptance or source acquisition. The corrected
FX-03 expectation does not mark its imported acceptance case executed.

## Original fixed source

- Worktree creation baseline: `7b5bd1678757896fa3f18fc6825ff2e309f2dd15`.
- Adopted main, including Result.describe: `8028e8a708db6a5ef2b82f6d559b3d2bf7e55041`.
- Implementation and local gate SHA: `f7aeed04fe1d697c1e8ae1f0d27db25d8a51b4e0`.
- A subsequent evidence-only commit does not change executable sources.
- Node: 22.23.2. MoonBit: 0.10.12+1634b282e.

AS binds its new name to the current row and removes every old range variable.
Reusing the same name is valid. A SELECT materialization cannot resurrect the
initial FROM alias. SET assignments share the same input snapshot; existing
ranges retain their original slots until displaced. DROP/RENAME affect current
names, not those retained original values.

## Independent expectations and public execution

[`cases.json`](../../spec/frontend/fixtures/pipe-scope/cases.json) contains
hand-authored source rows, output rows, ordered columns and complete field
contracts. No expectation is produced by the new lowerer. Four separately
authored ordinary Program expectations in `scripts/query-program.test.mjs`
verify lowering through the test-only bridge; that comparison is distinct from
the installed Host execution evidence.

The packed runner installs client-wire, sdk, run-host-core, local-node and node
tarballs into a clean directory outside the checkout. Its unchanged application
uses connect, aql, wait, named Result reads and describe against embedded Local
and a real TLS HTTP Host. Both use the installed DuckDB source and its published
alias generation, not a fixture provider or injected frontend schema.

| Fixture group | Executed checks, in each Local/HTTP profile |
| --- | --- |
| SET snapshot | Simultaneous assignment, changed current values, original alias values, NULL and duplicate rows |
| DROP/RENAME | Current names and original alias names/values remain distinct |
| AS current/same name/quoted name | Replacement binds current values, including case-insensitive qualified references |
| AS after projection | Valid WHERE/EXTEND/SELECT consume current columns; old aliases cannot return |
| AS after DROP/RENAME and star | Only current visible names are exported |
| SQL alias projection | Qualified input columns lower through the existing SQL path |
| Empty Result | Ordered columns, full contracts and nullability remain available without row sampling |
| 15 refusals | Removed aliases, removed current names, collisions and unimplemented KEEP surfaces cause no Run acceptance or provider acquisition |

There are 11 successful scope cases and 15 refusal cases per profile. Reads,
attach, exact request resubmission and request lookup do not increase accepted
Run or physical source-stream counts. The default Client gate additionally
runs the existing five SQL/Pipe cases, 18 SGA sources, cancellation and native
CLI acceptance. These are not evidence of full frontend r1 conformance.

## Identity and generated artifacts

Contract versions stay at 0.1. Query scope rules change the Grammar Manifest
logical CID to
`sha256:e897632af8edbfb7d01c4de07f0d79295a1f7696908f8c81d704dc3cebeb9f20`.
Bound Invocation Template, Executable Plan, Compiled Plan and Run Definition
identities that bind this manifest change, including ordinary Values Programs.
Their Program and unchanged AoA identities are not arbitrarily rewritten.

The Local Values/tasks compatibility test retains pre-change preimages from
the reviewed `a74a1c073c6f86a43c41b2aafc62df0820ad5216` runtime. It verifies their
existing fixed CIDs and all relevant self hashes, then changes only the grammar
reference and dependent template/executable/compiled hashes. It compares the
new issued body with this independent canonical migration. The separate
hand-assembled Run materials vector determines the updated fixed Run CID.

The compilation manifest, document metadata and canonical vectors were
regenerated from sources. Workers and Node fixture generators were run in
dependency order and required no fixture changes. Runtime JavaScript is not
committed.

## Original executed validation

All final local commands below ran on the clean implementation SHA above,
through `scripts/local-checks.mjs`:

- `run spec`: passed, including the version and generated-artifact gates.
- `run lint`: passed, including public API, SDK types and isolated Node/Core.
- `run client`: passed, including packed public source and Result descriptions,
  Checkpoint, simulated Salesforce acquisition/Effect and recovery regressions.
- `run core --target js`: 7,084/7,084 passed.
- `run core --target wasm`: 7,080/7,080 passed.
- `run core --target native`: 7,162/7,162 passed after the disk-space retry.

The first native test build stopped with `No space left on device`; its type
check passed. Only this worktree's already-verified JS/Wasm debug outputs were
removed before retry. Sources and logs were retained. This environmental
failure is distinct from a product assertion failure.

While editing, the touched MoonBit packages passed 754 JS tests and the
independent Program/profile/Run-vector Node tests passed 10/10. The focused
packed scope runner also passed; the final default Client run is the fixed-SHA
artifact evidence. Full frontend imported cases, KEEP execution, the wider
numeric/STRUCT/CAST/NULL/order matrix and public STEP/OP removal were not run or
implemented here. No real Salesforce org or Cloud deployment was tested.

## Original fixed-SHA packed artifacts

The successful Client gate recorded these SHA-256 values. Its summary binds the
source revision, command outcomes and durations; stdout/stderr and native
acceptance logs are retained. Expanded packages, cache and temporary Host Stores
were reclaimed after evidence was saved.

| Development tarball | SHA-256 |
| --- | --- |
| client-wire | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| sdk | `823149a8d04223425d9752b29596b72e72d3401ef168e6d164b7ec1557b38cf3` |
| run-host-core | `a6cd2be8ff079241410c31cba65046418a9dbf698428bc529123b1d9e352c302` |
| local-node | `7b17b925c872868a138326829e89c970b2261f10df30575571bb28f3e3d84c54` |
| node | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

Use `node scripts/test-packed-public-query.mjs --alias-scope-only` for the
focused scope acceptance, or the Client job for existing-path regression.
Pinned build dependencies are producer requirements; installed consumers need
no MoonBit toolchain. Linux CI is recorded on the PR's final HEAD, independently
of these local results. Main merge, package publication and deployment are not
performed by this unit.

## Review regression: ORDER expressions after SELECT

The review reproduced a regression introduced by persistent AS scope tracking:
`FROM pair |> AS t |> SELECT x |> WHERE x > 0 |> SELECT x |> ORDER BY x + 1`
was rejected, although every reference addresses the current row. The new
MoonBit regression failed before the correction and passes afterward.

Correction commit: `9e277663ecaa96606454d1f1fc89c0634e89e6a5`.
Fixed acceptance source: `f44e0b52e0fa368ed7ceaf4f1e35eeb1aa78186a`.
The scoped ORDER branch lowers expressions through the common expression
builder using current visible slots and already-computed SELECT bindings.
Identical ORDER expressions share one derived slot. A deferred SELECT, or an
immediate cleanup projection, removes sort-only fields. Persistent AS scope
tracking remains enabled; references never return to the initial FROM alias.
DISTINCT cannot read an omitted input column.

The independent Program fixture uses exactly `x = [2, 1]`, one derived ORDER
slot and an explicit final projection of `x`. Packed acceptance installs
`id = [2, 1]` in the real DuckDB source, then explicitly renames it to `x` and
drops `amount` before the reviewed AS/SELECT/WHERE/SELECT/ORDER sequence.
The expected Named Result is `[{x:1},{x:2}]`, with one nonnullable number column
named `x`. The removed `records` alias in an ORDER expression is rejected
before admission or acquisition. A separate same-name input/output collision
checks that an ORDER expression uses the already-computed output alias.

The first packed fixture tried to manufacture reverse order with extra
operators and reached the existing physical execution limit. This was an
unsuitable fixture setup, not successful acceptance. Diagnostic copies confirmed
the failure as `Execution(Physical(ExecutionLimit))`; they are not acceptance
artifacts. The final fixture installs the required rows directly, and no
capacity ceiling, authorization, provider or strategy is changed.

On the fixed acceptance source, the focused packed runner passed all 13 normal
cases and 16 refusals in each Embedded Local/TLS HTTP profile. Expected rows
and public describe columns are independently authored. Its generated package
tree was reclaimed after recording command output and tarball hashes. The
local-node tarball digest is
`93ffe1bb5ea627f00c72f0196e6c521243614a28901f3cca99d58cc010be04bf`;
the other four tarball digests match the original table above.

Related frontend tests passed 75/75 on each JS, Wasm and native target. The
independent query Program tests passed 5/5. Formatting and diff checks passed.
The new local lint attempt passed its preceding steps but stopped while
copying the isolated Node module fixture with `ENOSPC`; it is not recorded as
a completed gate. Full local Client/spec/Core jobs are not claimed rerun on
this correction. Required jobs are checked on the final PR HEAD in CI.
The original final-HEAD CI passed on `40ee88e9e`, before this review correction;
it is distinct from the corrected HEAD's CI result recorded in PR #107.
