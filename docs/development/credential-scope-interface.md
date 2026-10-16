# Credential interface references

This index projects the existing Remote Credential Owner; it adds neither a
permission rule nor a grant schema. Original invocation equality and current
per-operation authorization have distinct responsibilities. The generated
subject keys replace the previous adapter list in its original order. Operation,
expiry, quota and grant CID retain their separate existing Owner checks.

| Attribute | Existing authority and executable reference |
| --- | --- |
| Responsibility | `src/remote_credential/credential.mbt`: `prepare_credential_use`, `authorize_credential_use`; `adapters/host-common/owned-invocation-context.mjs`: `invocationBindingsMatch` |
| Inputs/outputs | `src/remote_credential/credential.mbt`: `RemoteCredentialGrant`; `scripts/generate-credential-scope-binding.mjs`: `credentialInvocationFields` |
| Identity | `src/remote_credential/credential.mbt`: `grant_cid`; `adapters/host-common/remote-credential-control.test.mjs`: `Remote Credential use admits only the exact active scope` |
| Ownership | `adapters/host-common/owned-invocation-context.mjs`: `ownInvocationContext`; `adapters/site-node/sqlite-credential-journal.mjs`: `claim` |
| Synchronization | `adapters/site-node/https-credential-resource.mjs`: `journal.authorize`; `adapters/site-node/https-credential-resource.test.mjs`: `revocation during secret resolution` |
| Failure | `adapters/site-node/sqlite-credential-journal.mjs`: `finish`; `adapters/host-common/sqlite-transaction.mjs`: `unknown`; `adapters/site-node/sqlite-credential-journal.test.mjs` |
| Cancellation | `adapters/site-node/https-credential-resource.mjs`: `signal`; `adapters/site-node/https-credential-resource.mjs`: `signal?.throwIfAborted` |
| Resources | `adapters/site-node/https-credential-resource.mjs`: `maxResponseBytes`; `adapters/site-node/sqlite-credential-journal.mjs`: `close` |
| Extension | `scripts/generate-credential-scope-binding.mjs`: `checkCredentialScopeBinding`; `packages/local-node/package.json`: `prepack`; `scripts/local-node-package-inputs.mjs` |
| Verification | `scripts/generate-credential-scope-binding.test.mjs`; `scripts/credential-final-fence-mutation.test.mjs`; `adapters/host-common/remote-credential-control.test.mjs`; `adapters/site-node/https-credential-resource.test.mjs` |

The generator reads the actual Owner declaration and refuses unsupported field
shapes. Adding a subject field or dropping a generated comparison invalidates
the independent freshness checks. The runtime scope negatives use the compiled
credential Owner, rather than replacing its decision with the projection.
The post-await revocation test uses the real credential journal and a local TLS
server; removing the final authorization must fail its no-request assertion.

A referenced test is not an execution receipt. Compiled runtime source, adapter
source, toolchain, actual counts and mutation results retain their individual
qualifications. No new compiled runtime, installed public product acceptance,
Provider service operation, or numerical profile is established by this index.
