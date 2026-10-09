# QUALIFY demand of an embedded SELECT window

## Reproduction and minimal repair

Dependency: PR #1177 at `e5a838a3c6e555daf04a29fe89dfb6bfc42c3852`.
Fetched main remains `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.
This branch does not depend on the separate Pipe-consumer PR #1181.

A checked schema supplies public numeric `id` and `aql_select_window_0`.
Rows `(id=2,user=10), (id=1,user=90)` separate the user value from rank.

```sql
SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos
FROM records
QUALIFY pos > 2
ORDER BY id DESC
```

The correct result contains only `(id=2,user=10,pos=3)`. The same query with
`GROUP BY ALL` has the same result on these distinct input rows. Both rejected
with `Expression(UnknownReference)` when QUALIFY demanded the embedded SELECT
expression before final projection. The QUALIFY alias materialization callback
appended private window bindings to input columns, reintroducing the ambiguity
that #1177 removed from final SELECT.

Only that callback now uses #1177's shared private-expression scope adapter.
The evaluated alias is cached by the existing materializer and reused in final
SELECT, not expanded or evaluated twice. Public schema fields and qualified
input receivers remain intact. Checker, evaluator, execution Owners, grammar,
contract identities and pins are unchanged.

The superficially similar ORDER-window callback was inspected. An alias
containing a window value is rejected before that callback when another window
tries to use it as an input. The exact existing `UnsupportedAnalytic` rejection
is retained by a focused test; this PR does not change that language boundary
or modify an unproven path.

## Independent expectations

- A complete hand-authored Values/analytic/derive/filter/select/sort Program
  passes the normal checker independently of source lowering.
- Focused lowering requires the add operand to be evaluated analytic slot 3
  (two checked fields plus the reserved output alias). The add occurs once.
- Lowercase and uppercase schema-only names retain public columns. Named
  windows, quoted aliases and explicit qualified user-value operands retain
  their distinct meanings.
- Eleven added public positives include ordinary JSON controls, both case
  forms, GROUP BY ALL, named/quoted syntax, NULL, empty input and duplicate
  rows. `QUALIFY pos > 2` retains duplicate id=2 rows with pos 4/3; comparison is
  multiplicity-aware. A qualified nullable user operand instead produces
  pos=91/id=1 and a nullable result contract.
- Two added public refusals cover a hidden QUALIFY slot and a window-valued
  alias used as another window input, with distinct existing error categories.
- The existing normal and narrow public consumer compares rows, full
  Result.describe types/nullability, declaration order, stream completion and
  request replay. No compiler-output-derived expectation, Program patch,
  new harness, Owner or fallback is introduced.

## Focused evidence

Paths are relative to this checkout unless absolute. Guard directories are
under `_build/local-checks/attempts`; test directories under
`_build/focused-evidence`.

- Before product repair: 0/2, exact `UnknownReference` in ordinary and grouped
  SELECT: `run-Kr1YRr` / `focused-test-tyHTYP`. This is lowering evidence, not
  a failed public Run.
- Minimal repair with existing caller tests: 23/23,
  `run-17aBm7` / `focused-test-q5Lkeh`.
- Expanded final JS: 26/26, `run-V6aQVF` / `focused-test-trBjLI`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/qualify_private_window_alias_test.mbt src/query_program/qualify_test.mbt src/query_program/quoted_qualify_test.mbt src/query_program/select_window_private_scope_test.mbt src/query_program/window_scalar_projection_test.mbt`.
- Node fixture checks: 9/9, `run-uYmtT5` / `focused-test-Mfq83Y`.
  Command: `node scripts/local-checks.mjs test node -- scripts/window-scalar-source-input.test.mjs`.

The first expanded selection passed 25/26 at `run-kpSXrZ` /
`focused-test-TWCurJ`: the new named-window test mistakenly placed WINDOW before
QUALIFY. Correcting only the test to the existing clause order resolved it.
No grammar or product change was made for that test-writing error.

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used. Changed-file
formatting and `git diff --check` passed. The narrow corpus is now 81 positive,
39 refusal and one deliberate execution-failure case per transport.

## Packed evidence and common capacity boundary

Product/fixture source: `d66bd47ef3a77cfa477be3411d81af24026a95ef`, clean.
Normal five-package production and independent SHA-256 verification ran under
guard `run-RVScUW` using `/private/tmp/actql-b-qualify-private-window-packed.mjs`.
The consumer command was `node scripts/test-packed-public-query.mjs --window-scalar-only`
with `ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-qualify-private-window-d66bd47ef-pack`.
The original receipt is
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-HHX2xY`.
Its source is clean, digest errors are empty, command 010 exited 1, and the
temporary installation was removed after evidence preservation (absence checked).

The first new positive, `window-scalar-schema-private-qualify-json`, was
admitted but ended `failed / ACTQL_E_UNPUBLISHED_RUN`. Later new cases and HTTPS
were not reached by that acceptance campaign. No success is claimed for them.
The expectations, filter, sorting, input bounds and Host budget remain unchanged.

The same five tarballs were then installed outside the checkout for three
minimal diagnostics: independent JSON, SQL and GROUP BY ALL. Public SDK/Host
observation confirmed all three fail with `CapturedRunPublicationFailed` before
publication. A separate Node inspector diagnostic, without runtime edits or
Program patches, identified the nested common failure as
`LocalManagedStart(Execution(Physical(ExecutionLimit)))` and inspected the
prepared reservation. The exact variant mapping was checked against the pinned
source and generated bridge, rather than inferred from the public terminal code.

| Input | Prepared execution/scratch bytes | Prepared retention bytes | Execution budget |
|---|---:|---:|---:|
| Independent JSON | 601,097,472 | 14,240,000 | 536,870,912 |
| SQL | 554,326,016 | 14,240,000 | 536,870,912 |
| GROUP BY ALL | 554,326,016 | 14,240,000 | 536,870,912 |

Transfer and all Ledger usage counters, including attempts and reserved
execution bytes, were zero at the refusal. That does not prove the next
reservation fits the budget. It remains unproven whether capacity derivation is
overly conservative or the checked Program legitimately exceeds the fixed limit.
The frontend fix does not alter the common capacity owner.

Uninstrumented failure observation: guard `run-a1tIUE`. Variant diagnostic:
`run-gceo9X`. Final reservation diagnostic: `run-O6V1Iv`, command
`node /private/tmp/actql-b-qualify-diagnostic-wrapper.mjs`, invoking
`/private/tmp/actql-b-qualify-diagnostic-d66bd47ef/capacity-detail-probe.mjs`.
These diagnostic wrappers exit 0 after collecting observations of failed Runs;
their successful completion is not successful execution acceptance. Logs, stores
and installation custody remain preserved in the diagnostic directory.

[Minimal input, independent Program and common-owner handoff](2026-10-10-qualify-private-window-capacity.md).

Independently recomputed five-package digests, also matching the original receipt:

| Package | SHA-256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `9fb890689ec9ff5dbcfc8d774c456b055e4d1ab01e0654838a24a3597022139f` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

## Remaining verification

Clean-source public execution acceptance is incomplete at the common capacity
boundary. Resume the unchanged cohort after an adopted common-owner resolution;
do not exclude the JSON control or remove QUALIFY/ORDER to obtain a passing run.
Parent packed evidence is not child-HEAD evidence. Submitted-HEAD CI,
Wasm/native execution, full Core and the complete frontend campaign have not
been run locally. This unit does not establish completion of every frontend
semantic boundary. Final target is main after #1177 merges; keep the stacked
base until then. No merge or manual CI rerun is requested.
