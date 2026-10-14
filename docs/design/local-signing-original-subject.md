# Original subject suppliers for Local signing

The normative owner is [Direct Local signing identity metadata](../../spec/contracts/local-signing-credential.md).
This decision clarifies the nominal supplier of existing fields in the initial
Client Local profile. It introduces no identity domain, canonical body change,
permission or new Owner.

`ClientRequestIdentity` separates a LogicalRequestScope from an
IntentFingerprint. The fingerprint binds the checked Program Definition,
effective Parameter Values and admitted caller-input selection. The scope
distinguishes logical requests with equal input meaning. Signing therefore
binds its `request_cid` to the original fingerprint and `request_scope_cid` to
the same original logical scope, with the authenticated Submission scope kept
separately. The submitted-content identity belongs to a different nominal
Owner and cannot be substituted because it also has CID spelling.

The initial Client Local `submission_scope_cid` uses the original retained
reference's existing Submission identity: `native_client_submission_request_id`.
Its `actql-submission-identity/0.1` body binds epoch CID and caller nonce. Two
nonces under one epoch and one nonce under different epochs therefore remain
different submissions. The epoch CID or authority scope alone is too broad;
the logical request scope has a different domain. No extra reference hash is
needed. This selects the previously unspecified Signing field supplier rather
than changing those existing identity laws or historical signed bytes.

Read that reference through the authenticated retained Submission/Run-admission
owner, not from an incoming CID assertion. Keep original request/Run/Checkpoint
control revision and current Client/Reviewer/key checks around observation.
Identity projection after epoch expiry does not renew the epoch or grant
signing permission. Old Resume and Preparation field suppliers remain unchanged.

The existing paired approval/capture custody retains the actual invocation,
checked material owner, Preview and persisted Checkpoint. Its current-fenced
projection supplies the invocation from that retained chain. The authored
Checkpoint RunUnit coordinate selects the UnitDefinition in the same checked
owner. An earlier acquisition/producer unit is permitted; selecting the first
unit instead of the Checkpoint coordinate would bind the wrong computation.

This projection cannot reconstruct a missing capture, borrow a preparation
fence while waiting, recompile an old Program or backfill old journal rows.
Current live custody and durable restoration are distinct. Client RunRead,
Reviewer resolve, signer key authority and issuer issue authority remain
independent checks before and after their own observations; separate Store and
journal reads are not one atomic transaction.

The flat grant schema, field names, CID domain and canonical bytes are
unchanged. Past signed evidence is preserved and cannot be relabeled as new
operational authority. Original claim/outcome/Unknown and cleanup retain their
existing Owners and responsibilities.
