# Packed INFER source: input prefix handoff

This records an incomplete execution acceptance, not a successful source INFER
release or merge approval. B does not add another inference executor.

## Fixed sources and packages

- Formally selected common owner: `8f906009fd3d64b5873f227bc24ec993938023be` (#178).
- B's isolated merge: `1b24297edffdd1e8dd113c5bfcf6f8a216f33e14`.
- Executed clean B source: `d68ad4194e1067acc931b3147ba79453644c383b`.
- Historical `08e87475…` acceptance is separate. A's subsequently published
  `b396da7d9b19c150d094df5a5ae39badf033586d` has not been adopted for this run.
- The two overlapping Frontend test files were resolved by retaining the
  explicit absent-ModelTask assertion and detailed nested object-field checks.
  These tests passed 11/11 on JS; formatting and diff checks passed.

Normal prepack produced the following SHA-256 digests. No bundled runtime was
edited after installation.

| Package | SHA-256 |
|---|---|
| client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| sdk | `9fd8d7c7019eafcd1401fa1804108644f13875b2197bb3d3e012abbb5428143e` |
| run-host-core | `8772e0039311cd1b18fdb73eb5d0a0ef66d1c6f4bf8e93c6544baf3e28160471` |
| local-node | `103af68bf04cfb1173acadba98ed63165b64c4b925edf5b006abd259e4f3722a` |
| node | `5ee3b433edde987b6007f337aafe71af71c565135a16cae3de1debdebc4f1d67` |

## Minimal source and independent expectation

```aql
SELECT DISTINCT 'ticket-1' AS id
|> EXTEND 'urgent' AS text
|> INFER `model-task:packed-risk.v1`
     ITEM KEY (id) INPUT (text = text) AS assessment
```

Expected `answer`:

```json
[{"assessment":{"input_key":{"id":"ticket-1"},"outcome":"ok","value":{"reason":null,"risk":"high"}}}]
```

The complete independently authored column contract is in
[`infer-source-expectation.mjs`](../../scripts/fixtures/infer-source-expectation.mjs).
It preserves a nonnullable closed assessment, the eight-byte literal key
bound, the common outcome String and nullable closed value with nullable
reason. The deterministic ModelTask registration reuses
[`installed-infer-fixture.mjs`](../../scripts/fixtures/installed-infer-fixture.mjs).
Neither expected rows nor expected types come from compiler/reader output.

## Observed failure and controls

The normal packed source run failed its first Embedded Local execution:
`needs_reconciliation`, `reconcile_run/execution_unknown`, zero physical model
provider calls. It had already reserved the physical Run start. HTTPS reproduced
the same state. Closing that HTTPS Host exposed
`ClientDispatchCleanupPending`, whose primary cause is `MoonBitHostFailure` at
`openNodeInferOperation` while invoking `clientProgramStartScopedInferExecution`;
cleanup reports `ClientDispatchStopUnknown`. No capture or Result was published.
Do not retry this saved uncertain execution as a new model dispatch.

An independent JSON control with Values, key assertion, INFER, object derive
and select succeeded through the same installed HTTPS Host. It returned the
expected assessment row, one provider call and one admitted Run. Reread,
attach and same-request resubmit did not execute again. Its literal key is
declared as an unbounded String, so this diagnostic's actual description is
kept separate from the source fixture's expected bounded key contract.

A preparation/input-only probe narrowed the boundary further:

| Input | Checked | Selected INFER | Suffix prepared | Input prefix started |
|---|---|---|---|---|
| Authored source above | yes | step 6 | yes | no |
| Independent projected JSON control | yes | step 2 | yes | yes; cleanup confirmed |
| JSON control with an extra ordinary pre-INFER derive | yes | step 3 | yes | no |

This probe does not accept Runs or invoke models. Diagnostic generated Programs
are retained as diagnostics, never promoted to golden expectations.

## Required common-owner connection

Source inspection identifies a concrete omitted connection:

1. `client_local_host/client_sequence.mbt::prepare_client_infer_prefix` accepts
   the existing fragment and ordered contract bodies. The common sequence
   preparation requires an admitted fragment contract for SnapshotMap,
   OrderedBindings and other expression-bearing kernels.
2. `client_infer_host/execution.mbt` starts `start_client_infer_input` with
   registry and Values bodies, but does not pass either optional contract body.
3. The installed Host already loads these same admitted bodies. The new
   `clientProgramPrepareInferComputeSuffix` passes them for the suffix; the
   input prefix currently receives neither.

The omission is the source-based explanation for the controlled prefix failure,
not a new numeric/ModelTask semantic proposal. A should thread the existing
contracts through the common start/replay input path, retaining exact checked
owner/step binding, limits and custody. B does not edit this owner or reconstruct
inputs in JavaScript. Unsupported input preparation must be handled at the
correct existing admission/physical-start boundary; do not fabricate a confirmed
stop for a reserved unknown execution or weaken Client uncertainty semantics.

## Reproduction and remaining acceptance

With the pinned repository toolchain and dependencies:

```sh
node scripts/test-packed-infer-source.mjs \
  --owner-sha 8f906009fd3d64b5873f227bc24ec993938023be \
  --keep-artifacts
```

The controller records fixed SHA, tarball digests, stdout/stderr and exit
observations before classifying failure. It uses only installed public Client
and HTTP Host exports for execution. Retain this failed run's Store and journal;
do not remove or resubmit them for diagnosis.

The intended acceptance continues with Local and HTTPS object projection,
Result.describe agreement, exit after committed capture and replay in a new
process with zero provider calls. Capture/replay phases were **not reached** in
this failed source run. KEEP, non-success/NULL, empty input, acquired source and
the full refusal matrix remain incomplete. No repeated full local Core/Client
gate is claimed. A's run 36990550556 at the selected owner SHA ended cancelled;
it is not successful final-SHA CI evidence.
