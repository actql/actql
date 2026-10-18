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
