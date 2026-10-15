# Normally installed real cross-Connector acceptance

This is one opt-in Local SQL scenario, not a mocked Connector or a general
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

Save manifest/archive and all copied-input digests, the private exact process
output, independent actual Result/schema, physical Catalog rows/commit,
original Run and restart PID, before/after Source/HTTP counters, cleanup and the
outer guard's actual Owner/group/lease closure. Failures preserve the new
scratch/DB/WAL/Unknown; no blind retry or old-Run replay is authorized. A failed
cleanup is not a passing completed receipt. This scenario is unexecuted until
those actual receipts exist. CTAS10 on df28 and its original failures remain
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
