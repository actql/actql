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
are signed. For Reviewer proof it comes only from the original Checkpoint
Owner's typed Resolution proof (`resolution_proof_preimage` or
`PreparedResolutionProof::preimage`) or typed Effect Approval proof
(`PreparedEffectApprovalProof::preimage`). The latter signs the already
required `actql-approval-attestation/0.1` with the same current Reviewer key as
its Resolution. Each distinct preimage requires its own authenticated original
scope and durable exact-preimage grant/use; one use cannot sign both artifacts.
For Host attestation it comes from the admitted attestation preimage. The
metadata layer does not substitute
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
Client Run read, issuer issuance responsibility and Host attestation remain
distinct. The explicit Native issuer route still requires its original selected
issuer configuration and current `credential/<issuer>:issue` decision; the
narrow initial-Host route below does not replace that route or manufacture that
Account decision.
Restored metadata cannot open a key, produce a new claim, repair missing
originals, extend expiry, or retry an unknown signature outcome.

Claim/query/outcome/cleanup and public Approval assembly are separate connection
work. Saved signature return requires authenticated original outcome and current
return authorization. Lost claim/ACK remains unresolved until the existing
journal establishes its original outcome; failed cleanup retains the same
Owner, retry handle and reservation. This metadata contract introduces no
parallel Grant issuer, Store, Ledger, Scheduler or Recovery Owner.

### Initial Local Host issuance responsibility

An authenticated original explicit Local initialization/adoption may supply a
private operational admission to the existing LocalSigning issuer for that same
physical Store and original installed key generation. This is an intentional
initial-0.1 operational extension, not authority previously supplied by signer
metadata or key generation. General Host adoption, a PEM, public-key CID, path,
signer label, current file hash or incoming approval is insufficient. Missing
original initialization, installation or policy remains unavailable; an ordinary
cold open cannot initialize or reconstruct it.

For a newly and explicitly initialized default installation, the selected
packaged policy is the closed
`actql-local-signing-bootstrap-policy/0.1` original: `max_uses` is exactly 1
physical use per exact purpose-bound operation, and `max_issue_interval_ms` is
exactly 300000. Its canonical body and CID are retained/authenticated with the
original initialization intent, same Store/key generation and Host adoption.
This is a new explicit policy selection, not a discovered old allowance or a
change to Submission TTL, execution funding or the grant/use wire bodies.

The issuer identifier is exactly `local-signing/` followed by the original
initialization intent CID including `sha256:`. Common computes this identifier
from the original intent identity; this creates no new identity domain and the
string alone is not authority. The initialization intent precedes key/issuer
adoption, so it does not depend on its own later adoption record. The actual
authenticated initial nonce, Store/account/configuration and key custody remain
necessary; later Host identity, current paths or replacement initialization
cannot substitute.

At the first durable issue, the actual trusted Host samples its current clock
once. The absolute expiry is the earlier of that sample plus 300000 milliseconds
and any earlier original key/authorization validity bound. Checked arithmetic
refuses negative/uncertain time, Int64 overflow or an already expired bound.
Persist the actual sample, absolute expiry, policy and same grant/use with the
original operation. Restoring, reading, answering again or observing Unknown
does not resample/renew it. A prior claimed, expired or Unknown operation cannot
be bypassed by another grant, ordinal, decision, preimage, key or initialization.
Only absent configured signers selects this default; configured named signers
retain their explicit original route and never fall back to this policy.

For the two typed ReviewerProof artifacts, retain one original Effect Approval
and one original Checkpoint Resolution. An Approved Resolution may follow only
its exact required, already successful original Approval evidence: same
Checkpoint, Request/Run/Unit, Reviewer, key generation, proof preimage and stored
signature/use. This is not another operation for the same artifact. A renamed
or changed Resolution, incomplete/Unknown Approval, foreign key or altered
evidence cannot select this continuation. Rejected answers retain their
existing evidence-free route; a signed Approved answer cannot be replaced by
signing a conflicting rejection.

The original trusted initialization/adoption must retain or durably authenticate
the actual installation issuer identity and its explicitly selected finite
expiry/use policy. Neither a guessed issuer label, Submission epoch lifetime,
arbitrary signing lifetime nor an inferred use limit replaces those originals.
The admission is confined to one original Checkpoint, purpose, exact preimage
and original finite use. It is not an exported generic issuer, a wildcard
key-use capability or a Source, Model, Effect, egress or dispatch grant.

Require the same retained Client request, Submission, Run definition/invocation,
attempt and unit; the original current Checkpoint/kind; and the original selected
key configuration/generation. Independently require current actor, Account,
Reviewer or Host-attestation purpose authority, Run read and physical key/sign
permission. ReviewerProof and HostAttestation retain distinct selected key
originals. A Host attestation cannot supply Reviewer permission. Default
machine-user identity comes from the actual trusted installation/current actor,
not a caller's claimed human identity. A failed named selection never falls
back to the default. Cancellation, denial, retired or replaced originals refuse.

Persist/adopt the original grant and durably claim its original use in the
existing journal/custody before physical signing. Recheck current bindings
around asynchronous key access and callbacks. Commit or signature uncertainty
retains the same duty: no replacement grant, ordinal, attempt, key or signer,
re-signing or resend. Authenticated original saved-signature return and history
inspection remain separate, current-authorized no-issuance paths. Recovery may
read the same original key/issuer/grant/use/outcome; it cannot repair missing
records by initialization or reissuance.


## Native original history read

The new Native Signing history-only path requires current original-Client
RunRead and the purpose-specific current Reviewer resolve and original key
custody. The retained operation, Client request intent, logical request scope,
authenticated Submission identity, original Run, key configuration/generation
and issuer installation originals must agree. The issuer may be a different
principal from the Reviewer and original Client. Existing issuer configuration,
generation and custody requirements remain current; an issuer `issue` decision
is not read permission. This finite path adds no `credential/<issuer>:read`
Account tuple and does not install HostAttestation authorization.

History returns only an already saved original claim/outcome or exact signature.
It cannot reread secret key bytes for signing, claim an ordinal, sign again,
renew expiry, issue another grant or interpret missing/Unknown history as
unsent. Read authority does not authorize using an expired grant or admitting a
Resolution: those operations retain their independent current, expiry and
Checkpoint checks. Require current before and after the read; missing,
foreign, replaced or unverified original custody stays unavailable.

The existing Native private grant journal may retain a Signing original as a
closed `grant`/`intent`/`signing_purpose` alternative. The purpose must match the
already admitted Signing grant. Resume and Preparation private packets and all
public grant/use bytes and CIDs remain unchanged. The existing logical-request
reservation bucket is separate from the Signing grant's public Submission
identity; counters, per-request byte/object ceilings and original epoch/Run
joins are not changed by this additional typed alternative. Packet parsing and
custody inspection do not install an operational issuer, history authorization,
claim, signature or use permission.
