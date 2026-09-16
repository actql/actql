# Physical result identity and completion: contract review

This records the agreed Q1–Q11 design, not a registered execution profile or
permission to omit fields required by current contracts. It reviews the contracts at main
`3820ea1119997ba6194905e0336c11f472e6dd96`. No profile identifier, wire shape or
pin is assigned here. The direction is physical files/chunks plus a manifest
for stored results, with logical content identity requested separately. These
contracts apply equally to one row, two rows and large inputs; size affects
physical placement and cost, not required guarantees.

## 1. Three different claims

| Claim | Evidence | What it does not establish |
| --- | --- | --- |
| These bytes are the sealed representation | Digest of exact stored bytes, ordered manifest, verified storage binding | Correct execution, authorization, or equality across encodings |
| This representation is this completed result | Admitted execution and conversion evidence, exact owner/attempt/input/output binding, immutable generation and holding | Equality with an independently produced logical result |
| These differently encoded results have equal logical content | The required existing domain-specific logical CID, or another separately admitted equality proof | Same attempt, access history, authority or current availability |

The current row-array hash is already a whole-content hash, not a CID per row.
The proposed change is the hashed representation, not merely the hashing batch
size. File bytes need not be decoded into canonical rows to obtain their digest.
Changing compression, partitioning or encoding may change physical identity
without changing the logical result. Physical identity is not backend-independent.

## 2. Ordinary execution contract

Completion establishes successful execution, discharged semantic obligations,
and an exact immutable retained result. Content hashing is not a substitute for
any of those checks. Completion records bind the Run, Program owner, requirement,
Parameter bindings, producer, attempt, input bindings and output target, plus
schema, logical order, validation scope/contract, measurements and holding.

For persisted or transferred results, use sealed physical files/chunks
and their manifest as the normal representation. A directly reusable managed
resident table or Local memory result need not be exported merely to obtain a
physical hash. It instead needs an admitted immutable-generation binding and
the promised holding lifetime. If it cannot survive the producer's teardown
but independent holding is required, it must be exported before completion.

Logical CID is computed only when the applicable contract or consumer requires
it; otherwise it need never be computed. This applies to acquisition receipt
contents as well as final output, not just internal task outputs. A CID-free
managed result is not an existing ResultArtifact or completed Invocation.

Known requirements are propagated before execution and before discarding any
required receipt. Host policy and applicable language/execution contracts set
the minimum obligations; the planner compares only candidates that satisfy
them. Users do not select a collection of validation-disabling switches.

## 3. Physical manifest responsibilities

The new physical manifest is distinct from the existing name-to-ResultArtifact
ResultManifest. Its descriptor needs the following closed, bounded information:

- Representation contract and format/codec version, logical schema identity,
  physical-to-logical field mapping and decoding/ordering contract.
- An ordered sequence of chunk occurrences, each binding ordinal, exact byte
  length and digest. Repeated chunks remain repeated occurrences, not a set.
- Exact logical row count and an unambiguous reconstruction rule for order and
  multiplicity. Physical read order is not presumed to be logical order.
- A domain-separated identity of the complete canonical metadata body, excluding
  its own digest. Metadata canonicalization does not canonicalize the row payload.

Empty results have an explicit schema, zero row count and a valid empty chunk
sequence. Metadata size, chunk count and descriptor depth are bounded. A future
paged manifest must authenticate page order and totals; it is not implicitly
supported by an unbounded chunk list.

Chunk ordinals are contiguous and unique; repeated digests at different
ordinals are allowed. Missing chunks, changed order, unexpected byte lengths,
unsupported decoder contracts and inconsistent row counts reject admission.
Storage locations and credentials are resolved separately and do not grant
authority. Completion evidence binds the exact manifest and owned storage;
hashing a caller-supplied manifest does not authenticate its claims.

Write, hash and seal can share a bounded byte stream. Publication requires all
chunks and metadata to be sealed, required validation/conversion to succeed,
and promised holding to be secured. Partial uploads and provisional tables
are not completed results. Cleanup and reservation settlement remain separate
from flush, transaction commit and logical completion.

## 4. Trust, reuse and conversion

Initial scope is one managed Run, including existing admitted local execution
process delegation. Receiving admission checks delegate, session/channel,
request/attempt, material generation and authority. A serialized handle, path,
inode, digest or Run ID alone is insufficient. Arbitrary remote authentication,
cross-Run evidence reuse and restart reconstruction are not covered.

Reuse is allowed only while the actual immutable-generation guarantee holds.
All mutation paths must be controlled; a filename plus an earlier successful
hash is not an immutable file. New storage/transfers require their own integrity
admission unless existing verified custody explicitly covers them. Physical
hashes detect mismatch against a trusted expected digest, not malicious
replacement of both the payload and its untrusted descriptor.

Conversion from resident data to a file, or between formats, must establish the
same typed values, NULLs, precision, field mapping, order and multiplicity.
Verification can be integrated into conversion; a separate full scan is not
intrinsically required. SQL success or a matching physical digest cannot prove
that conversion. Unsupported cases remain ineligible before execution; failure
after execution begins follows existing failure/cleanup rules, not auto-retry.

