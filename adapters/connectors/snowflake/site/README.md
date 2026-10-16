# Snowflake key-pair material

The SQL API accepts a signed RSA JWT as provider authentication. This module
supplies only that bearer material to the existing Credential Site. It never
issues a credential grant, dispatch use, Run, source capture or retry.

## Interface responsibilities

- Responsibility: resolve the selected provider RSA key and construct SQL API
  authentication within the original installed Credential Site.
- Inputs and outputs: a closed public issuer/environment selection and the
  existing secret byte ceiling produce a token resolver and local cache close.
  PEM and optional passphrase values are read only when the Site claims a use.
- Identity: issuer account/user and environment-variable names remain in the
  original installed identity. JWT issuer spelling uses uppercase account/user
  and replaces account-name periods with hyphens; the account identifier must
  exclude locator region/domain information. It is never inferred from a URL.
  The fingerprint is SHA256 of the public key's DER SubjectPublicKeyInfo bytes.
- Ownership: the original Credential Site owns this one bounded token cache.
  It clears cache references only after that same Site's close succeeds.
  The original HTTPS acquisition binding retains its actual in-flight token;
  closing a cache is not proof of cryptographic-memory zeroization or Provider
  termination. No per-Run material registry is created.
- Synchronization: each use resolves and validates the current key even on a
  cache hit. An unchanged, unexpired key returns the original cached token.
  Rotation/expiry produces different material; the existing HTTPS binding
  refuses to swap it during an original acquisition. No request is retried.
- Failure: malformed, missing, over-limit, undersized/non-RSA or incorrectly
  decrypted material refuses without a stock token/key fallback. Crypto errors
  expose a named refusal, not PEM/passphrase contents. Failed Site close keeps
  the same Site and cache responsibility for its existing cleanup procedure.
- Cancellation: abort and local close are checked before and after asynchronous
  material resolution. Cache close is idempotent and does not restart a lookup,
  grant a send, cancel a remote statement or settle an uncertain operation.
- Resources: the selected `maxSecretBytes` bounds the input PEM, passphrase and
  output token individually. This is not an accounting claim for their sum,
  native crypto scratch or the process; normal numerical funding remains absent.
  Only one token/fingerprint/time tuple is retained. No whole-VM supplier or
  new quota/Ledger is introduced.
- Extension: installed profiles choose either the existing token environment or
  explicit key-pair material. These selections cannot be combined. The grant
  authority's Ed25519 private key is a separate original and is never used as
  the provider RSA key. The ordinary adapter source graph follows the import.
- Verification: independent public-key JWT verification, encrypted-key handling,
  exact issuer/expiry, current rotation, bounded/refused inputs and close/abort
  counters accompany actual isolated Host/Account/SQLite/TLS/RowRun cases.
  Those tests are not live Snowflake or a normally installed release acceptance.

Provider requirements:
[SQL API authentication](https://docs.snowflake.com/en/developer-guide/sql-api/authenticating)
and [key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth).
The token uses RS256 and a 59-minute lifetime, within the provider's one-hour
maximum. This credential expiration is independent of Account grants, Result
retention, Run availability, request identity and cleanup responsibilities.
