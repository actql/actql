# Pipe WHERE / EXTEND / SET private window scope

## Boundary and dependency

This follow-up depends on PR #1177, submitted parent
`e5a838a3c6e555daf04a29fe89dfb6bfc42c3852`. Its shared private-expression
scope adapter is reused, not copied. The previously inspected main baseline was
`040eed2b1a11a3d1f7bae81b68d956d1017fac05`.

Checked input schemas can contain names absent from authored source tokens.
With numeric `id` and a public column named like the parser's private window
reference, these three ordinary Pipe consumers failed with
`Expression(UnknownReference)`:

```aql
FROM records |> AS r
|> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> ORDER BY id

FROM records |> AS r
|> EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> ORDER BY id DESC

FROM records |> AS r
|> SET id = ROW_NUMBER() OVER (ORDER BY id) + 10 |> ORDER BY id DESC
```

The colliding public fields are respectively `aql_pipe_where_window_0`,
`aql_select_window_0` and `aql_pipe_set_window_0`, including uppercase variants.
All three call sites appended private bindings to the visible input lookup,
making the extracted reference ambiguous. They now use the parent's existing
private-expression adapter. User columns remain public; authored references,
window input lookup and captured range receivers retain their original meaning.
No prefix is forbidden as a public name. There is no checker, execution Owner,
grammar, contract or pin change.

## Independent counterexamples and public fixtures

Input rows `(id=2,user=10), (id=1,user=90)` deliberately separate the user value
from the window rank. Expected descending-id results are:

- WHERE: only `(id=1,user=90)`.
- EXTEND: `(id=2,user=10,pos=3), (id=1,user=90,pos=2)`.
- SET: `(id=12,user=10), (id=11,user=90)`.

Complete ordinary JSON Programs independently express the analytic operation,
predicate or assignment, projection and sort. The frontend output is not used
to author those controls and is not patched by the consumer. Typed array
parameters carry the schema-only names through the real public input boundary.
Thirteen new positive cases cover JSON controls, lowercase and uppercase names,
nullable user values, empty input, immutable `r.id` after SET and an authored
user-column OVER key with opposing rank values. Three additional private-slot
references must return `ClientProgramInvalidInput` before Run admission and
Source I/O. The normal and existing narrow window-scalar consumers include all
cases; no new acceptance harness or Local-only path is introduced.

## Focused verification

Evidence paths are relative to this checkout: guard directories under
`_build/local-checks/attempts`, test evidence under `_build/focused-evidence`.

- Before the repair: 0/3, all exact `UnknownReference` failures;
  `run-dmW7T8` / `focused-test-iE7TNW`. This establishes lowering failure,
  not failed public Run execution.
- Expanded final JS selection: 28/28;
  `run-8DRZiG` / `focused-test-JVOwsx`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/pipe_window_private_scope_test.mbt src/query_program/pipe_where_window_test.mbt src/query_program/pipe_extend_window_test.mbt src/query_program/pipe_set_window_test.mbt src/query_program/select_window_private_scope_test.mbt`.
- Node fixture selection: 9/9;
  `run-35PeJ1` / `focused-test-ACT72V`.
  Command: `node scripts/local-checks.mjs test node -- scripts/window-scalar-source-input.test.mjs`.

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used. Changed MoonBit
formatting and `git diff --check` passed. The complete narrow corpus now contains
83 positive, 40 refusal and one deliberate execution-failure case per transport.

## Initial packed control correction

The pristine pack at `fea0a5eac609c9da52d064cb0e3fe4b059ca8baf` passed
the new WHERE/EXTEND controls and sources, then stopped on the SET JSON control.
Its derive map tried to replace existing `id`, which violates the existing
`InputCollision` rule (independently asserted in
`src/relation_typing/typing_test.mbt`, derive-map versus ordered-derive tests).
The control now derives a fresh `assigned_id` and explicitly projects it as
`id`, as the existing SET control does. Source, expected rows, types, order,
ceilings and product code are unchanged. SET source and HTTPS were not reached
in this initial run; it is not evidence that they failed.

Original logs/receipt are retained at
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-R7HKmg`;
guard `run-oSL73e`, command `010` stderr reports
`packed-local-window-scalar-pipe-schema-private-set-json` / invalid input.
The pack remains at `/private/tmp/actql-b-pipe-window-private-fea0a5eac-pack`.

The corrected fixture selection passed 9/9 using the same Node command at
`run-QNbepS` / `focused-test-i8fgo5`.

## Completed pristine packed acceptance

Clean source: `d8179efdef3623a5f18b0fd7ea00ba35ab660413`.
Any later evidence-only commit must not relabel this as submitted-HEAD execution.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-pipe-window-private-d8179efde-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-pipe-window-private-d8179efde-pack node scripts/test-packed-public-query.mjs --window-scalar-only
```

The existing serialized bounded guard ran normal packing, independent digest
verification and the existing public consumer. Local and HTTPS each completed
**83 positive / 40 refusal / one deliberate execution-failure case**, including
all thirteen new positives and three private-slot refusals. Independent expected
rows, full Result.describe types/nullability and column order, stream completion,
repeat reads, attach and same-request replay/no extra admission or acquisition
were retained. The three new refusals returned `ClientProgramInvalidInput`
with zero Run admission and Source I/O. Existing cases were not excluded.

Original receipt/logs:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-ssLoQe`.
Guard: `run-MGEvKr`. All ten commands have exit zero, complete output and zero
verification status. The receipt is passed/complete, source is clean, revision
matches the producer manifest and there are no evidence errors. Independent
SHA256 calculations matched all five manifest and receipt digests. Successful
and failed temporary installations were removed after preserving evidence;
the successful receipt's artifacts path was independently confirmed absent.

| Package | Independent SHA256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `2df8178e6d627d950cfe2dfb289cda1a31a54d5b6625c9031fd127bab438056e` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Payload digests match the first pack because the intervening change only
corrected the independently authored JSON control and recorded evidence.

## Remaining verification

Parent evidence remains evidence for the parent's source revision.
Submitted-HEAD CI, Wasm/native execution, the full Core and complete frontend
campaign have not been run locally. This does not claim that every private
window consumer or every frontend semantic boundary has been audited.