Consumer-specific demand, guards, authority, lifetime checks and logical charges
remain. Reusable evidence must cover the exact quantity, contract and scope:
an exact row count can discharge a row ceiling, but not predicate evaluation or
join-key constraints. Planning estimates never become validation evidence.

## 5. Measurements without mandatory row reconstruction

Keep semantic canonical UTF-8 per-value bounds where applicable. In particular,
`actql-fixed-compute-capacity/0.1` bounds top-level input values, demanded context
values, evaluated roots and output values; it does not universally require
serializing a complete canonical row array.

Use exact reusable measurements or a verified equivalent size calculation when
they preserve the bound and failure rules. A new or changed value may need new
measurement. Do not replace semantic bytes with compressed file size, or call
canonical size calculation free because hashing was removed.

Physical memory reservations cover simultaneously live representations, engine
and transport buffers and metadata. Storage and transfer use their respective
physical quantities. Logical consumer charging remains per consumer even when
the measured evidence is reused. Existing receipt profiles that require exact
canonical array bytes retain that obligation; a new physical receipt must name
its different quantity explicitly, not reinterpret the old field.

## 6. Existing features and compatibility boundaries

| Boundary | Existing dependency | Proposed handling |
| --- | --- | --- |
| Internal Compute / managed Result read | Exact completion, schema/order, input and holding bindings | New managed representation contract; no unconditional logical CID |
| Query acquisition | `received_rows_cid` in access scope; `output.rows_cid`; observation and evidence preimages | Separate new observation/receipt contracts preserving actual access, snapshot, coverage and role; do not null old fields |
| ResultArtifact and ResultManifest | `logical_result_cid`, Invocation and provenance references | Preserve existing closed shapes and preimages; bridge only with all required evidence |
| Result delivery | Exact artifact, authorization/egress, logical verification and canonical delivery bytes | Existing delivery unchanged; physical-manifest read is not implicitly this protocol |
| Captured Run, replay, local semantic projection | Exact observation set, Result artifacts, authenticated reference graph | No physical-root substitution; require the existing dependency closure |
| Effect preview / approval / apply | Captured Run, local projections and their attestation, policy and current authority | Preserve existing boundaries; establish required identities before preview |
| Logical deduplication / cross-representation caching | Logical content equivalence plus applicable authority and provenance | Not enabled by physical digest equality |

