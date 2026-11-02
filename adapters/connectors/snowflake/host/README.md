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
  installation identity. Managed CA reads retain the exact observed-FD bytes sent to Site; standalone identity remains DATA hashing only. Opaque preparations remain in the same Core instance.
- Ownership: the registered loader requires the same Source initialization, managed configuration reader and Host service before native construction. Its original Buffer array, description/declaration, Environment and optional KeyPair material stay on that initial parent through Source registration/finish and retirement. The existing Host alone starts and funds the RowRun and finishes,
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
- Resources: all original metadata Buffers are constructed together inside the same pre-reserved input projection. Node counts and decoded-text/wire bounds then compose the existing conservative Source envelope before native description/declaration construction; the full peak remains retained through original Source retirement. Original KeyPair material is created under that envelope, remains lazy, and its close follows the original Site close result. The profile explicitly selects request/response/row/decoder bounds;
  the Host reserves these through the original RowRun before I/O. Metadata is
  bounded by the existing profile reader and exact canonical base64 response
  bodies before Common parsing. No normal numeric profile is supplied here.
- Extension: the generated installation table derives from `host-bundle.json`.
  Provider transport remains in `site/snowflake-sql-read.mjs`; Common schema and
  SQL admission are not duplicated in this installation or a new validator.
- Verification: real standard installation selection, Common SQL/decimal38/NULL,
  Account, SQLite credential journal, loopback TLS, original Host capture and
  cleanup are exercised. Registered initialization components use actual initial Resource/Source registration/retirement and scoped state-FD checks; their explicit RowRun/Ledger cases do not certify ordinary Request/Plan/provider output/failed-child funding or a pristine current-source normal artifact. Public Client Local/HTTPS fixtures also check SQL to
  Named Result, repeated reads, attach and same-submission lookup without a
  second Provider request. They use the same preplanned acquisition/Compute
  Ledger and confirm its original reservations retire after client close.
  Normal package/source gates do not establish a live
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

## Lightweight Python Remote consumer

For a Host already configured with the `snowflake.usage_30d` alias, the ordinary
SDK-only installation uses the public Remote API. Source credentials stay with
the Host's existing credential Site; they are not Python client options.

```python
from actql_sdk import Client

with Client.connect(endpoint, token) as client:
    original = client.new_submission()
    execution = client.start_source(
        "SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, "
        "TREND AS trend FROM snowflake.usage_30d |> RESULT usage",
        format="sql", submission_ref=original,
    )
    state = execution.wait()
    if state.status != "succeeded":
        raise RuntimeError(state.status)
    rows = execution.result("usage").all(max_rows=100)
```

Decimal values use their exact public decimal spelling, including values beyond
binary64 precision; NULL remains `None`. The matching async methods use the same
wire and original Run. Save both `execution.ref` and the original submission
reference when another process needs lookup/attach. Lookup and attach do not
restart the Source query or replace its original custody.

The bounded Python consumer tests use a normally installed SDK-only wheel, with
its RECORD and current source/generator inputs checked independently. They cover
sync/async reads, application-owned typed rows without Pydantic, reader close,
separate Python processes and a fresh Host process reopening the same new Store.
These fixture results do not establish live Snowflake service, Python Local
startup, an automatically acquired metadata snapshot or a new release cohort.

## Provider key-pair authentication

A `KEYPAIR_JWT` Site may select RSA key material instead of an already issued
JWT in `tokenEnvironment`. Remove `tokenEnvironment` and add the closed field:

```json
"keyPair": {
  "accountIdentifier": "myorg-myaccount",
  "user": "ACTQL",
  "privateKeyEnvironment": "SNOWFLAKE_PRIVATE_KEY",
  "passphraseEnvironment": "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"
}
```

Omit `passphraseEnvironment` for an unencrypted PEM. The account identifier is
explicit provider issuer data, without region/domain suffixes, not an inferred
request origin. Neither key nor passphrase is stored in the profile. The
existing `resolveSourceSecret` callback, when supplied, receives the same
original credential-use context plus `materialEnvironment` naming the selected
material; otherwise only those selected environment variables are read.

The Site's `credentialPrivateKeyPath` still identifies its independent Ed25519
grant-signing original. It is not a provider key. OAuth and pre-issued JWT
profiles keep their existing token path; invalid/mixed selections refuse rather
than falling back. The same existing `maxSecretBytes` bounds each private input
and the output token; a too-small profile is a refusal, not permission to grow.
The existing current/credential-use checks and original response binding remain
in force. [Material responsibilities](../site/README.md) distinguish the local
cache, Provider expiration and actual transport/Run cleanup.
