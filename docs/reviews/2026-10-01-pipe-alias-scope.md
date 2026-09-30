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

## Fixed source

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

## Executed validation

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

## Fixed-SHA packed artifacts

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
