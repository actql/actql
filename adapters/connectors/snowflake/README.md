# Snowflake physical SQL API read

This private driver adapts the existing credential HTTPS boundary to the
Snowflake Read in the same Core runtime. It does not implement a Run, grant,
Source validator, retry controller or publication owner.

## Interface responsibilities

- Responsibility: issue the original Common statement candidates through the
  existing credential Owner and admit its exact bounded response observations.
- Inputs and outputs: an original PreparedRead and already-begun accounted
  RowRun, explicit bounds, selected warehouse/role, current Host read callback
  and credential supplier produce provider-prefix audit material or refusal.
- Identity: preparation/acquisition/run stay opaque and same-runtime; the Host's
  original request UUID, invocation/dispatch CIDs and all credential bindings
  stay fixed across the one POST and subsequent status/partition GETs.
- Ownership: Common owns original row contracts, charges and capture. One
  existing HTTPS binding owns its retained credential/request/socket, bound
  into that same RowRun's cleanup observer before I/O. Socket retirement alone
  cannot retire workspace while the driver's original response use is active;
  the same observer requires both to stop. The Host retains its root.
- Synchronization: each original request is attempted once; every send fences
  current Host authority after secret resolution. Responses are charged before
  bounded identity/gzip decoding and checked again before Core admission.
- Failure: HTTP refusal, decoder/schema rejection, unavailable authority and
  lost response remain distinct causes. One bounded raw observation stays
  private on failure. A stale refusal/loss-recording failure stays secondary to
  the original transport/decoder cause. Response loss retains Unknown and never
  resends the POST.
- Cancellation: signal/parent close stops admission; an abort request is not a
  provider cancellation, commit or cleanup ACK. Pending stop retains the same
  root and original callback, without another reservation or transport scope.
- Resources: explicit request/response/decode/count limits and the original
  RowRun transfer/retention/workspace apply. Wire bytes are charged exactly once;
  decoded bytes do not enlarge the original budget or create normal funding.
- Extension: the generic installed Host supplies only its pure typed preparer,
  same-runtime borrow and current callback. Provider spelling and gzip remain
  here; no provider branch enters the shared Host or replaces its finish/capture.
- Verification: genuine Common SQL, exact decimal38/NULL, Account and SQLite
  credential Owners run against fresh loopback TLS. Status/partition/gzip,
  foreign scope/schema, denial/revocation, lost reply, dot handles, abort and
  pending cleanup are executed. Generic Host cleanup counters separately use
  explicit stop-law doubles. This is not installed/live Snowflake, Python Local,
  normal numeric funding, Engine, wheel, write or whole-product acceptance.
