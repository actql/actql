# Accounted Snowflake result admission

This adapter binds an original checked Source requirement and Common-generated
row declaration to an admitted Snowflake table description. Common reissues the
observed carrier reference with the original resource and version before comparing
it with the saved declaration. A field-map digest is never compared with an
envelope digest. Explicit declaration limits bound this preparation.

The existing `client_row_source_host` owns the acquisition, attempt, capture,
transfer reservation, retention and cleanup. This package retains that same
`RowRun` and the original SQL API result while admitting ordered partitions.
Every received body is charged before Core parsing; metadata and typed values must
match the original contracts, including precision, scale and nullability.
Malformed, incomplete, duplicate, foreign or over-budget input cannot become a
captured Source. SQL spelling comes from the description projection, not caller
text or a provider-inferred replacement schema.

An installed driver can instead borrow the Host's already-begun accounted
RowRun with `borrow_accounted_read`. The original acquisition must match
nominally. Binding the existing physical cleanup observer is mandatory before
issuing statement candidates. Complete provider admission in this mode only
marks the provider prefix complete; the Host alone finishes and captures the
original Run. The reader cannot invoke its owned-read finish/capture/close APIs.
Retiring this borrow clears aliases only after that exact transport confirms
stop; a parent close retains the same observer through cleanup failure.

Completing partition admission enters Common's awaiting-cleanup state. It does
not acknowledge a transport stop, COMMIT, publication or durable recovery.
Capture uses the original Common evidence issuer and physical verification port.
Close stops further page admission immediately, but retains the original lookup
handle, reservation and cleanup carrier until that same transport port confirms
settlement and Common cleanup succeeds. Retrying cleanup does not submit another
provider request, reserve another attempt or repeat a confirmed stop observation.
A failed begin returns the same already-reserved read as a partial cleanup carrier.

The Host/Site remains responsible for current Source authorization, exact physical
request/statement/partition binding and actual transport custody. This package
sends no SQL or network request. Tests use real Common query compilation, checked
Source declarations, accounted RowRuns and capture/cleanup Owners; physical stop
observations are explicit test doubles. They do not establish service, installed
product, Python Local, VM funding or recovery acceptance.

## SQL API transport candidates

Provider spelling follows the [SQL API reference](https://docs.snowflake.com/en/developer-guide/sql-api/reference)
and [response protocol](https://docs.snowflake.com/en/developer-guide/sql-api/handling-responses).

`prepare_statement_read` binds one request UUID, the original quoted projection,
selected warehouse/role and bounded request count to that same Read. It emits
one nominal POST candidate and then only GET candidates for the original handle
and ordered partition. Exact `.` and `..` handles remain valid opaque observations but return
`UnrepresentableHandle` before issuing a GET candidate: standard URLs remove
those path segments, even when their dots are percent-encoded. This does not
reject complete observations that need no further request or other dot-like
handle spelling. The request body selects one statement. A provider status
URL is never followed; handle bytes are encoded as one bounded path segment.
The existing Host still supplies current Source/credential authority for each
actual request. Request material is not a grant, send receipt or durable journal.

DATE and TIMESTAMP_LTZ output formats are selected from the same original
acquisition's projected Contracts. DATE requests `date_output_format=YYYY-MM-DD`;
LTZ requests `timestamp_ltz_output_format=YYYY-MM-DD"T"HH24:MI:SS.FF9"Z"` with
`timezone=UTC`. An unselected physical temporal column does not add a parameter.
A final query projection alone does not rewrite that original Source carrier.
Existing non-temporal request bytes remain unchanged. The explicit formats avoid guessing
between provider epoch representations or relying on session defaults; they do
not convert civil or retained-offset values into this UTC domain. Response and
request bounds, original response hashes, current authority and physical cleanup
remain independent. See the [SQL API parameter reference](https://docs.snowflake.com/en/developer-guide/sql-api/reference)
and [format elements](https://docs.snowflake.com/en/sql-reference/date-time-input-output).

A dispatch candidate is one-shot. `charge_statement_response` charges its exact
physical bytes before the selected driver decompresses or parses them, issuing
one nominal response ticket. `accept_charged_statement_response` consumes that
same ticket with the bounded decoded bytes. `accept_statement_response` is an
identity-decoder convenience, not evidence of physical gzip execution. Decoded
body provenance and simultaneously held wire/decoded storage remain the selected
physical driver's responsibility. The independent test using distinct body bytes
checks this API boundary only.

A valid 202 status consumes that original charge as control input, without
inventing an empty page, rows, evidence or completion. It must preserve the same
statement handle. A complete 200 result uses the original nominal column contracts
and existing Common page/capture Owner. Decoder refusal, changed handle, exhausted
request/transfer bounds or response loss interrupts this original Read. A lost
POST or GET retains the same request identity and known handle, never resends,
creates another attempt, cancels the provider or acknowledges physical cleanup.

These candidates and executed Common tests do not establish an actual HTTPS
exchange, installed Site/profile, credential current check or socket retirement.
Those remain the next consuming physical boundary, sharing this original Run.

## Interface responsibilities

- Responsibility: Snowflake page/schema adaptation delegates acquisition and
  resource semantics to the existing Common row Owner.
- Inputs and outputs: bounded original description/declaration/requirement and
  exact received bodies produce an opaque prepared read, original read or typed
  refusal. Capture remains a Common-issued original.
- Identity: original requirement, declaration resource/version, RowRun and
  response/partition identity remain bound. Copies or matching digests do not
  issue transport, Source or publication authority.
- Ownership: the read retains its same Run, result, reservation and failed-start
  cleanup carrier. Parent resources are released only after actual stop and
  existing child-first cleanup acknowledgement.
- Synchronization: synchronous ordered admission; interruption closes admission
  without implying provider cancellation, physical stop or another attempt.
- Failure: schema/decoder/bounds/transport-unsettled failures remain distinct;
  incomplete data and cleanup failure cannot become success or automatic resend.
  Physical response loss retains its original request/handle as Unknown.
- Cancellation: interruption rejects later input; physical settlement remains
  distinct and cleanup retries retain the same original attempt.
- Resources: explicit response, contract-work, declaration and same-Ledger bounds
  apply. These logical limits do not fund an unrelated VM/process/domain.
- Extension: physical driver/current credential binding remains with the Host;
  unsupported scalar types are not disguised as strings or JSON.
- Verification: independent bodies cover exact decimal38/NULL, SQL and AQL
  compilation, partitions, schema changes, malformed/overflow input, transfer
  exhaustion, partial begin, interruption and retained same-attempt cleanup;
  nominal one-shot SQL API candidates, non-row statuses, original handles,
  response-ticket replay/foreign rejection and bounded decoder refusal.

Owned reads expose Common's existing bounded acquisition capture through
`begin_result_capture` and `advance_result_capture(read, quantum)`. Callers
finish page admission first, drive that same child to completion, then obtain
its checked evidence with `capture_result_read`. The legacy synchronous path
still refuses unsupported shapes; it does not execute later Program stages.
Borrowed readers cannot use these owned capture entries. A close that retains a
pending child can retry `advance_result_capture_cleanup` on the same original;
this cannot resume pages or computation, confirm physical stop, or create a
replacement attempt.
