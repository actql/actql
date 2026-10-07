# Resumed Captured Run issuance

## Completion unit

This closes aggregate capture issuance in the JS retained publication path,
not all Local execution or every publication validator. The existing context,
canonical JSON, sealing and snapshot owners are reused. No new scheduler,
capture contract, fallback, Store ledger or Run state machine is introduced.

The implementation source before main integration is
`221f288a0ac395835baa64ec310ec81a3657e415`. The normally adopted main is
`c54e157b5caa1ad981eb9393f64fd0815fb5a434`, including merged #921.
The integrated source is `d1d9358fd858762aed8e74fe4e5905ea47b8ee0b`.
Capture owners, generated bridge inputs and the seven selected Node cases
have identical content across that integration. Main's semantic Result
Artifact binding in `installed-row-effect.mjs` is preserved alongside signal
forwarding; it is not replaced by a physical holding identity.

## Production connection and custody

`CapturedRunIssuancePreparation` polls context construction, canonical
envelope emission, publication sealing and final computation evidence
checking. Only the checked final contract can transfer, once. Cancellation
retires the current child, writer and private references; it has no authority
to release prepared Store payloads or dispatch Compute again.

`ComputationEvidenceCheck` recomputes the embedded context identity through
the existing canonical hashing writer. It finds the exact single Result
Definition for each Artifact and checks fields, row shape, actual row count
and logical Relation CID through `CapturedResultSnapshotPreparation`.
Already admitted immutable rows enter its existing field/sort/row/hash
phases without another whole-array copy. Neither a matching CID alone nor
an unverified caller-created snapshot substitutes for these checks.

The source bodies and canonical preimages are unchanged. Explicit blocking
MoonBit callers drain the same owner. The JS publication control instead
awaits its continuation, yields between polls and checks the actual abort
signal before starting, between polls and before final transfer. Both
Effect-free publication and Effectful computation capture await that control;
installed Effect callers forward the signal. Existing export/publication
owners retain cleanup custody when capture fails or is cancelled.

Node and RelA bridges and public interfaces are generated from the common
template and source. Compiled runtime output remains ignored.

## Independent acceptance

The common package checks identity and total control transitions with
quantum 1, 7 and 64, bounded finite polling, independent Result value/field
literals, one-time transfer and cancellation after real progress at context,
envelope, seal, final context hash, row checks and ready-to-transfer boundaries.
Existing reference, inventory and mutation regressions still execute. The
private context/sealing fixtures retain independently authored exact and
one-short byte/node/depth/control bounds; they are not a measured universal
aggregate work or stop-latency bound.

The actual Host fixture uses one normal Values/filter/select Program with
two downstream consumer Stages, real retained and publication Stores and
three required Named Results: `published`, `consumed_a`, `consumed_b`.
All names must exist. Each committed Result is read and compared in full
to independently authored descending rows containing long composed and
decomposed Unicode, CRLF, supplementary Unicode and explicit NULL.

Separate cases cancel inside the final context hash and Result-row check,
using a read-only common phase observation rather than a fixed sleep. All
three Compute tasks have physically completed before this cancellation.
The exact abort cause is preserved; no committed index is published. The
private preparation closes and releases its slots, existing publication
cleanup returns retained/publication reservations, and the Compute dispatch
count remains three across cleanup. Blocking JS issuance is prohibited by
the test's proxy. This is capture cancellation, not evidence of interrupting
an already completed Compute task.

## Executed checks and provenance

Checks used the pinned toolchain and `scripts/local-checks.mjs`; only the
affected package and consuming Node boundaries were selected.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 src/run_publication

node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node \
  src/connectors/duckdb/conformance

node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern '^(retained Captured Run issuance yields through final evidence checking:|portable control validates Receipt and Captured Run references|complete publication reclaims prepared payloads after a later export fails|complete publication composes every unresolved cleanup owner)' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs \
  adapters/host-common/publication-contract-control.test.mjs
```

At the pre-integration implementation source:

- Common JS: **247/247**, `run-C73rgq` / `focused-test-vCxcDv`.
- The two consumed runtime roots build: **38 tasks**, `run-4buJ2U`.
- Actual Host and publication/cleanup callers: **7/7**, `run-b7dntB` /
  `focused-test-OtC9YA`. Three are real Store capture cases; four are the
  selected publication controls/callers, including one nested cleanup case.
- The Node composition generator, selected `moon info`, changed-file
  formatting, Node syntax and `git diff --check` pass.

Receipts are retained under `_build/local-checks/attempts/` and
`_build/focused-evidence/`. The earlier `run-Gkx58a` syntax failure and
`run-nQmP8j` adapter failure are retained as failures, not acceptance. The
adapter failure exposed treating a non-raising opaque constructor as a raised
result; the real boundary rerun uses its correct declared representation.

At integrated source `d1d9358fd858762aed8e74fe4e5905ea47b8ee0b`:

- Both consumed runtime roots rebuild from the integrated source: **4 tasks**,
  `run-lVr3lq`. Incremental artifacts are retained; this is not an unchanged
  old distribution or a packed installation.
- The three capture cases and two existing snapshot cases pass **5/5**,
  `run-NU5ppP` / `focused-test-8Ui2jD`, selected with
  `--test-name-pattern '^(retained Captured Run issuance yields through final evidence checking:|retained Result snapshot admission yields inside long Text:)'`
  in the same retained Host file and 180-second wrapper.
- Node and RelA composition freshness, both fixture generators, both installed
  Effect adapter syntax checks and `git diff --check` pass. All production
  capture callers await issuance; installed callers forward their signals.

The common JS and other four Node caller results above retain their
pre-integration provenance; byte-identical tested sources are not reported
as newly executed whole suites. The subsequent record commit changes only
this document and the Local gaps record, not product or fixture inputs.

## Remaining boundaries and unverified coverage

Metadata preflight, dependency/authoring/Model checks, schema unique-array
comparison and scalar predicates retain their existing synchronous leaves.
Field-name normalization and contiguous-string allocation latency are not
made universally bounded by this change. The later publication chain/commit
validation and restored Store admission still have explicit synchronous
entrypoints; this record does not claim that those calls become interruptible
merely because issuance now polls its final checks.

The next publication unit is to connect those later checks to the existing
continuation or exact applicable owner-issued evidence without weakening
binding, admission or recovery checks. Store durability and Run cancellation
terminal decisions stay with their existing owners.

Full Core, Wasm/Native execution, pristine packed/HTTPS acceptance and hosted
CI have not been run for this unit. Checkout runtime evidence is not a
pristine distribution campaign. No CI rerun, protection change or merge is
performed. Any later integrated-source checks retain their own SHA and
receipts rather than relabeling the preceding results.
