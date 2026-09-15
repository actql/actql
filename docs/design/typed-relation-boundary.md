# Typed Relation semantics and realization boundary

The common Relation lowering retains resolved operations, bound expressions,
input occurrences, schemas and canonical expansion identifiers. Connectors read
these immutable projections to determine eligibility and compile their physical
realizations. They do not traverse `CheckedPipeline` or `CheckedOperation` to
reconstruct meaning. The source checker remains authoritative; checked ownership
is retained internally rather than replaced by content equality.

## Semantic sequence and canonical expansion

`PreparedSequence` contains existing typed values, row and join operations. It is
not a Local evaluator, a whole canonical Plan, or an admitted fragment. Shared
lowering support and a particular connector's execution support are distinct.
Unsupported lowering remains explicit; a successful lowering does not establish
that every connector supports the operation or its required laws.

`sequence_canonical_node_at` relates semantic occurrences to the identifiers used
by wire emission. Group/count includes canonical grouping and NULLS FIRST ordering;
inner join includes its canonical projection. Keyed distinct and ordered take
retain their required prefixes. The serialization and the readonly projection
use the same retained, collision-checked identifiers. Physical fusion cannot
remove an intermediate guard, demand obligation, failure rule or final order.
No runtime JSON serialization/reparse is needed. Existing canonical wire and CID
domains remain unchanged; the projection does not introduce an alternative hash.

Resolved port views preserve repeated inputs, including self-join occurrences.
Host tasks bind these semantic operations to exact input producers and checked
control gates. Tasks and canonical algebra nodes are not interchangeable. Host
ownership checks may retain checked references, but Host helpers must not become
an alternative route for connector-specific semantic derivation.

## Requirements versus Local enforcement

`SequenceRequirements` binds exact fragment requests, occurrence-indexed logical
limits, measurement ceilings and join ceilings without an evaluator or storage.
It is a requirement, not evidence that enforcement ran. Request owners are not
reconstructed from JSON, CIDs or equal numeric limits. Its bounded constructors
validate ownership, duplicate occurrences and selected ceilings.

`FixedComputeCapacity.common_fragment` carries this neutral contract. Local's
`GeneratedSequence` is a separate implementation preparation; Local compares its
actual requests and enforcement configuration with the selected requirements.
Other connectors receive the same contract without constructing Local contexts.
A connector that cannot enforce a selected common budget rejects the candidate
before comparison. It must not reinterpret that budget as Local-only or replace
logical work with SQL elapsed time or memory consumption.

## Completion versus representation

`CompletionPreparation` contains admitted registry contracts, the owned semantic
sequence and selected retained output identifiers. It has no Local runtime
contexts, counters or buffers. Connectors can prepare it directly without Local
registration or `GeneratedSequence`. It does not authorize successful output.

The common trusted completion path still requires exact retained output evidence,
input ownership, the declared final target and live connector verification.
Physical task success additionally requires reservation settlement and atomic
holding attachment. Cancellation is not settlement, and closing an upstream
input does not invalidate an independently completed downstream result.

`CompletedOutput` and `ProducerRead` remain opaque common handoff contracts in
`execution_relation`. Row tables, numeric columns and admitted storage stay
private behind these contracts. Public bindings share completed storage without
re-admission or full copies; layout does not alter logical measurement or
failure frontiers. Package location does not grant a connector access to storage
constructors or mutable evaluator state.

## Scope and verification

This boundary covers the implemented Relation subset and the finite captured
task profile. It does not add Graph/Vector execution, remote Store, durable
publication, new operators or performance guarantees. Full validation-scan
transfer and process-local capture remain constraints of the DuckDB profile.

The backend semantic dependency gate checks connector imports and reader calls,
including renamed aliases, and rejects Local preparation in non-Local/common
APIs. It supplements typed ownership tests rather than providing a plugin
sandbox. Standard Node conformance includes a DuckDB-only Compute registration,
neutral completion construction, checked task execution, result CID verification
and cleanup. Existing independent wire, order, guard and row/column ownership
fixtures remain the semantic regression oracle.
