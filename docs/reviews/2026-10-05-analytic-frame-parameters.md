# Analytic ROWS frame parameter connection

## Completion unit and baseline

Branch: `fix/frontend-analytic-frame-parameters`, based directly on main
`40340e5be89d53f3e862b3580d1fa3fcc9129a12`. This is independent of the
unmerged analytic-order and grouped-offset branches. There is no new execution
owner, checker rule, SDK parameter system or wire format.

The common analytic contract already admits literal or whole Parameter numeric
boundaries. The query parser read only a positive integer at this position:

```sql
SELECT id,
  FIRST_VALUE(amount) OVER (
    ORDER BY id ROWS BETWEEN @before PRECEDING AND @after FOLLOWING
  ) AS first,
  LAST_VALUE(amount) OVER (
    ORDER BY id ROWS BETWEEN @before PRECEDING AND @after FOLLOWING
  ) AS last
FROM records WHERE id > 0 ORDER BY id
```

The parser now retains both the parameter name and authored direction. Lowering
emits the existing `{"preceding":{"$param":"before"}}` and
`{"following":{"$param":"after"}}` boundaries. Context declarations enter the
ordinary Program; supplied values remain separate and are checked by the common
owner. Window comparison includes parameter names and directions.

The [GoogleSQL window reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#defining_the_window_frame_clause)
permits a constant nonnegative integer or parameter. This connection retains
the current common contract's **positive** distance restriction. Zero numeric
frame boundaries remain an explicit common-contract gap; no GoogleSQL-wide
compatibility claim is made. RANGE, GROUPS and arbitrary boundary expressions
are not added. Parameter grouping is not added in this unit.

## Independent expectations and identities

The complete [machine control](fixtures/analytic-frame-parameter.expected.program.json)
and [rows and ordered column contracts](fixtures/analytic-frame-parameter.expected.json)
were authored independently of compiler/runtime output. Remaining interval
expectations are literal fixtures in [the public corpus](../../scripts/fixtures/analytic-frame-parameter-source-input.mjs). Source input is deliberately
unordered, includes a NULL amount and an excluded row, and changes frame widths
between SQL and Pipe. Following-only and preceding-only frames include empty
intervals. The literal control and typed empty input remain separate checks.

The MoonBit expected Program compares the complete SQL/Pipe lowering, including
declarations, boundary direction, fields and final sort. Before the fix, this
two-test selection passed its independent JSON/checker control and failed the
source path at parsing (`run-l7r7mk`, 1/2).

The query-rule document changes the Grammar Manifest from
`sha256:88b3e10e85fa88630900251773eb7b2fe5eb00e0714f3668843145fd82e68a8c`
to `sha256:cb47f1587dd7cb896f57d56d2aab4eacca6cd6fb673ab8f258b777947b142f14`.
The independent fixed Values Run changes from
`sha256:51ecc5fb9c556efbca40505459a5432303d0bc368879a6859bda4098d38b9166`
to `sha256:8a5db028aab616c7d31ba9bce6a4e1f6249dc434fad5f3720290475a04097e85`.
The previous vector is retained. New expectations use the independent canonical
preimage oracle, not the product issuer's observed CID. Program/body and common
type/law contracts are unchanged; the contract baseline remains 0.1.

Workers fixtures were regenerated before Node fixtures using the pinned
toolchain. Their mechanical diff incorporates existing main fixture-helper
changes (preparation work, Subgraph variant, optional Program text). No Graph
behavior is reimplemented by this unit. Both read-only freshness checks passed.

## Executed verification

Use the pinned toolchain/Node environment. Each MoonBit selection used
`node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js`:

| Selection | Result | Local evidence under `_build/local-checks/attempts` |
|---|---|---|
| `src/query_program/analytic_frame_parameter_test.mbt` | 3/3, including exact common reversed-frame cause | `run-gpD1Xk` |
| `src/query_syntax/analytic_frame_parameter_test.mbt` | 2/2 | `run-wLBfME` |
| Both initial frame files after formatting | 4/4; precedes the added cause regression | `run-h9cMom` |
| `src/query_program/compile_test.mbt -f '*OVER*'` | 3/3 | `run-mYbL5u` |
| `src/run_publication_host/client_values_run_materials_wbtest.mbt` | 1/1 | `run-lqvv7p` |
| Node manifest/profile/independent Run vector files, bounded 120s | 15/15 | `run-Hoeib5` |

`moon info src/query_syntax`, formatter, three changed-script syntax checks,
compilation-manifest freshness, Workers/Node fixture freshness and
`git diff --check` passed. No full Core, all-target, proof or performance run
was added.

The normal producer command was
`node scripts/test-packed-public-query.mjs --analytic-frame-parameter-only --keep-artifacts`,
under the shared heavy lock and a 720-second budget. Its clean source is
`6b0cecc411951bd5ca797b9e9a6cac23c0a51743`; evidence is the sibling scratch
invocation `public-query-evidence-p4sutE` (`run-QZNXSD`). It performed normal
prepack, outside-checkout installation, package-boundary and README checks.
The **complete frame corpus failed** at its first reversed-bound refusal after
all 7 Local successes. HTTPS was not reached by this original invocation.

The same retained packages then ran a separate, filtered consumer diagnostic
(`run-c7usjU`), without modifying package files or the original consumer:

- 7 normal cases and 10 other typed preparation refusals passed on both Embedded
  Local and authenticated HTTPS. Named rows, stream completion, ordered complete
  types/nullability and hidden-column absence use the ordinary public harness.
- Source acquisition occurs once per successful Run. Result reread, attach and
  identical-request resend do not add acquisition or acceptance. Preparation
  refusals preserve zero Run acceptance/provider I/O and request lookup absence.
- Two reversed-bound text cases and two independently authored JSON controls
  reproduce the classification defect on both transports, with zero acceptance
  and provider I/O. This is **defect-reproduction evidence**, not successful typed
  refusal acceptance. The filtered success does not supersede the failed full
  invocation or prove a pristine later-HEAD packed campaign.

The tracked standard corpus still contains both failing typed-refusal cases.
They have not been deleted, reclassified as successes or excluded from normal CI.
Changes after the packed source are the cause regression and evidence/fixture
documents; no runtime implementation or normative pin changes after packing.

| Normally packed package | SHA-256 |
|---|---|
| client-wire | `9dddd809931f810598bf6669ffd211b716c40bd34b9f169073b90d11cc014595` |
| sdk | `440cc4585c66840867f645708c6654435e7f111dc119f91f3bd4ccf117a11207` |
| run-host-core | `4afd5a452b51ec024fe701f58eb5ecda964013706f721433036d958b0bc3654f` |
| local-node | `527556ade5875751585f620d6cd14316c8c8dcf2402c1912fd24585445c40982` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The installed test Host declares the existing 10,000-byte analytic ceilings and
10,000 frame memberships. Those values and the 512 MiB execution budget are
unchanged. Logs, tarballs, diagnostic consumers and reproduction Stores remain
available; generated runtime bundles are not committed.

## Common diagnostic boundary: handoff, not a Frontend workaround

These valid syntactic forms must reject their reversed bound intervals:

```sql
SELECT FIRST_VALUE(amount) OVER (
  ORDER BY id ROWS BETWEEN @before FOLLOWING AND @after FOLLOWING
) AS first FROM records
-- before=2, after=1
```

The preceding counterpart has `before=1, after=2`. Independent machine inputs:
[following](fixtures/analytic-frame-parameter.reversed-following.program.json),
[preceding](fixtures/analytic-frame-parameter.reversed-preceding.program.json).
Send them as `format: 'json'`, with the respective ordinary `parameters`; do not
add external declarations to a Program already declaring them.

The B regression confirms that the ordinary checker rejects with exact cause
`Closure(Operations(Frames(InvalidFrame(_))))`. Both cases currently classify as
`UnclassifiedFailure`. `pipeline_check_context/operation_frames.mbt::check_program_operation_frames`
already checks the relative distances correctly. The missing category is in
`program_check/diagnostic_category.mbt::closure_diagnostic_category`: it handles
Frames budget exhaustion but not `Frames(InvalidFrame(_))`. Public SDK results
are `SubmissionUnknown`, caused by `ClientHostFailure`, for both text and JSON.
No incorrect successful Result or actual acceptance was observed.

For the common diagnostic owner (E, with common checker ownership as needed),
the minimal correction is to classify the known authored invalid-frame cause
as invalid input while preserving unknown/foreign-owner and configuration/limit
distinctions. Reuse existing diagnostic/wire owners. This report does not claim
that a teammate message was delivered or an owner fix was implemented.

The exact retained diagnostics are `frame-supported-diagnostic.mjs` and
`frame-known-refusal-diagnostic.mjs` in the producer's `artifacts` directory,
run under the 120-second shared guard (`run-c7usjU`). The latter intentionally
checks the observed wrong code as a reproduction; its success is not the desired
public API contract. A correction must pass the unchanged **complete** standard
source corpus on Local/HTTPS. Keep this PR Draft until that boundary and required
exact-HEAD verification are closed. CI, Wasm/native and all broader Frontend
coverage remain separate and unverified by these selected checks.
