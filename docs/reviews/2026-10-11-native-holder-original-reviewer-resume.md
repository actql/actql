# Native holder Resume with the original Reviewer

The holder's Resume consumer now constructs authentication from the scoped
Cloud private Reviewer read. It no longer accepts a precomputed Reviewer
authentication through its installation callback. The same original Review,
report, durable ACK, dispatch and Resume claim enter the existing Native
signature verifier, Host admission and approved-row Owner.

The operator installation supplies the existing signature library, independent
Host keys, current authority, Provider access, bounds and trusted Site/workspace/
installation scope. The original HTTP principal and Reviewer verification key
come from Cloud custody through the authenticated control channel. They are not
selected from the signer, Site operator or a proposed delivery.

Both control URLs are derived from the configured HTTPS observations endpoint.
The old claim/current reply is unchanged. The separate private Reviewer read
uses the same Site credential and current Site fence. Both reads share the
holder's fresh challenge sequence. Every row authorization fence rereads the
original Reviewer registration and claim, and checks Site and current authority
before and after the read. Missing or changed context does not authorize a send.

The approved-row, Ledger, saved-response, unknown-result, publication and cleanup
Owners remain unchanged. The supplied claim observer always replaces the
configuration placeholder before the row Owner is called. No synthetic current
observation, approval, Provider success or new recovery decision is introduced.

## Scope and evidence

This connects the library and holder callback consumer. The production holder
entry point still needs independently installed Review policy, publication,
Provider access and Resume configuration. Its default absence continues to
preserve pending responsibility. This change is not production installation or
public Effect acceptance.

Focused JS tests cover current-role or Site loss before the read, context/role/
Site loss during the read, and fresh reads after context becomes unavailable.
These authored authority ports are fence tests, not actual HTTP, cryptographic
or Provider acceptance. Matching Native holder compilation checks the real
callback consumer and both control URL paths. Actual Native crypto, Cloud DO,
approval, Provider write, Result and formal release remain separate acceptance.

The child depends on the private Reviewer adapter in OSS #1444 and the unchanged
claim adapter below it. Cloud #267 supplies the private route and uses the
merged #266 caller-floor helper. The final merge target is OSS main after the
parents, and formal Cloud adoption must use a merged OSS source cohort.
