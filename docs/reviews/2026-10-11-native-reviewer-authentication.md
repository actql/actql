# Native original-principal Reviewer authentication

The retained Resume caller previously required an already authenticated
`HostAuthentication`. Reading the Resolution's actor, key and preimage does not
authenticate them. This adapter verifies the existing common unsigned Resolution
CID text with the installed Native Ed25519 implementation and independently
selected current Reviewer registration.

`NativeEffectReviewerSelection` comes from trusted original Host custody. Its
principal is not the signer, Source principal or a value from the delivery wire.
`read_current(selection, key_id)` must use the existing current authorization and
Reviewer registration for that principal and original Checkpoint. This port
creates no registry and accepts no permission from a public request. Registration
identity, key, approval scope, authority context and policy are checked before
verification and read again afterward. Site retirement, revocation and rotation
return refusal rather than authenticated historical authority.

`authenticate_native_effect_reviewer` supplies the existing Host authentication
port. It does not admit approval evidence or create a Resume claim. The private
verification seam is available only to package tests; production always invokes
`signature.Library::verify_ed25519`.

`NativeResidentEffectReview::authenticate_remote_reviewer` selects the original
Checkpoint from its retained report and requires the original durable typed ACK.
After physical Reviewer verification it invokes the existing exact Resume
envelope admission and Native Host-attestation verification. The independent
registration is rechecked through that latter verification boundary. Candidate
Checkpoint, principal, claim and keys cannot replace the original report or Host
installation. The returned authentication is not a Provider-send permit: the
existing current Cloud claim/fence, Site, original Run lifetime, Reviewer, target
credential and Ledger checks remain required before execution.

The private framing parser preserves string values and duplicates are rejected.
Signed preimages are supplied by `checkpoint_runtime::resolution_proof_preimage`;
this change introduces no identity domain, serializer, ledger or approval owner.

## Validation scope

The independent signature corpus supplies the expected preimage and signature.
Seven focused JS tests exercise the private authorization/framing seam: original
principal versus signer, foreign Checkpoint/registration, malformed or duplicate
proof, physical-verifier refusal/error, and registration/Site change during
verification. These seam tests do not execute Native cryptography.

The actual Native caller test uses the existing independent Ed25519 corpus and
installed signature library, with altered-signature and foreign-principal
counterexamples. It is compiled but not executed in this submission. Matching
Native caller checking, `moon info`, formatting and whitespace checks use the
existing bounded non-Heavy worktree guard. Fixed-source commands and receipts are
reported with the PR; preparation results are separate from final clean-source
results.

## Remaining connection

This is an additive trusted installation boundary. The default Remote CLI still
does not install Review/publication/Resume configuration. Its original-principal
custody and live Reviewer registration must be connected through the existing
trusted Host/Cloud owners; a static file or incoming wire must not be described
as a live authority check. Remote CLI changes are coordinated with D and do not
reuse Local issuer authorization for Effect approval.

Actual Native crypto execution, authenticated Native-to-Cloud HTTP, DO/Store
reconstruction, Provider write, public approval, Named Result, formal release,
Preview deployment and formal Cloud cohort adoption remain unverified. Existing
older physical failures and historical Run custody are retained separately.
