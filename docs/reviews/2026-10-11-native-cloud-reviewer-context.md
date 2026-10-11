# Scoped original Reviewer context from Cloud

`NativeEffectCloudReviewerRead` installs the existing trusted Cloud TLS/control client, scoped Site credential and independently selected Site/Workspace/installation. Its private endpoint is `effect-resume-reviewer-current`; the old claim reply remains unchanged. An operator, signer or Resume query cannot supply the original HTTP principal.

The retained original Review report and durable typed ACK bind query framing to the dispatch/report/Checkpoint. The query selects only the original claim; framing is not approval admission. Cloud independently selects retained HTTP-principal custody and current Identity/Reviewer facts. The bounded, closed response decoder checks that original challenge, scope, generation and claim using the existing Resume fence. It imports only a raw 32-byte Ed25519 public key into the existing Native PEM verifier; secrets, alternative schemes and extra fields are refused.

`cloud_reviewer_installation` returns the scoped original principal and the existing `NativeEffectReviewerInstallation`. Each verification read performs a fresh challenge-bound HTTP request and compares the full registration against its initial snapshot. `authenticate_remote_reviewer_with_cloud` then invokes the same real Reviewer signature verifier, exact common Resume/report admission and independent Native Host-attestation admission. The existing post-signature callback rereads the same context and original claim. Missing, changed, revoked, expired or replayed context is not permission to send or retry.

This adapter does not install Provider credentials, claim execution, send writes, publish Results or discharge cleanup. The current Site, independent Host keys, Reviewer rights and actual Provider/Effect Owner fences remain required. D's credential-issuer authority is not Reviewer approval authority.

`spec/fixtures/cloud-effect-reviewer-current.json` is the same independent framing vector used by Cloud. Focused white-box tests cover principal/signer separation, raw-key conversion, the original claim, foreign Site/Workspace/installation, lease expiry, replay, duplicate/missing fields, secret extensions and wire bounds. The affected Native consumer is compiled separately. Codec tests and compilation are not physical TLS/crypto/Provider or public Cloud Effect acceptance.

The dependent Native API stack must reach OSS main before formal Cloud package adoption. Actual production holder configuration and the larger approval/restart/Result/release acceptance remain unfinished.
