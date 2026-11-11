# Adding an installed row provider

This is the existing Node Host implementation boundary, not a dynamic plugin
protocol or a promise of a stable external SPI. Applications consume public
packages; provider authors contribute a checked installation manifest and
physical driver. The common semantics stay in MoonBit and existing Host owners.

## Registration and pure declarations

1. Declare Source and/or Effect roles in `src/connectors/<name>/host-bundle.json`.
   Specify the profile versions, registration/revision, adapter module and
   exact check/identity/publish/load exports. A read-only provider needs no
   dummy Effect or Compute contribution.
2. Declare a real pure codec package as `providerBundle` only when needed.
   Declare owned static files as `assets`; no implicit package resolution,
   external aliases or undeclared filesystem dependencies are allowed.
3. Regenerate with `node scripts/connector-node-bundles.mjs --write`. The
   installation table and standard package inventory come from the manifest,
   not common Core provider-name branches.
4. Restore the typed Catalog/views through `client_row_source_host`. Use its
   Mapping factory and `check_environment` permission checks rather than
   constructing evidence or accepting unsupported operations in the driver.

A row-addressable Mapping keeps its required nonnullable scalar identity.
An explicit collection-only Mapping has `primary_identity: null` and a real
typed `collection_identity`, and permits create/selector-none only. Neither
shape changes read key requirements. Unsupported operation declarations are
refused at registration/check, not carried into physical send.

## Ownership and I/O

`createInstalledRowSource` owns the checked acquisition, page charge, capture,
input binding and Source Evidence. Its driver supplies `physicalTarget` and
finite `readPages`, using the provided per-page authorization and scoped
credential resource. It does not create a second acquisition ledger or issue
its own success authority. Observe bytes before projection and do not replace
API errors with empty input or NULL.

`createInstalledRowEffect` owns the checked Preview, Set approval, durable
claim, saved response, Receipt, publication and recovery. Every write kind
supplies pure `prepareRequest` and `requestFacts`, a `writeOperation`, one
physical `send`, response `project`, and a bounded `footprint`. The common
owner compares exact value/selector facts with the Program and Preview before
dispatch. Use the value canonicalizer's data mode for values and keys; reserve
configuration normalization for configuration identity.

For target-addressed writes, provide the required target observation/version
hooks. Custom recovery requires `recoveryEntry`, `recoverRequests` and
`requestCid` together, including create drivers. Existing registration checks
reject incomplete hook sets. Recovery must reconstruct and compare the exact
approved requests; retained data is not authorization. Create-only providers
can use the existing default reconstruction instead of a custom recovery path.

An installed Source profile's `prepareManagedRun` takes the single internal
object `{preparedProgram, requestIdentity, prepareInvocation}` and returns its
same Host-owned Run. Capture the actual method and receiver at installation.
Do not use a positional third argument for a Model selection or issue a new
Connector-owned Node admission. The Host's shared ordinary route is used by
both admission and dispatch; Model and Content retain their distinct existing
constructors. This is a private implementation contract, not an external SPI.

Classify a refusal only from observed semantic facts before send.
`checkedEffectPreparation` and `refusedEffectPreparation` are not markers for
arbitrary exceptions, rate limits, missing responses or physical stop. A
provider with no authoritative lookup/idempotency must leave possibly-sent
writes unknown. Never synthesize success from equal-valued readback.

Keep close/cleanup failures on the same existing initialization or shutdown
retry handle. Mark completion only after close succeeds. A retry releases
resources; it does not repeat Source, Compute, Preview, approval or send.

## Minimal contract acceptance

Reuse the common registration, value comparison, prepare-refusal, response
recovery and cleanup fixtures from
[`installed-effect-site.test.mjs`](../../adapters/host-node/installed-effect-site.test.mjs).
Add independent provider data and only provider-specific boundary cases:

- supported registration and preparation; unsupported operation/hook refusal;
- exact typed values, selector/target and request identity, including Unicode;
- zero sends before approval, one send per granted claim;
- saved success and unknown reconstruction without resend;
- current authority/target refusal before send;
- cleanup failure retaining custody and retry without computation;
- finite codec/transport limits with exact and one-short cases;
- an external installation using public package exports and matching digests.

The [Sheets acceptance map](../reviews/2026-10-09-sheets-public-connector.md)
shows that division. A local HTTPS responder is physical-I/O fixture evidence,
not acceptance against the real service. Declare the actual supported query
and write profile rather than claiming every language shape is usable.
