# Sheets real-service acceptance preparation

This is a preparation checklist, not a completed Google acceptance report.
The existing connector, common Effect owners and public Local/HTTPS fixture
acceptance are retained. No new authentication service, approval path or
secret store is required. CI remains stopped.

## Environment the resource owner must supply

Use one disposable Spreadsheet containing no business or personal data and
two distinct GRID tabs, named `actql_read` and `actql_append` for convenience.
Binding uses the spreadsheet ID and numeric sheet IDs, not those names.
The numeric `gid` in a tab's URL can identify the tab; the existing connector
checks the admitted IDs against actual API metadata before use.

| Item | Required provision or decision |
| --- | --- |
| Spreadsheet | ID or private URL; confirmation this isolated file is authorized for the acceptance |
| Read tab | Numeric sheet ID, at least 9 rows and 3 columns, fixture below in A1:C9 |
| Append tab | Different numeric sheet ID, empty dedicated tab with at least 3 columns; no concurrent writers |
| Google identity | Existing OAuth user or service account; access to this file, with write access for append |
| Access token | Supply through `ACTQL_SHEETS_ACCESS_TOKEN` in the private execution environment, or an existing Host secret resolver; provide only the reference and readiness, never the token |
| Google API | Sheets API enabled for the credential's project; an existing token issuance method with the required scope and adequate lifetime |
| Real write permission | At most **two total appended rows** in the named numeric append tab for this campaign; one common approval for the two-row Set |
| Identification | Agree one nonsecret campaign marker, such as `=actql-acceptance-20261010-01`, stored as literal Text in both rows |
| Cleanup | Recommended: retain the test file/data; the resource owner deletes it later, after receipts and any unknown-write custody are resolved. Agent deletion is not authorized by this checklist |

Existing usable resources or authentication should be reused. Do not create a
new project, service account or key merely to follow this example. If none
exists, the resource owner must select/provision the Google identity first.
An API key alone is not a substitute for the authenticated append path.

