# JOIN property paths: integrated public acceptance

## 2026-10-05 integration

The final integration retains the original nullable-property JOIN Frontend
repair, duplicate rows, alias and qualified-input ordering, LEFT JOIN, typed
empty output, zero Source reads and the explicit JOIN output bound of 12.
The source fixture and both reproduction inputs are unchanged.

The common repair is implemented once in PR #396. A Relation-only source-free
DAG with a shared Values producer and a binary consumer now reaches the existing
selected-operation and exact managed-input checks. The existing graph expansion
retains one producer, both real operation ports, the original checked owners,
Result identities and cleanup lifecycle. It does not duplicate source evaluation
or change the 536,870,912-byte execution ceiling. The former ten-step chain's
601,096,960-byte reservation accurately described its retained child lifetimes;
this repair changes the physical plan rather than that capacity arithmetic.

This branch adopts the completed #381 integration, which includes #396, through
normal Git history. All three corpus registrations remain present and every
final PR base remains `actql/actql:main`. Merge order is #396, then #381, then
#391; no PR is merged into a dependency branch.

The final PR body records exact source SHA, commands, raw receipts, tarball
digests and unverified coverage. The report below retains historical findings.

## Historical report


## Scope and baseline

This branch starts at `3bcada80e678a8d7919d1129a6a1c282c543659c`, the
published HEAD of [#374](https://github.com/actql/actql/pull/374). Its underlying
main is `3c443c5bf3483170aa941feac767650a76b532f2`. The child depends on
#374's receiver-identity check for ORDER expression reuse; it does not copy
that fix. Integrate the parent before retargeting this PR to main.

Main `7e32faa5a455dc4beafa02a8cd06313e83772d50` (including #388) was normally
merged at `79ccf879a6bce95d304e3a4165d8dd62e1118606`, without conflicts.
This keeps main's Draft preparation policy and does not replace the unmerged
#374 dependency. The published child remains Draft while execution is incomplete.

The adopted [query scope](../spec/query-text.md#scope-and-lowering) and
[nullable property contract](../spec/query-text.md#infer-keep-source-projection)
already allow nested fields after resolving a visible column or range prefix.
SELECT siblings and WHERE use the input snapshot. Final ORDER uses evaluated
output aliases first and retains qualified inputs. The common checker owns
object types, missing members and nullable receiver propagation.

The two-input JOIN boundary had two gaps: it required every reference to be a
complete scalar column, and then used scalar-only expression lowering. Existing
JOIN-chain post-projection already uses the shared Pipe property path and is
not rewritten. Direct equality keys in ON retain their existing support profile;
property-derived ON keys remain a separate unconnected boundary, not a claim
that they are invalid GoogleSQL.

## Independent counterexample

```sql
SELECT l.payload.score
FROM objects AS l JOIN others AS r ON l.id = r.id;
```

The [complete handwritten three-stage Program](../../src/query_program/join_property_paths_test.mbt)
joins direct ID keys, carries the nullable object receiver and uses the existing
property expression before publishing only `score`. Ordinary checker acceptance
of that Program passed, while both SQL and equivalent Pipe lowering failed:
**1/3** baseline (`run-KXn66f`, `focused-test-Pnyasr`). The oracle was authored
before the product repair and is not obtained from compiler output.

The repair resolves the longest column prefix, retaining ambiguity failures,
and carries that receiver through the JOIN. The remainder lowers through
`append_with_properties`. Direct column projection remains direct. SELECT
expressions are computed once, ORDER aliases refer to those slots, and private
receiver/sort fields are removed before the public Result. ORDER's required
inputs use the same prefix precedence, so an alias receiver does not accidentally
retain or revive an input. The Stage Result pre-JOIN filter uses that same
existing expression entry. CTE capture, predicate sharing, assert, Effect,
checker, physical strategy, provider, Host and SDK are not modified.

## Acceptance obligations

The [public fixture](../../scripts/fixtures/join-property-source-input.mjs)
contains a complete independent JSON control and authored SQL/Pipe/DATA inputs.
Two right rows share ID 2, deliberately retaining JOIN multiplicity. Independent
expectations include nullable scores, implicit/quoted property names, WHERE's
input snapshot, selected-property receiver rebinding, qualified receiver control,
DISTINCT on selected expressions, LEFT JOIN's absent right object, typed empty
output and a pre-JOIN Pipe filter. Authored JOIN bounds remain 12.

With `payload.score AS original_score, r.other AS payload`, ORDER by the output
receiver must yield IDs **1,3,2,2**. The qualified input control instead yields
**2,2,1,3**. The original scores and object values are checked alongside the
order; a syntactic match cannot substitute SELECT's input receiver. The WHERE
case retains only input score 20 even though the projected receiver has score 5.

Five preparation refusals cover an ambiguous receiver, an unknown receiver,
a missing member, a scalar receiver and an input removed by DISTINCT. They must
retain the existing typed public input errors, zero durable Run admission and
zero provider I/O. Missing member/scalar errors are delegated to the common
checker rather than fabricated in the Frontend.

These cases are registered in the normal packed corpus. The focused command is
`node scripts/test-packed-public-query.mjs --join-property-only`; its selection
excludes unrelated native, graph, inference, restart and planner campaigns.
The existing public harness checks Named rows, complete ordered Result.describe
contracts (also on empty rows), internal-column exclusion, stream completion,
same-Run resend/lookup/attach and no additional acquisition. No lowered Program
is patched, no row is sampled to infer a type and no test-only Host route is used.

## Executed evidence

After repair, the new JS selection passed **9/9** (`run-XajraL`,
`focused-test-i71Zfs`). Existing/new JOIN callers passed **50/50**
(`run-B7JC5z`, `focused-test-3A0bBh`), including the added output-receiver
versus ambiguous-input assertion; these counts overlap. A CTE test first
used a bare GeneratedValues right input in a path requiring Stage Results;
both sides now explicitly bind CTEs, without changing CTE implementation or
expanding its current support claim. Two temporary test/compiler errors were
corrected before submission and are not execution passes.

The first clean packed source `01cc6a4bababea17764293b973ffa63383ad9c8f`
(`public-query-evidence-7sRChy`) passed the independent JSON and SQL/Pipe
property projection controls on Local, then stopped at WHERE's input-snapshot
case. The preserved bridge cause is `Graph(TaskLimit)`, not a checker error or
alias misbinding. The standard common owner permits 32 tasks. A private bridge
probe using that build confirmed this cause for six remaining preparation
shapes; it is diagnostic evidence, not public execution acceptance.

The authored text now declares one explicit `DATA seed = SELECT 1 AS unit`
producer shared by the seven row projections. Rows, nullable values, duplicate
ID 2, SELECT/WHERE/ORDER expressions, full column expectations and JOIN bound 12
are unchanged. This keeps the corpus within the existing task admission budget
and also exercises shared producer use. No task ceiling, strategy or Program
after lowering is changed. The same bridge then prepared all nine text cases.
Clean normal packs at `d150b9432f6d1628686c1ffe8412bfe35e1b5970`
(`public-query-evidence-Q46Dqg`) and integrated source
`79ccf879a6bce95d304e3a4165d8dd62e1118606`
(`public-query-evidence-g15LM6`) both passed the independent JSON control, then
admitted the first SQL source and ended with `ACTQL_E_UNPUBLISHED_RUN`.
The remaining eight text positives, all five refusals and HTTP were not reached
in either attempt. This is not successful public acceptance. The earlier failed
installations were removed after preserving command logs and identity/digests;
the integrated installation is retained for this failure's diagnosis.

No full Core, all-target, proof or performance suite was added after main
integration. Subsequent focused diagnostics reuse the retained five packages,
with this SHA's normal prepack digests:

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `65b6408c2bb93597b8c92fc424b010b5e1d3e8b75ba414ad006bd30d57999a86` |
| local-node | `bdf8322d72da299bb3eddfceac71f5ef9a0f9ae8f8d51424f52d3dfa33d34fd8` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Common execution boundary and reproduction

Diagnostic-only logging in private installed copies of `runtime-result.mjs`
and `runtime-core.mjs` identified `NodeHostFailure.Dispatch` containing
`ComputeHostIssue.Dispatch(InstalledDispatchIssue.NoStrategy)`. The failure is at
`strategyHostNext` → `physical_host.prepare_next_compute_task` →
`prepare_next_installed_task`, before the first task executes. The observed
cursor is task **0**, with **0** managed inputs and an empty producer list.
Submitting the first source's generated Program unchanged through JSON, with
the same parameter values and Host profile, reproduced that same failure.
The logging copies were restored afterwards; no repository Host, checker,
strategy, runtime or package manifest was changed. These observations are
diagnostics, not pristine Local/HTTP acceptance or proof that every strategy
candidate is unavailable. Candidate derivation/installation is still unresolved.

The [minimal authored source and independent single-row expectation](../../scripts/fixtures/join-property-shared-seed.repro.mjs)
reduce this to one shared producer:

```sql
DATA seed = SELECT 1 AS id;
DATA objects = SELECT 1 AS id, @a AS payload FROM seed;
DATA others = SELECT 1 AS id, @b AS other FROM seed;
SELECT l.payload.score
FROM objects AS l JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 1
```

With `a = {score: 10}`, `b = {score: 20}` and the fixture's typed declarations,
the independently required answer is `[{score: 10}]`, one nullable numeric
column. This minimal source also prepares and is admitted, then fails unpublished
in the retained, restored installation. The control declaring each input with
its own FROM-less SELECT instead succeeds and returns exactly that row.
This control is diagnostic isolation; it does not replace the shared-producer
fixture or satisfy its acceptance obligation.

The [saved ten-step generated Program](../../scripts/fixtures/join-property-shared-seed.repro.program.json)
is a reproduction, **not** a lowering oracle, saved from the ordinarily prepared
source. Minimal JSON preparation/execution was not executed at that earlier SHA;
the integrated-source diagnosis below now executes this unchanged document. The larger
first source's generated JSON reproduction above was executed. Use the fixture's
`parameters` for JSON; its declarations are already in the Program and must not
be added externally. For source, supply both `parameterDeclarations` and
`parameters` to existing `client.aql`. Use the same standard installation/profile
for both, wait, then read `execution.result('answer').rows()` and `describe()`
only after success. The existing focused clean-pack reproduction command remains
`node scripts/test-packed-public-query.mjs --join-property-only --keep-artifacts`;
do not rebuild a separate execution owner or patch the generated Program.

The common Compute/strategy owner can trace the task-0 revision and installed
candidates from these source/JSON reproductions. B retains the receiver lowering,
independent oracles and unchanged full public expectations. After the common
repair, resume all ten positives and five refusals on both Local and HTTP;
successful single-row/control probes are not substitutes for that completion.

Submitted-HEAD CI is unverified. Draft's `awaiting ready_for_review` is intentional
and is not a rerun request. This is implementation, focused checker and partial
public evidence, not a claim of complete acceptance.
No grammar, wire, schema, saved-data or contract-version changes. Corrected
sources produce their normal Program identities. Full Core, all targets, native,
proof, performance and a Google service differential run are not local checks
for this bounded unit. No merge is performed.

## Main integration and current capacity handoff (2026-10-05)

Main `82d3e85e0150157ab2a3beedcf9e1e476f565b58` was normally merged at
`d6879fc4a0064a6d478d3f40a900f5b16513a036`. This includes #403's retained
Relation branches and #399's public retained-output connection. The two
conflicts were packed fixture routing/selection registrations. Both sides'
cases and focused flags were retained. No common implementation or workflow
was edited. The unmerged #374 dependency and stacked PR base are retained.

At this clean integrated source, the bounded JS command
`node scripts/local-checks.mjs test moon -- --target js src/query_program/join_property_paths_test.mbt`
passed **9/9** (`run-IqSBJK`, `focused-test-8vAp7h`). Both conflicted
JavaScript files passed syntax checks, and `git diff --check` passed.
Full Core/all-target checks were not added.

The ordinary external pack command was
`node scripts/test-packed-public-query.mjs --join-property-only --keep-artifacts`,
under the existing serial heavy-check guard (`run-jb116k`). Receipt
`public-query-evidence-WuPTbp/summary.json` records the clean source above,
normal prepack, all tarball digests, complete child logs and no evidence errors.
The independent JSON control passed Named Result rows and ordered type contracts
on Local. The first SQL case was admitted and failed unpublished. The other
eight text positives, five refusals and all JOIN HTTP cases were not reached.
README Local/HTTPS success is separate. This remains an incomplete campaign.

| Package | Normal prepack SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `1b476f0905929248c53c9d36e98cafeefbd7a278f7ecd0a9aaa3500a8312fc14` |
| local-node | `81ac587c4104ef4ca36f5741e97868a00c7f9226941f4f9f54c31d16d921818b` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Two small follow-up diagnostics reused this retained private installation.
Temporary logging in its `runtime-result.mjs` and `strategy-bundle.mjs` was
restored byte-for-byte afterwards. No tarball, repository runtime, Program,
parameter, predicate, JOIN bound or package manifest was changed. These are
diagnostic overlays, **not** pristine acceptance passes. Captured command
records are `join-diagnostic-command-d1Su5v` and
`join-diagnostic-command-vNal1g` below that receipt; guard attempts are
`run-uG0dL5` and `run-17ou7P`.

Both the minimum authored shared-seed source above and the saved ten-step
Program submitted unchanged through JSON now reach this common start boundary:

```text
strategyModule_local_ManagedStart
NodeHostFailure.LocalManagedStart(
  LocalDispatchIssue.Execution(RunIssue.Physical(LedgerIssue.ExecutionLimit)))
```

The minified raised representation was mapped against the same build's bridge,
`connectors/local/driver/dispatch.mbt`, `physical_strategy/captured_dag.mbt`
and `physical_resources/ledger.mbt`; it was not inferred from the terminal
unpublished error. The selected task is **0**, with no external inputs. For
both source and unchanged JSON the selected managed envelope is:

| Quantity | Bytes |
|---|---|
| Transfer | 0 |
| Retained output | 14,240,000 |
| Scratch | 601,096,960 |
| Execution | 601,096,960 |
| Standard Host execution limit (unchanged) | 536,870,912 |

All eight reported ledger usage counters were zero before this start. Zero
prior reservation does not imply this new reservation fits. The immediate
failure is in `start_local_managed_dispatch` calling
`start_captured_managed_execution`, after managed strategy selection. Thus the
old minimal task-0 `NoStrategy` finding is superseded at this integrated source;
it must not be reported as an unresolved candidate failure here. This does not
prove every full fixture's strategy or capacity is now correct.

The independently seeded control still succeeds through Named Result rows
`[{"score":10}]` and the complete nullable numeric `score` column contract.
Its separate tasks advertise execution envelopes between 46,771,200 and
98,462,464 bytes. It is a diagnostic contrast, not a replacement for the shared
producer case. No accepted scope or expected row/order/schema was weakened.

The next common-owner investigation is the fused shared-branch provider's
capacity derivation and lifetime model, with the exact source, ten-step JSON,
parameters and independent result already linked above. Determine whether the
bound is necessary or overcounts before proposing any common change. B does
not raise 512 MiB, split/duplicate the logical seed to bypass the refusal, reduce
an unsupported coefficient, or implement a private provider. After that boundary
is resolved, resume the original ten positives and five refusals on both
transports. CI for a later evidence-only HEAD remains separate from this clean
packed source; no manual rerun or PR merge is requested.
