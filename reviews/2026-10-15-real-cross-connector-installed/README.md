# Normally installed real cross-Connector acceptance

This is one selected opt-in SQL or AQL route over Local or HTTPS, not a mocked Connector or a general
release certification. Its independent input is two rows in a new real DuckDB
file, joined by object name with the real GCS Connector's metadata-only
`LIST_FILES`. The authored public Result `joined` contains exactly one row,
`{id: 1, tag: "actql-content-test/a.csv"}`, with ordered nonnullable number/string
columns. The original SQL, expected rows and schema live in
`scripts/fixtures/real-cross-connector-control.mjs`.

The public `@actql/node` installation loads the two original Source profiles
and a separate new disposable Local Iceberg/Catalog Effect profile. Its first
Host stops normally at the actual approval checkpoint. A new Node process
retains the exact original profiles, proof key and Host state, attaches to the
same Run, approves via the existing signer API and reads the same Result.
Before approval, both processes check the original sealed Preview's target,
action, Catalog, namespace, table, Mapping and bound artifact/schema references.
The schema CID is independently derived from the expected recursive field map;
the complete original review bytes and semantic CID must survive the restart.
Physical Catalog verification requires one commit and the exact written row.
A second fresh Node process then performs terminal-only same-Run attachment,
Result reread and zero input-I/O verification after the Effect has committed.
The original process also attaches as a final control. None may reacquire a
Source or repeat the write.

## External and local scope

The explicit metadata manifest uses the new closed
`actql-gcs-metadata-acceptance/0.1` form. Only project `test-for-smooth`, bucket
`actql-content-test`, prefix `actql-content-test/` and expected object
`actql-content-test/a.csv` are selected. Real metadata/list transport is limited
to 10 HTTP requests and 1 MiB aggregate response bodies. Token resolution is
separate: one existing authorized gcloud/impersonation subprocess, at most
30 seconds and the existing 16 KiB output bound. Its internal HTTP and buffering
remain unmeasured trusted authentication; they are not zero and do not count as
measured GCS transport. Token resolution and transport share the 60-second/$1
window. No content download, GCS write, new GCP key/account/IAM/grant/scope or
secret output is permitted.

Fresh Local Site/Host Ed25519 proof keys are permitted through the existing
Credential/Signing Owner. They are private mode0600 and remain identical in the
separate-process recovery. Old Run/Unknown keys and custody are never reused.
The global deadline is connected to the original physical HTTPS request's
cancellation and close observation. The test-only observer forwards original
requests and responses; it supplies no rows, token or replacement response.
Existing Site response clamps and campaign reservations remain authoritative.
The original request remains active until its own close event, not merely until
a timer or resolver closes. DuckDB counters forward the real native calls.
Restart has no credential resolver and refuses any input read before sending.

## Finite recipes and evidence

`prepared-checks.mjs <clean-source>` runs only inert Node controls and source
syntax/import-closure checks: nonHeavy60/TERM5/child30. These do not start a Host,
create keys, resolve credentials, read GCS or execute a database.

After a shared immutable normal4 release is ready,
`prepared-public.mjs <clean-source> <normal4-dir> <python> <metadata-scope.json>`
uses the existing Heavy pool, outer300/TERM5. The normal lifecycle installation
has a90-second bound; the one-case Node child has a180-second bound. There is
no producer or development-package fallback. The real optional native peer is
explicitly pinned to `@duckdb/node-api@1.5.5-r.4`. ActQL packages resolve only
through the existing immutable scoped loopback registry; third-party dependencies
use the normal registry/SRI and isolated user/global npm configuration. Product modules, Core JS and
Python worker assets must come from the verified normal archives; only authored
harness/oracle files are copied. No checkout runtime, NODE_PATH or adapter
module overlay is allowed.