For an existing service account, share this specific file with its email as
Editor. Google Cloud IAM roles alone do not grant access to Sheets files;
domain-wide delegation and project-wide administrative roles are unnecessary
for this directly shared file. See Google's
[credential and direct-sharing guide](https://developers.google.com/workspace/guides/create-credentials#access_google_workspace_files_directly_with_a_service_account).

Use the existing OAuth/token tooling, not ActQL, to obtain a bearer token.
The `spreadsheets` scope supports this read/write acceptance; a read-only
token cannot append. An existing `drive.file` authorization is also usable
when this exact file is already granted to the app. Do not assume a scope
grants file access. Scopes apply to a Spreadsheet, not an individual tab;
isolate the file and retain ActQL's explicit target/operation authorization.
See [Google Sheets scopes](https://developers.google.com/workspace/sheets/api/scopes).
The adapter does not refresh tokens. Replenish an expired token through the
existing private supply path, never by repeating an uncertain write.

Do not paste access/refresh tokens, private keys or credential JSON into chat,
Git, commands recorded in receipts, logs or documents. Disable shell tracing
when using the existing secret tooling; do not print the environment or run
diagnostic HTTP commands containing Authorization headers.

## Finite independent read fixture

Prepare the following synthetic cells in the read tab. Blank means genuinely
cleared, not the string `NULL`, an apostrophe or a space. Enter Numbers and
Booleans as their actual types. A1:C1 are optional headers and are not read.

| Sheet row | A: Text | B: Number | C: Boolean |
| --- | --- | --- | --- |
| 2 | Literal `=literal` (Text, not a formula) | 0 | FALSE |
| 3 | Decomposed Unicode `é` (`e` + U+0301) | 7 | TRUE |
| 4 | Same decomposed Text as row 3 | 7 | TRUE |
| 5 | Formula `=""` | blank | FALSE |
| 6 | Literal `missing` | blank | blank |
| 7 | blank | blank | blank |
| 8 | Literal `error` | Formula `=1/0` | TRUE |
| 9 | Literal `outside-range` | 99 | TRUE |

The normal range is **A2:C7**, represented as zero-based, end-exclusive rows
`[1,7)` and columns `[0,3)`. Columns are Text/nonnullable, Number/nullable,
Boolean/nullable. The independent expected Named Result is:

```json
[
  {"text":"=literal","number":0,"flag":false},
  {"text":"e\u0301","number":7,"flag":true},
  {"text":"e\u0301","number":7,"flag":true},
  {"text":"","number":null,"flag":false},
  {"text":"missing","number":null,"flag":null}
]
```

Do not derive that expectation from a successful connector response. If Google
does not preserve the empty-string or Unicode distinction, retain the safe
observed distinction and report the discrepancy before changing the contract
or expectations. The codec uses calculated `effectiveValue`, not display text;
see [CellData](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/cells#CellData).

Two separate read-only installations additionally bind A7:C7 (empty Result)
and A8:C8 (typed cell-error refusal, no Result). Use distinct profile,
publication and state paths for each admitted range, not an in-place binding
change to an existing Run. Row 9 and the header must never appear in the normal
read. Codec exact/one-short evidence is already available; it is not proof of
the Google API's real range behavior.

## Configuration example and existing Host material

Copy [site.example.json](../../examples/sheets/site.example.json) outside the
checkout. Replace the spreadsheet, namespace and numeric IDs with the supplied
values. `sheetId: 0` and `appendSheetId: 7` are placeholders, not assumptions.
The example's `credentialPrivateKeyPath` is the common local grant-signing key,
**not** a Google service-account key. Its journal and all Host/approval keys
stay private. Existing local key generation and account/reviewer installation
are A's preparation work; the user need not invent those materials.

Source/Effect profile formats and ordinary Programs already exist in the
[public connector guide](sheets.md). A will connect those profiles to the
current principal, configured reviewer and Host keys using the existing
authorization APIs. In particular, keep the account's append permission
delegated for review, and explicitly allow read/metadata target revalidation.
Installation does not grant authorization or human approval. Do not copy the
fixture's all-principals account into a real installation.

## Execution after environment provision

1. Freeze latest main's complete SHA and prepare the official release cohort
   using the existing release recipe. Verify source, runtime bytes, archive
   digests and the external installation. Record versions and exact commands.
   Do not claim registry publication if installation uses local RC archives.
2. From public exports outside the repository, publish the admitted Source,
   execute the ordinary two-stage read over Local/HTTPS, and compare the Named
   Result with the independent rows. Check repeat Result reads and original
   submission lookup without another acquisition. Run the two error/empty
   installations separately; distinguish true blanks from formula values.
3. Publish the real collection Mapping, create one two-row Effect Set with
   `{text: campaignMarker, number: 0, flag: false}` twice, and retain the
   original submission/Run references before awaiting a response. The marker
   is literal `stringValue`, not a formula or a fabricated identity.
4. Verify waiting approval and zero physical appends; stop/reopen the Host,
   authenticate the configured reviewer and inspect target/values before
   approving. Continue the same Run and compare the Named Result. Capture only
   actual returned acknowledgement facts. The permitted two rows are a
   campaign-wide cap, not a per-process cap.
5. Reopen after saved success and read the same Run without new sends. A
   read-only inspection of the dedicated tab checks real cell contents and
   literal Text; it is supplemental content evidence, never proof that an
   unknown append succeeded. Do not infer a stable row ID from its position.
6. Keep response-loss, in-flight cancellation and cleanup retry injection on
   the controlled HTTPS service initially. Preserve its fixed artifact/receipt
   separately from the real Google evidence. Do not replay the same mock
   campaign merely to label it real-service acceptance.

Append position is after the last data row at send time, not a reserved row
number; see [AppendCellsRequest](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request#AppendCellsRequest).
If an actual send becomes unknown, stop all remaining real appends, retain
original journals/receipts/cleanup custody, and report it. Neither a token
refresh, process restart nor an equal row authorizes a resend. Further real
writes or deletion require a new explicit resource-owner decision.

## Evidence and stop conditions

Keep command receipts, source/cohort identities, redacted status/typed causes,
independent expected rows, observed response facts, actual dispatch counts,
submission/Run references and private custody records. Avoid raw HTTP header
logging. Public reports use references/digests, not private resource URLs,
credentials or full journal bodies. Preserve original failure receipts.

Stop before I/O if resource ownership, permitted range/write cap, current
authorization or credential readiness is missing. Stop before further writes
on uncertainty, a wrong target, unsupported values or exhausted permission.
No real Google read/write, package publication, deployment, or CI restart has
been performed by preparing this checklist. Completion still requires actual
execution and third-party installation evidence on the selected release SHA.
