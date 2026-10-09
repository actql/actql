# Native retained Result and observed Provider Preview

## Implemented connection

`prepare_native_resident_effect_preview` joins the retained consumer's actual
local Result Artifact with checked physical Provider target observations.
The existing request-scope Owner checks the request's Program and parameters;
the caller must supply the original durable Client request, trusted runtime
binding, Source binding and Store authority. Source authorization is not an
Effect approval or mutation grant.

The connection uses existing Owners to issue the private Source Artifact and
local Effect identity, recheck the installed write capability against the
current Catalog, derive the exact target footprint, canonicalize the draft,
author the complete semantic Preview, issue dispatch keys and admit those keys.
It then binds the Preview to current retained inputs and verifies the authored
plan against the exact Native Result export before returning it.

Target rows are reconstructed from the opaque checked request and observation;
supplied row facts cannot replace those Owner-derived facts. Provider data uses
the value-preserving parser and encoder. The finite initial route supports one
update member with required approval. Dispatch correlation limits are explicit
and remain bounded by the existing identity Owner; whole-document limits are
not reused for them.

Repeated preparation does not perform another Provider read, Source acquisition
or Compute execution. Failures retain the existing input and Provider-use
responsibilities. The returned Preview, plan proof and keys are not approval,
waiting commit, physical Store custody or an apply permit.

## Exact local evidence

Verified clean implementation SHA:
`635226381b7f5f8d58b33593779303a8abbe5e2f`.

```sh
ACTQL_TEST_SCRATCH_ROOT=<owned-evidence-directory> \
ACTQL_TEST_DUCKDB_LIBRARY=<compatible-native-library> \
  node scripts/test-native-salesforce-effect-preview.mjs --resident-proposals
```

Run through the existing verification lock and bounded wrapper with pinned
MoonBit and matching Native SQLite, libcurl and OpenSSL libraries. The runner
supplies its own signed test runtime fixture; its placeholder component is not
a distributed production Site binary. `--resident-preview` selects only the
two new physical Provider cases without changing their expected outcomes or
the existing timeout/nonzero-test guard. Normal Native HTTP registration keeps
the complete retained file.

Final evidence: `_build/native-effect-provider-preview-1791572877771/`.
Formatting, affected Native interface generation, Native type checking and
`git diff --check` passed. The retained Native file passed **11/11**, including
the unchanged Source/Transfer/capture cases and the physical Provider cases.
The Native whitebox executable SHA-256 is
`a58587affc6427c83f0f7179d83b1c2355da3224e832e5fd46f9316bf3450074`.
`source.json`, `receipt.json`, `artifact.json` and the scratch physical receipt
preserve the exact source, commands and execution evidence.

The real DuckDB Source, producer and consumer each executed once. The existing
receiving holding and borrow supplied the consumer input. Independent rows and
schema remained `[{"id":3,"record":"001000000000001"}]`, with the checked
non-nullable number and 15-byte-bounded non-nullable string.

The actual HTTPS target had `Count__c: 7`; the proposal had `Count__c: 3`.
The admitted Preview retained those exact before/after values, target guard,
capability and original logical request authority. Its plan proof matched the
actual held Result. Repeating preparation returned identical wire and a valid
proof with no extra physical acquisition. The total physical receipt records
**one Provider read and zero writes**.

The consuming case rejects an empty target batch, another Program's request,
another Run definition and the producer/root Result in place of the consumer
Result. The existing current-authority refusal case and consumed-read refusal
remain enforced. Existing input cleanup/reservation checks passed; these are
Native custody observations, not a Cloud Released transition.

## Preserved failed evidence

- `_build/native-effect-provider-preview-1791572416385/`: exact clean
  `04bbd560fec6a1d18f0f43a8c6475075d6bab0d6` aborted in the new Provider case.
  The MoonBit summary was unavailable; it is not counted as a passing run.
- `native-effect-provider-preview-1791572688496`: diagnostic 1/2; the new
  adapter had omitted the existing Preview draft canonicalizer and received
  `PreviewShape(InvalidWire)`.
- `native-effect-provider-preview-1791572745838`: diagnostic 1/2; reusing the
  whole-Preview limits for dispatch correlations received `InvalidLimits`.
  Separate finite key limits fixed the caller. No Owner check or limit changed.

Earlier error-type compilation diagnostics and the intermediate uncommitted
2/2 result are preserved separately from final clean-source acceptance.

## Remaining end-to-end obligations

This component follows #1185 and the pending Native capture series. Its final
merge destination is main after its parents; formal Cloud adoption must use a
merged source with matching packages and Native binary.

Private Captured Run/Checkpoint persistence with these real target facts,
original Cloud waiting commit, Host restart, current approval, physical Effect
apply and unknown-outcome reconciliation, final publication and formal release
remain unfinished. Store authority/read-decision facts are local installation
fixtures here. A standalone Native caller is not the public Cloud SDK route.

The full Native HTTP runner, full Core/packed campaigns, Hosted CI and Cloud
Preview acceptance were not run. Hosted CI remains stopped. No deployment,
external Provider org or historical #88 custody was changed or closed.
