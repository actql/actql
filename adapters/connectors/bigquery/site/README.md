# Original BigQuery HTTPS read

This private driver connects one checked Common BigQuery read to the existing
Credential HTTPS boundary. It consumes the original accounted RowRun and Job;
it cannot create an acquisition, replace its Ledger or choose a new Job on loss.

- Responsibility: Common owns the original query, Job, request sequence,
  response tickets, schema/value admission and RowRun capture. This driver owns
  bounded HTTP transport and decoder work through the original credential
  binding. The existing Host/Journal must supply the original-operation port.
- Inputs and outputs: `readBigQuerySqlApi` consumes the original prepared read,
  RowRun frame, Job, explicit limits, current authorization and credential
  custody. It returns bounded transfer/row observations, not a Source capture,
  commit acknowledgment or permission. Host finish/capture remains separate.
- Identity: the acquisition and RowRun are original opaque Common values.
  Authorization must match the same Run invocation and dispatch request. Common
  emits the exact query body and original project/Job/location routes; the
  driver never derives a replacement from a response or replays a POST.
- Ownership: `withOriginalJob(original, sendOriginal)` is a private trusted
  assembly port. Its input contains the same live Job/request, bounded record
  and canonical wire, plus the original RowRun frame. The existing Host must
  bind these to its accepted Run, prepared occurrence, task and Store epoch,
  confirm the original Journal CAS before invoking `sendOriginal` once, and
  retain unresolved responsibility. This driver does not provide that durable
  issuer. Equal DATA, a callback, Credential Use ID or CID is not its substitute.
- Synchronization: the original transport stop observer is registered before
  Common Job preparation. Current checks surround asynchronous authorization,
  secret resolution, response receipt and decoding. Only the first request
  enters the original-operation port. After it, Common can select only the
  same Job's status/results GETs. A late or repeated callback is refused, and
  an original send remains awaited even if its caller returns or throws early.
- Failure: a missing original-operation port refuses before credential use or
  I/O. Reply loss, decoder refusal, foreign Job/schema and HTTP errors retain
  the same original Job and charged observations without partial capture or
  resend. A RUNNING Job followed by a refused GET remains Unknown; socket close
  alone does not prove remote Job termination. Cleanup failure retains the
  original RowRun borrower and its registered cleanup responsibility.
  Any JavaScript rejection value, including `undefined`, remains a failure.
  Its original reason is retained separately from send, recording and cleanup
  failures; no callback is required to reject with an `Error` object.
- Cancellation: abort interrupts the original local exchange and preserves its
  uncertainty. It does not cancel the remote Job, settle business outcomes or
  allow another POST. Processing and transport closure must both finish before
  the borrow's cleanup observer can acknowledge local retirement.
- Resources: response wire is charged to the original RowRun before gzip/JSON
  decoding. Explicit output, page, row, request, secret and material bounds
  remain in force; decoder inflation is not transfer credit. The original Host
  reservation is retained after local transport retirement until its own
  finish/close. These bounds do not establish normal process/Run funding.
- Extension: provider spelling and value conversion stay in Common's Catalog
  and Read owners. The driver cannot widen types, change query bytes, infer a
  Credential grant or install a fallback supplier. Missing normal Journal,
  startup or capacity suppliers remain unavailable.
- Verification: the real Common/Account/Credential/SQLite-use/loopback-TLS
  cases exercise exact Signed64 paging, current fences, charged gzip failures,
  loss, no resend, one-shot callbacks and original cleanup. Their explicit
  original-operation assembly double does not prove durable Run Journal CAS,
  cold Job recovery, live BigQuery or an installed product route.


## Standard table Source installation

`src/connectors/bigquery/host-bundle.json` selects the table Source through the
existing installation table and integrated Common. The installed snapshot
retains original Get Table bytes, exact project/dataset/table/location and the
selected Site/TLS authority. The existing Common description/declaration and
query-requirement preparation produce the original acquisition. Authored SQL
is not passed through as arbitrary provider query text.

The private Site's `tokenEnvironment` or trusted `resolveSecret` supplies an
already resolved OAuth access token. Service-account key exchange belongs to
its actual authentication supplier; this factory does not interpret key JSON
as a token. Parser/read ceilings in the installed profile remain DATA, while
the original RowSource/Host supplies the actual admitted Ledger and RowRun.

- Installation responsibility: this factory binds the existing table description/read driver to standard RowSource, Account/Site, original-operation Journal and cleanup owners. It adds no query scheduler or retry state machine.
- Installation inputs and outputs: closed table/Site/metadata selection and original metadata bytes produce the same Common declaration/environment and Source. Each actual query requirement retains its original prepared read/acquisition; its existing Job driver fills that same accounted RowRun.
- Installation identity: exact metadata, project/dataset/table/location, runtime, Account context and TLS bytes bind installation/approval identity. The provider Job name is deterministically selected from the original Source attempt/Run/dispatch identifiers; the separate original-operation CAS still binds the actual request before its first POST.
- Installation ownership: the registered loader requires the same Source initialization, managed configuration reader and Host service. Its original binary input and nominal native declaration are backed before construction and retained through same-owner registration/finish/cleanup. Provider preparation is associated only with its same nominal acquisition in a private weak map. Standard Account/Site, original RowRun/reader/Journal and failure-cleanup owners retain all physical and authority duties.
- Installation synchronization: prepareAcquisition retains the original checked requirement. readPages requires the standard same-RowRun withOriginalJob callback and forwards current/authorization/credential inputs unchanged to the existing Job loop; no await may replace its original first-request fence.
- Installation failure: changed metadata target/origin, malformed base64, unsupported runtime, foreign acquisition or missing original-operation port refuses. The same existing driver retains original Job/Unknown on loss or failure; no fresh POST is authorized by a metadata match.
- Installation cancellation: the existing driver and RowSource retain cancellation, borrow/transport stop and actual close duties. Factory construction failure delegates the same Site to existing initialization cleanup without reopening it.
- Installation resources: the existing initial parent composes the decoded input and complete native description/declaration peak before constructor entry, then the actual returned wire before Host JSON/Environment construction. Parser/page/row/request/secret/TLS extents and maximum bytes billed remain explicit DATA. Int64 billing uses exact decimal-string configuration and bigint only at the typed boundary; no scalar limit issues backing or resets an entered Ledger.
- Installation extension: the host manifest declares only the real Source role, with integrated existing BigQuery bridge functions. The exact target and original-operation inputs remain required when adding authentication suppliers, Effects or recovery; they cannot be replaced by a new callback/permission framework.
- Installation verification: `installed-bigquery-source.test.mjs` covers profile/metadata/TLS identity and generated table import, plus the actual registered loader with original Core/Resource/Source/Site/initial-parent retirement and real file cleanup. Malformed binary input and native schema refusal keep their original failure beneath the existing cleanup carrier. The extracted Job-driver case has explicit service/RowSource ports and retains its separate scope. These components do not prove a pristine current-source normal installation, business Run funding, real BigQuery credentials/API or cold Job recovery.