The optional suffix `--format aql` selects the public `format: 'aql'` entry for
one fresh scenario. Omission and `--format sql` retain the original SQL default.
Both use the exact original authored document, source rows and independent
Result/schema; AQL selection does not reconstruct a Program or alter the JOIN.
Only these two closed selections are accepted, before any installation or live
Source access. Each invocation still performs one submission, one acquisition
per original Source and the same approval/post-commit recovery sequence. The
selected format is recorded in the parent and both fresh child receipts. It is
never a loop over formats or a retry of an earlier Run. Existing inherited
format environment values are cleared before the explicit selection is passed.
No real AQL success is established by selector controls or the SQL evidence below.

The optional `--transport https` selects the existing installed HTTP Host and
public Remote Client; Local remains the default. One fresh TLS certificate and
private loopback bearer are created in that invocation's private scratch before
the Node test starts. The Client trusts only the explicitly selected extra test
certificate; inherited extra-CA and format/transport overrides are cleared.
The listener binds numeric loopback, and the installed Host authenticates the
same original local principal. This is test setup, not a new GCP credential,
grant, issuer, Source, evaluator or runtime overlay. Product modules still come
only from the exact normal archives, and all original profile/authorization
objects go to the same installed Host API.

Each capture/approval/terminal process constructs and closes its own HTTPS Host
over the original durable installation. Only the endpoint port changes: original
profiles, signing key, Run, Preview and authority stay fixed. Both fresh children
forbid input acquisition; the post-commit child also forbids Table-worker starts.
Client, listener and Host closures are checked separately. Failed handles are
retained in the test's same holder; absent, false or pending Host shutdown results
cannot establish release. Unit controls use synthetic handles and are not TLS,
real Host or product E2E evidence. The fixed-source HTTPS execution below is
separate from those controls.

Save manifest/archive and all copied-input digests, the private exact process
output, independent actual Result/schema, physical Catalog rows/commit,
original Run and restart PID, before/after Source/HTTP counters, cleanup and the
outer guard's actual Owner/group/lease closure. Failures preserve the new
scratch/DB/WAL/Unknown; no blind retry or old-Run replay is authorized. A failed
cleanup is not a passing completed receipt. Each execution is qualified only by
its own actual receipts. CTAS10 on df28 and its original failures remain
separate immutable evidence; this harness does not rerun that cohort.

Attempted submission calls and observed accepted Runs are separate counters.
The original new submission reference is saved before calling startSource; an
unknown response is never relabelled as unsent. Cleanup observations are saved
even on failure, and completed is set only after final client closure resolves.
The failure receipt retains its last fixed harness phase and both the original
credential observation and the post-close observation. A pre-close `closed:false`
is never retrospectively replaced by an inferred cleanup acknowledgement.

Pre-approval public availability is recorded without reading the public Result.
The existing sealed Table Preview exposes operation and artifact/schema bindings,
not row payload text: `preApprovalPayload` explicitly records that unavailable
boundary. Full change-value inspection in Preview/Explorer remains unimplemented
and is not claimed by this narrow route. No arbitrary CID read, new read authority
or early Result publication is added. After approval, the actual Table rows and
public `joined` rows/ordered schema must match the independent oracle. The first
child must finish successfully and the Catalog commit must be observed before
the terminal-only child is started. The initial PID's later Host reopen is a
separate control, never evidence of a fresh post-commit process.

## Executed fixed-source Local route

Clean integrated source `6f5e518e1dbfb85b4c158fed43d300742eb6ecf2`
(tree `37dad9e1c8ccc88ceeea961a15ef5113ceafeb96`) passed the original
one-case normally installed Local route in `run-oaw2t5`: 1/1, complete exit0,
outer300/TERM5 and child180. G generated the single shared normal4 cohort in
`run-nrVlWO`; manifest SHA256 is
`5b89c703821e260d297b5cd25a1edb5328660a26a5168d70afa2a92cf4af4c39`.
The original 27 source-input hashes and 23 copied fixtures were unchanged from
the preceding failed f775 attempt. Product code came from the normal archives;
no adapter overlay, checkout runtime or replacement source response was used.