These dependencies are in [execution](../spec/execution.md#capture-and-replay),
[query acquisition](../spec/execution.md#query-acquisition) and
[artifacts](../spec/protocols/artifacts.md#result-artifacts).
Plan identity, source/Parameter identity, genuine Ref identity, Effect row
identities and canonical value semantics are not replaced by file hashes.

Thus the design preserves the existing features by supporting both contracts,
not by pretending the lighter contract provides every existing capability.
Programs with known legacy publication, replay or Effect requirements retain
the necessary identities and evidence from the start. Their performance gain
may come only from representation and evidence reuse, not CID omission.

## 7. Additional identity and lifetime

Track identity establishment separately from availability of the exact material
needed to compute it. Different domains, such as received rows and Relation
result, retain their different preimages. A discarded validation scan cannot be
reconstructed from final output or by rereading the source. A known downstream
requirement therefore forces prior computation/holding or pre-execution refusal.

Unknown future requests undergo additional admission of material, authority,
implementation, holding and budgets. Ordinary failure/cancellation does not
undo prior completion; detected corruption or binding mismatch blocks further
use of the affected representation and reports a holding failure. Partial
identity calculation is not published. Material expiry does not invalidate an
already established digest, but does prevent using it as current read authority.

## 8. Required contract and implementation follow-through

The current retained material still requires an `AdmittedOutputStreamReceipt`.
Node completion custody and the process observer require physical file digest
and bytes to equal the canonical row receipt. Those are concrete integration
points to replace with verified representation binding, not comparisons to
delete without replacement.

Before registering a profile, specify together: managed completion/observation,
physical manifest and conversion admission, Result read authority, identity
capabilities, measurement laws and the legacy dependency-closure bridge. Define
closed wire shapes only for data that actually crosses a boundary; never treat
a schema-valid record as owned execution evidence. Register normative exceptions,
machine contracts, dependency pins and independent fixtures together. The old
contract bodies/preimages are not silently relaxed.

Fixtures must cover empty results; repeated/reordered/missing chunks; corrupt
payload and metadata; equal bytes with foreign owner/attempt; mutation/generation
change; loss of holding; incorrect type/order conversion; exact measurement
reuse with per-consumer charging; late identity success/failure; discarded
receipt refusal; and legacy Effect/publication requirements discovered before
execution. Local and delegated DuckDB must share the boundary.

Performance evidence must count avoided row reconstruction, canonical encoding,
hashing and reimport, not just hash API calls. Include first preparation, physical
hashing, manifests, independent holding and cleanup. Preserve the registered
1 GiB / 27-case obligations and thresholds. New-contract measurements are separate
from old-contract paired comparisons; neither new conformance nor a smaller
hash count establishes performance acceptance.

## 9. Agreed evidence and implementation boundaries (Q1–Q11)

Q1: Success means all obligations admitted for this execution are satisfied,
including requested capabilities, not merely that the result is readable.
Unrequested future conversion is not promised. Audit records, rereading retained
output, replaying a suffix, replaying original acquisition and legacy artifact
export are different capabilities. An Effect is eligible when its particular
evidence contract is satisfied; this is not a blanket ban on Effects.

Q2: Initial acceptance combines a limited formal model, independent conformance
and fault tests, and a declared trusted implementation boundary. Do not claim a
new representation is covered by an existing mechanized theorem without its
assumptions and a checked bridge where needed. AoA canonical equality does not
mandate eagerly constructing canonical data, but Smooth's row-CID tie breaking,
CID selectors and strict materialized-row claims cannot be replaced by a file
digest. Semantic equality, including demanded failure behavior, is the basis
of correspondence, not an assumed converse of `cid_sound`.

Q3: Detecting a violation and selecting the reportable failure are separate.
Preserve specified phase/demand, precedence, logical position and atomicity,
not incidental physical discovery order. A maximum-size summary can establish
success under a compatible ceiling; its maximum's position does not necessarily
locate the first violation under a smaller ceiling. Inspect what is missing
before reporting. Do not inspect undemanded expressions or use expired authority
to obtain a preferred diagnostic. Unspecified ordering is not an implementation
license: record the permitted diagnostic outcomes explicitly.

Q4/Q6: Rules are finite and composition follows the actual checked transformation
DAG with bounded work and storage, not general proof search. Initial support
includes exact-view reuse, projection/rename/exact column copy, the exact row
correspondence produced by supported filter/take/sort, and unchanged or copied
derive columns. New values require their own validation and measurement.
Predicate execution, order and required CID tie breaks are not skipped.
Join/group need not derive all properties from inputs, but their newly validated
results must become reusable by multiple consumers. Preserve evidence by kind:
projection does not preserve a whole-row CID, dropping part of a composite key
does not establish uniqueness of the remaining key, and filtering does not
preserve exact row count or the input sequence's identity.

Q5/Q8: Acquire generation-specific pin, current use authority and resources
before dispatch, atomically with respect to reclamation (or by provisional
acquisition and final validation). Managed local process delegation, multiple
consumers, individual release, ordinary timeout/cancellation and confirmed
cleanup are required. Availability periods, authority expiry and hard deletion
deadlines are distinct. Renewable leases are allowed, not an initial service
requirement. Reject candidates unable to meet a requested strict stop/deletion
deadline; ordinary timeout is not such a guarantee. Late responses cannot revive
revoked attempts. Run teardown must respect promised Result holding duration.

Q7: Known obligations and allowed fallback are set before execution; concrete
reuse admission may occur after a producer completes and before its consumer
starts. No rule, insufficient evidence or the reuse-search sublimit can lead to
ordinary validation using remaining resources. Exhausting a global hard budget,
detecting corruption, authority loss or a real guard breach cannot be reset or
hidden as an optimization miss. No post-start silent backend retry is allowed.

Q9: Initial implication rules cover identical contracts, NULL allowance,
registered numeric-domain intervals, identically defined size/count ceilings
and the supported view transformations. No arbitrary predicate implication or
implicit conversion is introduced. Insufficient evidence is unknown, not a
violation. Universal success transfers to an exact subset; a violation somewhere
in the whole input does not establish a violation in that subset. The consumer's
input scope is fixed before its own filter, not replaced by its eventual output.

Q10: Reference composition, copying and supported export are physical choices.
They preserve values, order, multiplicity and admitted capabilities. Copying
creates new generation-bound evidence through a verified preservation rule,
not mutation of the old evidence's material ID. Establish and retain the new
copy before releasing source pins; include the overlap in peak reservations.
Retain provenance without retaining every ancestor buffer or liveness callback.
On cancellation or failure keep the original valid result and account for
provisional cleanup. A planned relocation is not re-execution of the computation.

Q11: Host adoption binds implementation revision, contract, supported evidence
kinds/rules, representations and conditions. Preparation grants task/attempt-
and subject-limited issuance capability; Program data cannot grant authority.
Core checks bindings and allowed conclusions; the adopted implementation is
trusted for the actual content operation and is tested independently. This is
not a sandbox or proof that native code is honest. Fixed registration and
existing managed delegation suffice; no PKI or exclusive certification service
is required. Third-party implementations of registered rules must not require
backend-specific Core branches.

The implementation acceptance paths are: acquisition through projection,
filter, derive, sort/take and multiple consumers; join/group results used at
least twice; and managed process execution through use/cancellation/reclamation.
Include sufficient-resource successful cases as well as rejection cases.
Contract registration, runtime conformance and performance acceptance are
separate claims. Existing-contract duplicate-work removal precedes, but does not
replace, implementation and separate measurement of the new profile.
