# Packed INFER checkpoint and remaining source connection

This is integration evidence, not completion of INFER KEEP/AS or a merge GO.
No common owner, provider executor, capture format or public API was changed.

## Fixed inputs

- Main baseline: `50fcc1ccd7e1cfb4ac379687f95a19043fdc113f`.
- Adopted A source: `08e87475c4cabbd52927b91ee89b6792d5fcf635`, with the
  public handoff document at `ca0ea5d6f72d7aff824b4f6ac46d958e49abbc45`.
  This was an initial development checkpoint, not a merge-ready handoff.
- B package build: `63576ac1efab72dab57e0a64abc694033c93319d` on
  `integration/frontend-infer-public-acceptance`.
- Corrected acceptance assertions:
  `d490bad63de57bc52a09c3cf86d0ccf7a43c1d8a` (description member names, a proved DISTINCT key and separate
  stores). Preparation-only diagnostic: `d1a111fea8577643b4c08e19623713f87301a724`.
  The later commits change fixtures/scripts only. They reuse the same installed
  package bytes; they are not another product build.

The earlier A CI [36980415257](https://github.com/actql/actql/actions/runs/36980415257)
was cancelled. It is not successful fixed-SHA CI evidence for this integration.
No newer uncommitted or unoffered A work was adopted.

## Independent expectations and actual result

The authored [checkpoint fixture](../../spec/frontend/fixtures/infer-keep/checkpoint-acceptance.json)
contains the ModelTask, three inputs and expected rows. The test provider
returns one closed object through the existing physical-preflight/response
API. It does not call a paid model, return a Client Result, substitute a checker
or manufacture a capture.

| Input | Packed embedded Local | Packed HTTPS |
|---|---|---|
| JSON Values → assert unique id → INFER → flat Result | Passed | Passed |
| Same JSON plus ordinary object derive/select for AS | Host 500 / SubmissionUnknown | Host 500 / SubmissionUnknown |
| Source SELECT DISTINCT → INFER AS | Host 500 / SubmissionUnknown | Host 500 / SubmissionUnknown |

The successful row is independently authored:

```json
[{"id":"a","outcome":"ok","value":{"reason":null,"risk":"high"}}]
```

Both successful transports checked Named Result rows and declaration-ordered
`Result.describe().columns` with the full value contract, including nullable
`reason` and nullable outcome `value`. The exact common-owner slot holding
identity was independently calculated and its saved private record checked.
Each mode accepted one Run and invoked the physical model once. Resubmitting
the same request and rereading its Result retained the same Run and did not
invoke the model again. This is not a fresh-process replay test.

Both failing paths left the accepted Run count and physical model call count
unchanged. This does not convert `SubmissionUnknown` into a confirmed public
rejection: the Client received Host 500, and normal uncertainty semantics remain.
The complete selected acceptance still exits nonzero; failed AS paths are not
recorded as passed or permanent language restrictions.

The first run stopped its JSON control on an incorrectly authored description
member (`type` instead of the registered `contract`). It remains failed evidence.
The corrected assertion reused those exact package bytes in fresh Stores.
An earlier source without DISTINCT had no established candidate-key evidence
and was rejected by checking; the selected source below supplies a legitimate
two-column DISTINCT key instead of inventing an ITEM KEY proof.

## Common-owner boundary requiring connection

The preparation probe uses the same packaged checker and Frontend. All three
selected inputs check successfully. Their terminal-INFER selectors are:

| Input | `clientProgramTerminalInferStep` |
|---|---|
| JSON control | `2` |
| JSON with AS projection | absent |
| Source with AS projection | absent |

The source is:

```aql
SELECT DISTINCT 'a' AS id, 'hello' AS text
|> INFER `model-task:risk-score.v1`
   ITEM KEY (id, text) INPUT (text = text) AS assessment
```

Its independently expected result has one `assessment` object with
`input_key: {id: "a", text: "hello"}`, `outcome: "ok"` and the same model value.
The projected JSON control uses the established single-column key and an
ordinary object expression after INFER, independently of the Frontend.

The current common connection is limited by
`src/run_publication_host/client_infer_prefix.mbt::prepared_client_terminal_infer_step`
and `client_infer_prefix_owner`: the graph's Result task must target the INFER
step, have one task and no acquired input. `adapters/host-node/embedded-local.mjs`
selects the installed model owner only when that selector is present. An AS
derive/select tail therefore enters ordinary compilation, which rejects INFER,
and reaches the generic Host failure response.

A must connect the existing admitted model acquisition/capture owner to an
ordinary post-INFER projection and Result Plan. Preserve the checked input and
output-key/capture evidence; do not select by JSON step ordinal, reexecute
INFER for a tail or ask B to remove the AS object. Until connected, unsupported
preparation should have a definite typed refusal before durable admission,
rather than an uncategorized Host 500. Shared Host files remain with their
existing owners. B has not edited those files.

After a formally offered fixed SHA supplies this connection, B reruns these
same source expectations before acquired input, KEEP, non-success typed NULL,
nested nullable properties and fresh-process replay. Those broader cases remain
prepared in [the full matrix](../../spec/frontend/fixtures/infer-keep/packed-acceptance.json)
and are **not run** by the one-row checkpoint.

## Package correspondence and reproduction

| Package at `63576ac1e` | Tarball SHA-256 |
|---|---|
| client-wire | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| sdk | `90e09482027f878bc8e755825afa6090c8c5c10efd8ea428cc010992c20cfe97` |
| run-host-core | `90af32ce196655b4f48ff59c9c91e19cf48f7234e9659734799fe69a53fe7c74` |
| local-node | `a746c103d9c0db43da04b7f20dfbc9ec2913493c82983e1567bb24d623ee873b` |
| node | `5ee3b433edde987b6007f337aafe71af71c565135a16cae3de1debdebc4f1d67` |

Use the pinned toolchain for prepack. The external application has only installed
packages on its runtime path and no MoonBit toolchain:

```sh
node scripts/test-packed-infer-input.mjs \
  --host-setup scripts/fixtures/installed-infer-checkpoint-host.mjs \
  --owner-sha 08e87475c4cabbd52927b91ee89b6792d5fcf635 \
  --checkpoint-only --keep-artifacts
```

Expect nonzero exit while the two AS paths remain unconnected. Run
`scripts/fixtures/packed-infer-preparation-probe.mjs` after copying it into that
external installation to inspect the checked selector and diagnostic Programs.
Those generated Programs are failure evidence, not test oracles.

Local editing verification was restricted to the two touched Node assertion
files (13/13), script syntax and diff checks. Product prepack was done once;
the assertion correction and diagnostic reused it. Full Core/native suites
were not repeated. Cancel/abort, Model delegation, failures before accepted
completion and the broader matrix are not proved by this checkpoint.
