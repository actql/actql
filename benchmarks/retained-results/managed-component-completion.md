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

The common-library managed input binding now connects a completed managed output
to a checked receiver and can supply that exact use-site to another managed
completion. `ManagedProducerRead` checks the expected bound producer invocation,
checked producer target, and bounded projection metadata. Projection, rename and
exact column copies reference admitted logical-schema ordinals, not backend
physical column slots. It does not read cells, construct a legacy row CID, or
claim a changed view has the original result identity. Separate receiving
bindings remain distinct even when they share one output occurrence.

Completion preparation snapshots the managed input array and checks the complete
receiving-port set and profile. Input liveness is checked before and after the
installed execution verifier; the completed output retains only historical
use-site identities. An independent downstream holding can therefore survive
upstream release. Legacy and managed input arrays cannot be partially mixed to
bypass a missing receiving port. Mixed-family dispatch is not implemented yet.

This was initially a common-library **component** boundary. The later
[managed graph publication](managed-graph-publication.md) connects an actual
acquisition-fed DuckDB strategy task to `CapturedDAG` without a legacy output.
Managed consumer dispatch, named Result publication and the Local path remain
open.
It does not derive all requirements from a Program or replace the scoped Host
implementation registry. Those integrations must supply the real verifier and
admitted obligations before using the new type; a test verifier is not an
execution proof for a production backend.

Availability and material lookup are not pin acquisition or use authorization.
Store/Host admission, logical guard measurement and scoped backend evidence
issuance remain necessary before dispatch. The generic payload is currently
shared by input and output material types at this component boundary; this is
not a promise of arbitrary representation conversion.

The tests use actual checked owners and producer bindings with installed test
verifiers. They cover profile body/budget rejection, unverified and foreign
outputs, cancellation, callback reentrancy, one-use issuance, distinct completed
occurrences, post-verification input revocation and independent output survival.
The existing physical-file integration remains content/retention evidence, not
proof that a live engine reaches this new completion boundary. No performance
ratio or completion of the 1 GiB / 27-case gates is claimed by this increment.

Managed input tests additionally cover two admitted rows, checked projection,
rename, repeated column copies and reordered source-column correspondence;
foreign parameter bindings, targets and metadata limits; distinct use-sites;
preparation snapshots; and revocation during verification. The chain test uses
an installed test verifier, not proof of executing a backend transformation.

Earlier completion verification passed: `execution_relation` 420 tests on each of JS, Wasm and
native; documentation/contracts including generated profile-body/pin consistency;
cross-target public interfaces; formatting and whitespace checks. No live
backend completion or new performance benchmark was run for this increment.

Managed input binding verification: `execution_relation` 423 tests on each of
JS, Wasm and native; cross-target public interfaces; full `npm run check:docs`;
formatting and whitespace checks. The frontend semantic-boundary gate remains
unchanged: both input families call the existing ownership boundary, rather than
granting a new frontend-traversal exception to the managed reader.

The subsequent [managed input measurement increment](managed-input-measurement.md)
adds reusable per-column quantities and a shared input/output ledger. It does not
yet supply the backend execution verifier or consumer dispatch described above.
