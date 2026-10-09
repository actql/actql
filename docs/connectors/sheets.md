# Sheets: finite typed read and approved append

The standard Node installation includes the Sheets Source and Effect adapter.
Use `@actql/node` for Local execution, `@actql/sdk` for a remote HTTPS Host,
and the public publication/HTTP-host exports of `@actql/local-node` when
configuring that Host. No dynamic package download or provider factory is
required. Hosted Cloud and Native Sheets execution are not included.

## Installation and boundaries

The installation consists of a Site JSON file, a Source or Effect profile,
and the publication produced by `publishSource` or `publishEffect`. All paths
in these files are explicit absolute installation paths, not Program inputs.
The Site supplies these fields:

```json
{
  "version": "actql-installed-sheets-site/0.1",
  "apiOrigin": "https://sheets.googleapis.com",
  "spreadsheetId": "AUTHORIZED_TEST_SPREADSHEET",
  "gridRange": {
    "sheetId": 0, "startRow": 0, "endRow": 4,
    "startColumn": 0, "endColumn": 3
  },
  "appendSheetId": 7,
  "columns": [
    {"name": "text", "type": "string", "nullable": false},
    {"name": "number", "type": "number", "nullable": true},
    {"name": "flag", "type": "boolean", "nullable": true}
  ],
  "namespaceId": "AUTHORIZED_NAMESPACE",
  "environment": "test",
  "siteKey": "sheets-site",
  "siteGeneration": 1,
  "credentialAuthorityId": "INSTALLED_AUTHORITY",
  "credentialKeyId": "INSTALLED_KEY",
  "credentialPrivateKeyPath": "/configured/credential-signing.key",
  "journalRoot": "/configured/credential-journal",
  "tokenEnvironment": "ACTQL_SHEETS_ACCESS_TOKEN"
}
```

The signing key is the existing credential-grant authority, not a Google key.
Google access tokens are obtained through the Host's existing secret resolver
or the named environment reference. No OAuth acquisition/refresh flow is
implemented by this adapter. A test-only `caPath` may be supplied. Production
egress and the account must explicitly authorize the selected origin,
spreadsheet and operations; changing a URL is not authorization.

Source profiles use version `actql-installed-sheets-source/0.1` and require
`siteProfilePath`, `publicationPath`, `connectorId` and
`accountConfigurationWire`. Effect profiles use
`actql-installed-sheets-effect/0.1` and also require `sources`, for example
`[{"target":"text","field":"text","null_behavior":"reject"}, ...]`.
Every declared write column must be supplied. The explicit account read rule
for the write collection authorizes target revalidation; the Effect rule does
not implicitly grant that read.

Publication checks the exact spreadsheet and numeric sheet IDs. The generated
create Mapping binds `spreadsheet_id` and `sheet_id` as the collection identity
and declares `primary_identity: null`. Tab names, row coordinates and equal
values are not row identifiers. Update, upsert, delete and ID selectors remain
unsupported. Source row keys are not relaxed by this Mapping shape.

```js
import {open} from '@actql/node';
import {publishSource, publishEffect} from '@actql/local-node';

await publishSource({sourceProfilePath, directory: stateDir});
const {mappings} = await publishEffect({effectProfilePath, directory: stateDir});
const client = await open({stateDir, durability: 'durable', installation: {
  effectProfilePath, authorization
}});
// Use mappings[0].target and mappings[0].mappingRef in the ordinary
// create Effect. The Host's normal reviewer/Checkpoint API approves the Set.
```

`authorization` is the standard account/reviewer/Host-key installation, not a
Sheets approval mechanism. The authored
[public acceptance](../../adapters/connectors/sheets/test/sheets-public-acceptance.fixture.mjs)
contains complete Local and HTTPS examples with synthetic credentials and
independent Programs. Do not copy its permissive test account to production.

## Read contract

Read is a finite, zero-based, end-exclusive rectangle: at most 100 rows,
64 declared columns, 6,400 cells and a 2,000,000-byte response. Grid indexes
and sheet IDs must fit the provider bridge's nonnegative int32 domain. Cell
types are explicit Text/Number/Boolean; no date, business key or formatted-string
inference is performed. Evaluated `effectiveValue` is authoritative, including
formula results. Cell errors and missing evaluated formula results refuse the
read rather than becoming NULL. See Google's
[CellData](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/cells#CellData)
and [getByDataFilter](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/getByDataFilter).

All API-blank rows are excluded as an explicit part of this Source contract.
Only declared columns participate. An existing empty string, zero or false is
not blank. Otherwise an absent nullable cell becomes NULL and an absent
required cell refuses the read. Order and duplicates of retained rows are
preserved. The adapter does not reconstruct distinctions the API has lost.

The current common query-acquisition profile accepts a scan/filter/select
capture stage followed by a separate Relation stage that publishes the Named
Result. The example uses an explicit `filter: "true"`, not a hidden rewrite.
Direct publication of the capture task is not claimed as supported: the
common managed identity policy refuses it. Other arbitrary query-acquisition
shapes are not added by this connector. That direct-publication refusal is
currently discovered after acquisition, not a new pre-I/O guarantee.

## Write contract

Write appends one typed row per physical `AppendCells` request to the
explicitly dedicated numeric tab. The existing common Preview and approval
cover the complete Effect Set, not separate human approvals per row. Append
position is after the last data row **at send time**, as defined by Google's
[AppendCellsRequest](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request#AppendCellsRequest).
No fixed coordinate or multirow atomicity is promised.

Text is sent as `stringValue`, never `formulaValue`. NULL, empty Text, missing
required fields, wrong scalar types and values outside the finite codec budget
are refused before send. These restrictions concern this append profile,
not the language's general value domain. Response bodies are bounded and a
successful exact batch acknowledgement records the spreadsheet, sheet and
one acknowledged row; it does not invent a provider row reference.

Successful rows are retained and never resent. The first possibly-sent row
without a trustworthy acknowledgement stays unknown and prevents subsequent
unsent rows. HTTP errors, lost replies and same-valued readback do not prove
nonexecution or settlement. Reconciliation and restart preserve that custody
without repeating Source, Compute or append. Revoked authorization or a changed
numeric target refuses an approved write before physical send.

## Verification and remaining work

The typed codec/bridge, normal Host tests and external packed acceptance are
separate checks. Run the focused wrapper or the dedicated packed consumer:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/connectors/sheets/catalog src/connectors/sheets/host_node
node scripts/local-checks.mjs test node -- \
  adapters/connectors/sheets/test/sheets-standard-host.integration.test.mjs
node scripts/test-packed-sheets.mjs
```

The packed command requires clean committed build inputs, uses the existing
four-package release recipe with normal prepack, verifies the exact source SHA,
frozen runtime bytes and tarball digests, and copies only test support to an
external installation. It exercises the same authored cases through public exports,
including separate-process saved-success and unknown reconstruction.

Real Google service acceptance remains pending until an explicitly authorized
spreadsheet/tab, secret reference and operation scope are supplied. Synthetic
HTTPS success is not Google service success. No CI, deploy or npm publication
is implied by a local receipt. See the
[owner and acceptance map](../reviews/2026-10-09-sheets-public-connector.md).
