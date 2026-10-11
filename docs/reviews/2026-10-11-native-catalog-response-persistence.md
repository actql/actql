# Named Catalog read and original Store persistence

The production connection calls the existing signed credential service and
named Catalog admission once, then prepares, persists and confirms the
independent original Catalog custody. Only confirmed evidence is returned for
policy adoption. The original binding comes from retained trusted Host context;
response bytes and use identifiers cannot select that expected context.

The result includes the same Store custody and its confirmed Catalog response.
The caller must retain it until its own Review obligations are discharged and
the existing Store cleanup confirms reservation return. Catalog persistence is
neither approval nor formal dispatch release.

## Failure and retry

- Physical-read failure remains the existing named Catalog issue, including any
  actual response already carried by that issue. The credential Owner retains
  its use/outcome responsibility; this connection does not retry the read.
- Failed Store preparation returns the copied original response to its caller.
  No durable save is claimed. The caller may explicitly retry saving those same
  bytes through `retain_native_salesforce_named_catalog_response`, which has no
  Provider service, grant or transport parameter.
- After Store preparation succeeds, every failure also returns that same
  pending custody. `retry_native_salesforce_catalog_custody` can persist and
  confirm that exact slot only. It cannot start a Provider call or replace the
  original grant/use. Lost save acknowledgements use the existing Store's
  reconciliation, not another read.
- Disclosure authority is checked before and after persistence/readback. A
  change refuses evidence adoption while preserving the save and custody for
  cleanup. It does not erase a physical response already obtained.
- A restored cleanup-only tombstone cannot produce active evidence. Missing
  original response custody is not permission to reacquire metadata or Source.

These failure values are a connection to existing Owners, not a new Ledger or
durable lifecycle. An in-memory returned response is not cross-process custody
until the existing Store confirms persistence. Current Provider permission is
independent of Reviewer authority and approval throughout.

## Integration and evidence scope

This child uses OSS #1454 at fixed parent
`e694a0ae33a6e82778bc8107a12d48e11ee61cc6` and targets main after that parent.
It does not modify D's Local preparation, credential service, issuer or CLI.
The generated interface is produced by the existing `moon info` generator.

Portable callback cases prove save/readback ordering, refusal after either
failure, and no adoption when authority is absent or changes. Their success is
not physical SQLite/crypto or Provider evidence. Matching Native checks compile
the production call chain against the actual Catalog, credential and Store APIs
and the resident caller. The existing warning in the create/update fixture is
retained separately from new errors.

Production holder policy installation and original Catalog grant selection,
actual TLS/Provider read, restart acceptance, public approval, Named Result and
formal release remain separate unfinished boundaries. There is no actual send,
Heavy acceptance, deployment or formal Cloud package adoption in this change.
