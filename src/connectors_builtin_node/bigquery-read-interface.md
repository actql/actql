# Same-runtime BigQuery read bridge

The Node assembly exposes the existing BigQuery Catalog/Read and Common row
Owners through compiler-generated JavaScript exports. The selected bridge is
mirrored into RelA by the existing Node assembly generator. The mirror is a
derived source, not an independent semantic implementation.

- Responsibility: adapt the original BigQuery metadata, prepared read and Job
  transport ports to the existing Node assembly without implementing another
  Catalog, acquisition, credential, Job or cleanup Owner.
- Inputs and outputs: same-runtime opaque descriptions, declarations,
  requirements, acquisitions, RowRuns and response tickets retain their typed
  identity. Explicit limits and original stop callbacks accompany them. Tuples
  expose bounded request material, routing DATA and usage, never authority.
- Identity: the caller retains the selected runtime instance and original
  values throughout the call. Objects are not rebuilt from JSON, property
  layout, matching schema bytes or another runtime. Nominal foreign requests
  and responses refuse in the original Read Owner.
- Ownership: the Host owns the original RowRun, reservation, finish, capture
  and physical retirement. The response borrow registers the same stop observer;
  these wrappers cannot issue a replacement root or substitute another lease.
- Synchronization: synchronous calls preserve the original one-shot request
  and charged response order. Mutable JavaScript request objects and callbacks
  cannot substitute an already issued nominal request or response ticket.
- Failure: typed refusals pass through unchanged. The two Unit-recording ports
  recognize only the original decoder-refusal or response-loss issue; Unit
  records that refusal, not successful admission, retry or cleanup ACK.
- Cancellation: interruption prevents further read admission. Local transport
  close, confirmed remote Job termination and successful complete results remain
  separate observations. A lost POST reply does not permit another POST.
- Resources: descriptions and result limits remain explicit. The original
  Common Ledger/RowRun owns transfer, retention and execution; primitive limit
  constructors do not supply physical backing or a normal numerical profile.
- Extension: the selected Site must bind current Credential/Account authority,
  actual wire/decoded correspondence and durable original Job material before
  physical dispatch. These wrappers do not supply a normal installation, token
  provider, Job recovery authority or an alternate backend.
- Verification: the compiled Node caller exercises the real Common declaration,
  ordinary SQL preparation and original RowRun through capture. Independent
  cases cover original request material, foreign nominal tickets, accepted
  running Job followed by refusal and original response loss. Its explicit stop
  observer is not a physical HTTPS or installed-product cleanup proof.
