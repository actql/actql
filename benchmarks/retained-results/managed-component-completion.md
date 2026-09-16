# Managed component completion boundary

Date: 2026-09-16.

The runtime now admits the complete registered managed-profile body under bounded
canonical hashing. A profile-name string or caller-supplied digest does not
select it. The selected pin remains
`sha256:161b405aa85064521a44076212bb266d93f166fa1b383ca8948a87923d797527`.
The generated runtime constant and body fixture are checked against the owned
machine contract by `scripts/managed-runtime-vectors.mjs`, included in the
documentation/contract test suite. Admission of that body is not a declaration
that all required runtime paths are implemented.

`ManagedCompletionPort` requires explicit profile selection, an existing common
completion preparation, an exact final target, and an installed proof-typed
execution verifier. It reuses existing bounded target, retained-output-name and
fixed-input binding validation. Its verifier must validate the actual attempt,
admitted obligations (including any demanded logical identity), guards, authority,
settlement and retained output. The port does not infer those facts from valid
values, a physical digest or availability. Fixed-input Compute supplies its exact
input ports; omission is for an Acquisition verifier with its separate capture
obligations, not permission to skip Compute input checks.

Issuance is single-use. The Core checks live inputs before and after verification,
exact bound output owner/target/schema, live retained material, and cancellation
throughout callbacks. A cancellation or a failed verification cannot be retried
as a success through that port. Equal rows or the same physical representation
do not identify an execution occurrence; each issued completion has a fresh
opaque occurrence identity.

Input provenance stores only bounded binding identities, not input handles.
Independent successfully retained output can remain usable after upstream
release; revocation before completion prevents issuance. This does not allow a
view to drop storage it still physically depends on. Material availability is
distinct from the immutable historical completion metadata.

## Compatibility and integration scope

The output type is `ManagedCompletedOutput`, not the existing `CompletedOutput`.
This is intentional: existing retained-completion descriptors, CID-bearing
Acquisition, ResultArtifact and strategy publication APIs cannot accidentally
accept it. No null/dummy CID or physical digest is supplied to an old wire.

This establishes a common-library **component** completion boundary. It does not
yet connect managed output to `CapturedDAG`, managed consumer dispatch, named
Result publication, an actual DuckDB execution-proof issuer or the Local path.
It does not derive all requirements from a Program or replace the scoped Host
implementation registry. Those integrations must supply the real verifier and
admitted obligations before using the new type; a test verifier is not an
execution proof for a production backend.

The tests use actual checked owners and producer bindings with installed test
verifiers. They cover profile body/budget rejection, unverified and foreign
outputs, cancellation, callback reentrancy, one-use issuance, distinct completed
occurrences, post-verification input revocation and independent output survival.
The existing physical-file integration remains content/retention evidence, not
proof that a live engine reaches this new completion boundary. No performance
ratio or completion of the 1 GiB / 27-case gates is claimed by this increment.

Verification passed: `execution_relation` 420 tests on each of JS, Wasm and
native; documentation/contracts including generated profile-body/pin consistency;
cross-target public interfaces; formatting and whitespace checks. No live
backend completion or new performance benchmark was run for this increment.
