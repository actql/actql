# Snowflake physical SQL API read

The installed Snowflake codec uses the shared funded Credential reader for
Query and Whole Input. The Host keeps the original Run, current Account
authority, response charge, physical binding and publication.

## Interface responsibilities

- Responsibility: issue the original Common statement candidates through the
  existing credential Owner and admit its exact bounded response observations.
- Inputs and outputs: the current bound response borrow supplies the same
  Query or Whole Input acquisition. The original table description supplies
  bounded statement spelling, and the codec admits typed responses on that Run.
- Identity: the Host's original request UUID and credential grant stay fixed
  across one POST and the status or partition GETs. The result decoder checks
  the selected acquisition's original column contracts.
- Ownership: the shared Credential reader retains each wire response before
  charging it. That owner joins and closes the physical scope before dropping
  its protocol aliases. Common keeps the RowRun and the captured evidence.
- Synchronization: each original request is attempted once; every send fences
  current Host authority after secret resolution. Responses are charged before
  bounded identity/gzip decoding and checked again before Core admission.
- Failure: HTTP refusal, decoder/schema rejection, unavailable authority and
  lost response remain distinct causes. One bounded raw observation stays
  private on failure. A stale refusal/loss-recording failure stays secondary to
  the original transport/decoder cause. Response loss retains Unknown and never
  resends the POST. After an original 202, a later status refusal also remains
  Unknown: local transport closure does not prove remote statement termination.
  Only the original Core's complete statement observation clears that uncertainty.
- Cancellation: signal/parent close stops admission; an abort request is not a
  provider cancellation, commit or cleanup ACK. Pending stop retains the same
  root and original callback, without another reservation or transport scope.
- Resources: explicit request/response/decode/count limits and the original
  RowRun transfer/retention/workspace apply. Wire bytes are charged exactly once;
  decoded bytes do not enlarge the original budget or create normal funding.
- Extension: the same statement codec serves both acquisitions. Query keeps
  its checked operator and output semantics. Whole Input uses its original
  RowInputAcquisition and its complete-input capture.
- Verification: loopback TLS tests cover typed decimal38 and NULL, one POST,
  exact status and partition requests, gzip, denial and revocation, lost reply,
  stale response recording, pending cleanup, and exact first close. The
  public key-pair fixture checks attach and same-reference submission against
  the original Named Result.
