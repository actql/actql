# Accounted Snowflake result admission

This adapter binds an original checked Source requirement and Common-generated
row declaration to an admitted Snowflake table description. Common reissues the
observed carrier reference with the original resource and version before comparing
it with the saved declaration. A field-map digest is never compared with an
envelope digest. Explicit declaration limits bound this preparation.

The existing `client_row_source_host` owns the acquisition, attempt, capture,
transfer reservation, retention and cleanup. This package retains that same
`RowRun` and the original SQL API result while admitting ordered partitions.
Every received body is charged before decoding; metadata and typed values must
match the original contracts, including precision, scale and nullability.
Malformed, incomplete, duplicate, foreign or over-budget input cannot become a
captured Source. SQL spelling comes from the description projection, not caller
text or a provider-inferred replacement schema.

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
- Cancellation: interruption rejects later input; physical settlement remains
  distinct and cleanup retries retain the same original attempt.
- Resources: explicit response, contract-work, declaration and same-Ledger bounds
  apply. These logical limits do not fund an unrelated VM/process/domain.
- Extension: physical driver/current credential binding remains with the Host;
  unsupported scalar types are not disguised as strings or JSON.
- Verification: independent bodies cover exact decimal38/NULL, SQL and AQL
  compilation, partitions, schema changes, malformed/overflow input, transfer
  exhaustion, partial begin, interruption and retained same-attempt cleanup.
