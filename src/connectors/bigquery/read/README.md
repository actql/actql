# Accounted BigQuery query Job and page admission

This package binds the original table description and checked Source declaration
through Common's existing acquisition and carrier-schema issuer. It reserves no
independent quota and creates no new Run. The selected projection and original
Job routing DATA remain attached to the same accounted RowRun.

The catalog codec retains the metadata Contract on its CheckedValues. Before
Common capture, the existing value-admission Owner rechecks each immutable value
against the same acquisition's original Contract, within the caller's aggregate
node/text bounds. Equal metadata/schema bytes do not replace nominal identity.

Each received envelope is charged before parsing or cursor validation. Page
admission requires the original Job identity, exact projected contracts and the
preceding opaque page token. Total rows must stay consistent across pages; the
explicit page bound and original transfer/row bounds remain enforced. Complete
admission requires a final absent token and exactly the declared total. Neither
an empty page nor an absent token alone proves a complete result.

Owned reads finish and capture only through Common, with its original physical
stop observation. Unknown cleanup retains that same Job, reservation and cleanup
carrier; it cannot reserve another attempt or send another request. An installed
Host may lend its already-begun original RowRun; that borrow must bind the same
physical stop observer before admitting responses. It cannot finish, capture or
close the Host's root. The original Host retains retirement responsibility.

The provider's total-row metadata allowance remains a nonnegative Int64. When
borrowing an already-begun Host RowRun, it is compared as Int64 and is never
converted into a capture allocation or another reservation. The Host's existing
page and capture capacities still bound every admitted row. Starting an owned
read separately requires an Int-representable capture bound before reserving
its original RowRun; an oversized bound is refused without a cleanup carrier.

A Job transport projection may bind that same original read once, before its
first request. It emits a single POST with the caller's original Job ID,
selected metadata-bound SQL, explicit GoogleSQL mode and maximumBytesBilled.
The selected Host must record that original ID through its existing journal before
physical dispatch; constructing this material is not durable Job adoption.
`job_original_record` snapshots the same live Job before its first POST attempt,
including exact method, escaped path, body, project, Job ID and location. The
closed `actql.bigquery-job-original/0.1` DATA envelope has independently bounded
bytes, tree, routing identity and aggregate request material. It uses the same
Common JSON encoder and original transport component encoding. The cold reader
admits only this format and its seven string fields. It preserves the body and
path as values, without parsing/reformatting SQL or deriving new routing from a
Credential Use ID. Its outer JSON projection is deterministic; outer JSON syntax
is not a new authority or identity domain.

`job_original_record_matches_request` compares that DATA to the actual nominal
first request in the same live Job. A true result neither confirms a journal
COMMIT nor permits dispatch. The existing Journal/Host must atomically bind the
original accepted Run/task and Store epoch, confirm the original CAS, then invoke
`attempt_job_request`. A lost COMMIT response requires original-key lookup; cold
DATA cannot construct another JobRead, reserve, launch, cancel, settle or resend.
The existing request path does not acquire a Journal supplier by adding this
codec. A stored body remains untrusted DATA until the original live request and
Host scope are independently checked.

Only same-Job status GETs and result GETs follow. Request candidates and charged
responses are nominal and one-shot; a missing response cannot repeat POST or
mint another Job. Every response consumes the original transfer capacity before
its selected physical decoder parses or decompresses it. The returned Job
reference, query text, SQL mode and scan cap must match the original material.

A matching DONE status establishes remote execution ended, independently of
result success. A final error never becomes a Source; warnings alone are not a
final error. A later HTTP refusal, socket close or local read retirement cannot
confirm a previously accepted running Job ended. Result pending observations
consume their original charge without inventing a data page. Bounded repeated
GETs still refer to the same original Job and exact preceding page token.

Job routing metadata is neither a launch/cancel grant nor proof of remote job
termination. This package emits bounded request material and sends no request. Authentication, Job creation,
provider cost limits, transport custody and current authorization remain with
the selected Host/Site. Common capture tests and explicit stop-observer doubles
are distinct from physical HTTPS, installed Source or live-service acceptance.
Unsupported value carriers remain named refusals in the existing catalog codec.

## Interface responsibilities

- Responsibility: BigQuery page adaptation uses the existing checked Common
  acquisition, value-admission and capture Owners.
- Inputs and outputs: original description/declaration/requirement, Job routing
  DATA, bounded bodies and explicit limits produce counts, original capture or
  typed refusal. Request material is not dispatch authority or a Source grant.
- Identity: the same acquisition, RowRun, projection, original Job and preceding
  page token remain bound. Equal schema bytes do not replace the acquisition's
  nominal Contract; runtime values are rechecked by its existing Owner. The live
  Job-to-RowRun observation compares both the original RowRun and acquisition
  by identity; it cannot turn a matching body, Job ID or cold record into custody.
- Ownership: owned reads retain their original reservation and failed-start
  cleanup carrier. Borrowed readers cannot finish, capture or close the Host's
  Run. Retirement requires the original physical observer and Common cleanup.
- Synchronization: ordered synchronous admission consumes one original page
  charge; one nominal request/response is outstanding, and a second or foreign borrow refuses. Completion describes admitted
  pages, not remote Job or transport termination.
- Failure: schema/cursor/count/contract/transfer failures close admission without
  exposing a partial Source. Failed cleanup retains the same original Job and
  reservation; it cannot create another attempt or imply a successful resend.
- Cancellation: interruption prevents further admission; provider cancellation,
  physical stop and business outcomes remain distinct observations.
- Resources: the original Ledger reserves transfer, retention and execution.
  Explicit page/body/node/text/row bounds apply; logical limits do not fund an
  unrelated process, VM or provider domain.
- Extension: physical Job creation, authentication, current authorization, billing enforcement
  and physical transport remain with the existing Host/Site. Unsupported value
  carriers are refused rather than disguised as strings, JSON or rounded floats.
- Verification: independent QueryIntegration cases exercise the real Common
  checked Source, exact decimal and SQL null capture, complete multi-page reads,
  malformed/foreign/cursor/total/transfer refusals, original Contract rebinding,
  empty results, borrowed custody, uncertain cleanup, one-shot Job material, closed original-record vectors, exact body preservation, foreign nominal request refusal, lost POST responses, foreign Jobs/configuration, request bounds and accepted-running-Job refusal. Stop-observer doubles
  do not establish physical HTTPS, installed Source or live-service acceptance.

Provider transport follows the official [jobs.insert](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/insert),
[jobs.get](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/get),
[getQueryResults](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/getQueryResults)
and [Job status/configuration](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/Job)
contracts. SQL identifiers use the original names under GoogleSQL quoted-identifier
escaping; neither names nor tokens are trimmed or normalized.

Owned reads expose Common's existing bounded acquisition capture through
`begin_result_capture` and `advance_result_capture(read, quantum)`. Callers
finish page admission first, drive that same child to completion, then obtain
its checked evidence with `capture_result_read`. The legacy synchronous path
still refuses unsupported shapes; it does not execute later Program stages.
Borrowed readers cannot use these owned capture entries. A close that retains a
pending child can retry `advance_result_capture_cleanup` on the same original;
this cannot resume pages or computation, confirm physical stop, or create a
replacement attempt.
