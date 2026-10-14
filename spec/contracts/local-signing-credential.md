# Direct Local signing identity metadata

This additive contract belongs to the existing Credential Owner. It describes
finite identity metadata for `ReviewerProof` and `HostAttestation`. Parsing a
grant or matching a CID supplies neither current signing permission nor opaque
key custody, a durable use claim, a signature, or Checkpoint admission.

The HTTP Local, Remote, Resume and Preparation grant/use bodies and CID domains
are unchanged. Signing does not populate fictional method, origin, path or body
fields. Its separate grant domain is
`actql-local-signing-credential-grant/0.1`; its use domain is
`actql-local-signing-credential-use/0.1`.

## Original bindings

The grant is a closed, flat object described by
`actql-local-signing-credential-grant.schema.json`. It binds the original
Submission/request scopes, request CID, Run definition and invocation, attempt,
unit definition, Checkpoint identity/kind, adopted Host, Account configuration,
principal/current authority scope, independently selected key configuration,
generation, key ID and public-key CID, issuer identity, purpose, exact preimage,
expiry and use limit. Every field contributes to the grant CID.

For the initial Client Local profile, `request_cid` is the original
`ClientRequestIdentity`'s IntentFingerprint, read through
`client_request_intent_cid`. `request_scope_cid` is the LogicalRequestScope CID
of that same original request, read through `client_request_scope_cid`. Retain
and authenticate the original Submission scope separately. For this profile,
`submission_scope_cid` is `native_client_submission_request_id` of the reference
read from the authenticated retained Submission and its original Run admission.
The existing `actql-submission-identity/0.1` CID binds the original epoch CID and
caller nonce. Neither the shared epoch CID, authority scope, logical request
scope nor a new reference-wrapper hash can replace it. The reference getter is
identity only; existing epoch/journal authentication and current request, Run,
Checkpoint and control-revision checks remain mandatory around the read.
Expired-epoch history inspection is not new-start or signing permission.
Missing or foreign retained admission remains unavailable; an incoming
reference's matching CID cannot repair or replace it. Matching intent
under another logical scope denotes another request; changing intent under
the same logical scope is a conflict. `ClientSubmittedIntent` binds submitted
`kind/input/parameters` content and is a different identity; its CID, a Provider
request CID, caller ID, proof preimage or a transport-wrapper hash cannot
replace the original IntentFingerprint.

At a waiting Checkpoint, `run_invocation_cid` comes from the original invocation
retained by the existing opaque paired approval/capture custody. Select
`unit_definition_cid` through the original checked owner and the Checkpoint's
explicit RunUnit coordinate. Recheck original request, Run, Checkpoint and
current custody around this projection. A preparation-start fence, the first
array element, recompile, recapture or current Program reconstruction cannot
supply missing originals. Missing/retired original custody remains unavailable;
a live projection alone does not establish durable restart support.

`checkpoint_kind` uses the existing Checkpoint Owner's six closed tokens.
`purpose` is exactly `reviewer_proof` or `host_attestation`. The two purposes
require separate selected key originals at the operational boundary. Changing
purpose or key metadata changes the identity; metadata alone cannot establish
that an installation has a key or permits its use.

`preimage` is the original Checkpoint Owner's CID text whose exact UTF-8 bytes
are signed. For Reviewer proof it comes from
`checkpoint_runtime.resolution_proof_preimage`; for Host attestation it comes
from the admitted attestation preimage. The metadata layer does not substitute
a grant CID, hash the preimage again, or reconstruct it from incoming Resolution
fields. A syntactically valid caller-provided preimage remains metadata until
the operational Owner authenticates its original binding.

## Canonical bytes and finite limits

The existing value-preserving ordered JSON encoder writes keys in canonical
UTF-16 order, without NFC or line-ending normalization. The grant CID is
`sha256:` followed by the digest of the exact canonical UTF-8 body, including
`version`. A reader requires that the recomputed CID and re-encoded bytes both
match; whitespace, unknown fields, duplicate keys, alternate order or altered
original values are not interchangeable grant originals.

The existing Local grant limits are reused: 32,768 input/output bytes, 64 nodes
and depth 2. Existing nonempty UTF-16 text limits are 512 for Account, issuer,
principal and key IDs; 256 for attempt and Checkpoint IDs. All CID fields and
the preimage use lowercase `sha256:` plus 64 hex digits. Expiry is a positive
Int64 encoded as canonical decimal text. `max_uses` is an integer from 1 to
1,024. The JSON schema describes structural shape; the canonical reader also
enforces Int64, exact bytes/CID and UTF-16 bounds.

The closed use body contains only `grant_cid`, `use_id`, `use_ordinal` and
`version`, under its separate domain. Its exact body determines the use CID.
The original finite ordinal is within the original grant's limit; its reader
does not increment a counter or refresh expiry. It reuses the existing use
reader limits of 4,096 bytes, 12 nodes and depth 2, with a 256-unit nonempty use
ID. Scope/expiry/revocation comparisons are pure binding validation, not an
Account Allow or proof that an ordinal was durably claimed.

## Operational boundary

The existing Host and Credential Owners must authenticate original adoption,
selected key generation and private resource custody, obtain current
purpose-specific authority, reserve bounded workspace, claim the original use
durably, and recheck current authority after callbacks. Reviewer resolve,
Client Run read, issuer issue authority and Host attestation remain distinct.
Restored metadata cannot open a key, produce a new claim, repair missing
originals, extend expiry, or retry an unknown signature outcome.

Claim/query/outcome/cleanup and public Approval assembly are separate connection
work. Saved signature return requires authenticated original outcome and current
return authorization. Lost claim/ACK remains unresolved until the existing
journal establishes its original outcome; failed cleanup retains the same
Owner, retry handle and reservation. This metadata contract introduces no
parallel Grant issuer, Store, Ledger, Scheduler or Recovery Owner.