Actual acquisition was one DuckDB session/statement and one GCS metadata
request/response (1,927 bytes), with one credential resolution/token mint.
Before approval the public `joined` Result and Preview row payload remained
unavailable. The original sealed operation/target/Mapping/artifact/schema
projection was checked, the first Host closed, and a different process attached
to the same Run, rechecked that exact Preview and committed its approval.
The Effect produced one real Local Iceberg Catalog commit and the independent
row `{id: 1, tag: "actql-content-test/a.csv"}`. Public `joined` matched that row
and its complete ordered number/string nonnullable schema.

After observing the Catalog commit, a second new process attached to the same
terminal Run and read the same Result/schema, with zero Source requests,
credential resolutions, new submissions or Table-worker starts. All three
process PIDs differ. Client/request/credential close observations were true;
Owner/group, own/shared leases and fixture open FDs were absent. Missing
optional cleanup metadata is not invented as an acknowledgement. Original
custody, DB/WAL, proof keys and exact raw output remain privately retained.

[The fixed evidence record](accepted-6f5e518e.json) identifies the exact commands,
archive hashes, actual observations and raw-receipt digests. The b6 token failure,
b6 dependency-member failure and f775 payload-binding failure remain separate
immutable failures. Count this as **one new real installed Local scenario**;
G's ordinary consumer is a separate qualification and does not count it twice.
HTTPS for this real route, full Preview row-value inspection, all seventeen
Connector profiles, all Frontend work, Native/Python/Cloud gates, Hosted CI and
formal publication are not established by this result.

## Executed fixed-source AQL Local route

The public `format: 'aql'` entry passed one fresh real-system Local scenario at
clean source `fa800389034469ce5a80c769457696125b987706`, tree
`a172a9edc03cd0df68b9bc26bb421d63ceedccdd`, in `run-IPEIcv`: 1/1,
complete exit0 under the same outer300/TERM5 and child180. G generated the one
shared normal4 cohort in `run-IecEBP` with ordinary prepack; manifest SHA256 is
`07e04a7076c93667e68a4db3a4f523426b71d0109baeae7d52575667c1500b85`.
B's 31 inert selector controls and Root's independent 31 controls are separate
preparation evidence, not the installed run.

The authored document, source rows, independent joined row and full ordered
schema remain identical to the SQL control. Actual acquisition was one real
DuckDB session/statement and one GCS metadata response of 1,927 bytes. The
original Preview was checked before approval, with row payload and public Result
still unavailable. Three distinct processes (55734, 55953, 55990) performed the
initial capture, same-Run sealed approval and post-commit terminal Result read.
The real Local Iceberg Effect committed once and wrote the independent one row.
Both fresh processes performed zero Source requests, credential resolutions or
new submissions; the terminal process also started zero Table workers.

G independently verified all 319 installed original member bytes/modes/SRI,
23 copied fixtures, 27 source inputs and the committed Parquet row/schema without
external I/O. Owner/observed child groups, original worktree/shared ownership
tokens and fixture open FDs were closed. All 139 custody files, proof keys,
DB/WAL and raw receipts remain retained. A preflight-only Git output-buffer
failure is preserved; exact blob-ID comparison resolved it before any Host or
authentication call, with product bounds and source unchanged.

[The AQL evidence record](accepted-fa800389-aql.json) binds the commands,
artifact identities, actual Result/schema, original raw hashes and G's separate
audit. Count one newly accepted AQL Local entry to the same business scenario already
exercised through SQL; no second distinct business scenario is added, and G/Root
add no duplicate. The preceding 6f SQL proof retains its immutable source qualification.
This is not a later-main pristine RC, real HTTPS, complete Preview row-value
inspection or completion of all Frontend/Connector/product gates.

## Executed fixed-source AQL HTTPS route

