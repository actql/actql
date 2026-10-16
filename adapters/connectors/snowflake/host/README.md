# Installed Snowflake table read

The ordinary connector manifest selects this source module. The standard Host
keeps its existing installation, Account, preparation, RowRun, capture and
recovery responsibilities. Loading restores a table description from an explicit
bounded metadata snapshot; it does not refresh that snapshot or contact Snowflake.

## Interface responsibilities

- Responsibility: bind the existing Snowflake description/protocol Owners to the
  standard installed row source and the existing credential Site.
- Inputs and outputs: a closed `actql-installed-snowflake-source/0.1` profile names
  connector/resource/database/schema/table, metadata/Site paths, original Account
  configuration and explicit limits. It returns the normal source adapter.
- Identity: exact target spelling, metadata bytes, warehouse/role, Site generation,
  CA bytes, runtime bundle and installed profile contribute to the existing Host
  installation identity. Opaque preparations remain in the same Core instance.
- Ownership: the existing Host alone starts and funds the RowRun and finishes,
  captures and closes it. A private WeakMap binds that original acquisition to
  the Snowflake preparation; it issues no replacement Run, permission or quota.
- Synchronization: load/check/identity perform local reads only. Every physical
  request uses the original Host current-read callback and the existing Account
  decision, credential grant, use journal and exact request/dispatch bindings.
- Failure: invalid metadata, unknown fields, foreign scope/schema and Account
  denial refuse without Provider I/O. An accepted statement followed by a status
  refusal remains Unknown with its original request/handle and no automatic resend.
  Initialization failure retains the same Site's outstanding cleanup.
- Cancellation: cancellation/close does not invent remote termination. The driver
  confirms its own transport/use retirement; the existing Host carries pending
  cleanup and cannot turn it into a Provider, Store or Run cancellation ACK.
- Resources: the profile explicitly selects request/response/row/decoder bounds;
  the Host reserves these through the original RowRun before I/O. Metadata is
  bounded by the existing profile reader and exact canonical base64 response
  bodies before Common parsing. No normal numeric profile is supplied here.
- Extension: the generated installation table derives from `host-bundle.json`.
  Provider transport remains in `site/snowflake-sql-read.mjs`; Common schema and
  SQL admission are not duplicated in this installation or a new validator.
- Verification: real standard installation selection, Common SQL/decimal38/NULL,
  Account, SQLite credential journal, loopback TLS, original Host capture and
  cleanup are exercised. Normal package/source gates do not establish a live
  service, installed npm release, Python Local/wheel, write or recovery campaign.

## Stored inputs

The metadata file is a closed `actql-snowflake-read-metadata/0.1` record with
`connectorId`, `resource`, `database`, `schema`, `table`, `apiOrigin` and `bodies`.
Each body is canonical base64 of original SQL API information-schema response
bytes, in original partition order. Common validates the actual table target,
metadata columns and full value contract. This is an explicit installed schema
snapshot, never proof of current Account permission or a successful data read.
The explicit metadata acquisition/publication service is a separate unfinished
connection; this loader does not fabricate that observation.

The Site record uses `actql-installed-snowflake-site/0.1`, the selected HTTPS
`apiOrigin`, warehouse, role, authentication type (`OAUTH` or `KEYPAIR_JWT`),
credential authority/key/private-key path, journal root, namespace/environment,
Site key/generation and token environment-variable name. Optional `caPath` selects
the actual CA bytes. Neither file contains a token value. The existing Host
checks later installation identity; separate local identity/load reads are not
advertised as an atomic snapshot.

The required limits are `maxBytes`, `maxNodes`, `maxDepth`, `maxColumns`,
`maxNameUnits`, `maxHandleUnits`, `maxPartitions`, `maxRows`, `maxTotalRows`,
`maxRequests`, `maxRequestBytes`, `maxContractPairs`, `timeoutSeconds`,
`maxSecretBytes`, `pollDelayMs`, `maxDescriptionBytes`, `maxDeclarationBytes` and
`maxDeclarationNodes`. They are bounded caller selections, not grants. Source
metadata type refusals remain named Common refusals; unsupported time/offset/bytes
are not disguised as strings or JSON.