The same business scenario passed its public AQL HTTPS entry at clean product
and harness source `475eb446dc5dc0ce3f5c4237618b9fe3aa975f9b`, tree
`9a902d912db22c7be67faea614bf1f3669ee52a2`, in `run-1J8u3n`: 1/1,
complete exit0 under outer300/TERM5 and child180. G generated the one shared
normal4 cohort in `run-wlgPdR` with ordinary prepack; manifest SHA256 is
`5662bed70db34891807d78948ea931dd98b61c93351465cab6430a19cf3d5724`.
There was no B producer, checkout runtime, adapter overlay or source response
replacement. The 40 inert controls executed at earlier `70cd57c2` remain
preparation evidence with matching inputs, not this installed execution.

The public Remote Client reached the original installed HTTP Host through
verified TLS on numeric loopback. Original Source profiles, authority, durable
installation, signing key, independent row and complete ordered schema were
retained. Actual acquisition was one real DuckDB session/statement and one real
GCS metadata request/response of 1,927 bytes. The public Result and Preview row
payload remained unavailable before approval. Processes 71585, 71895 and 72099
performed the original capture, same-Run sealed approval and post-commit terminal
Result read. The Effect committed once and wrote the independent one row.
Both fresh processes performed zero Source requests, credential resolutions or
new submissions; the terminal process also started zero Table workers.

All four Client/listener/installed Host closures resolved with empty retention
and false Store, authorization and diagnostic cleanup-pending fields. The exact
Owner and observed child groups, original worktree/shared tokens and fixture
open FDs were absent. All 319 installed member bytes/modes/SRI and 24 copied
fixtures matched the exact normal cohort and 28 source inputs. The 139 original
custody files, proof keys, DB/WAL and exact raw output remain privately retained.

[The HTTPS evidence record](accepted-475eb446-aql-https.json) binds the actual
commands, archive identities, Result/schema, raw hashes and independent audit.
Count **one new HTTPS entry to the same business scenario** already exercised
through SQL Local and AQL Local; additional distinct business scenarios and
duplicate G/Root execution counts are zero. The old Local qualifications remain
at their original Sources. This result is not later-main pristine acceptance,
full Preview row-value inspection, seventeen-Connector completion, numerical
funding, Hosted CI or formal publication.

## Executed fixed-source SQL HTTPS route

The original public SQL entry also passed over HTTPS at the same immutable
`475eb446dc5dc0ce3f5c4237618b9fe3aa975f9b` product and harness source,
using that exact normal4 cohort and manifest
`5662bed70db34891807d78948ea931dd98b61c93351465cab6430a19cf3d5724`.
`run-9ExQMQ` completed 1/1, exit0 under the unchanged outer300/TERM5 and
child180 bounds. No new producer, changed fixture, replacement oracle, adapter
overlay or old Run operation was needed: only the existing closed
`--format sql --transport https` selection changed from the preceding AQL run.

This was a separate fresh submission and disposable installation, with one
real DuckDB session/statement and one real GCS metadata response of 1,927 bytes.
The original sealed Preview, unavailable pre-approval row payload and Result,
same-Run approval, single Iceberg commit and independent public joined row/full
ordered schema were preserved. The approval and post-commit processes performed
zero Source requests, credential resolutions or new submissions; terminal
recovery started zero Table workers. All four Client/listener/Host close reports
resolved without pending retention or cleanup. Original Owner/child groups,
worktree/shared ownership tokens and application/custody open FDs were absent.

[The SQL HTTPS evidence record](accepted-475eb446-sql-https.json) binds the exact
four archives, 319 original member bytes/modes/SRI, 24 copied fixtures and
28 source inputs, nine original raw records, original independent oracle and
G's separate Parquet/receipt audit. The old AQL HTTPS and SQL/AQL Local records,
failed attempts, DB/WAL, keys and custody remain unchanged. Count one new SQL
HTTPS entry and zero additional distinct business scenarios. This does not
upgrade a later main or finish full Preview, seventeen-Connector Read/Write,
Model funding, Hosted CI or formal publication.
