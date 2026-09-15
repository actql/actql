# Completeness requirements

Completeness is relative to an extent, not a Boolean property of a Carrier.
A complete captured query result need not cover its original source. A row
bound, an empty result, a stable order or successful atomic execution cannot
upgrade partial or unknown source coverage.

## Static dependency boundary

`pipeline_typing.completeness_requirement` returns an opaque requirement for
an exact checked pipeline and target. Input extents, operation results, bounded
queries and window results are distinguished. OperationResult means the result
of that exact operation under its contracts, not the entire external source.
The retained operation supplies its specific request, partition, window or
selection semantics; this scope classification does not replace those rules.

The consumer applies the operation's fixed completeness law to these owned
dependencies; it does not choose a new propagation rule. In particular:

| Checked operation | Required coverage premise | Permitted conclusion after successful validation/execution |
| --- | --- | --- |
| Filter, exact projection, derive, group | Input coverage at its required extent | Preserve that coverage qualification for the operation result; do not promote it to whole-source coverage |
| Join and append | Both operand occurrences complete at their respective required extents | Completeness of this operation result, not of either external source |
| Semi/anti join, except/intersect | Both operand occurrences, including the membership-testing side | Right-side coverage remains necessary even though right values are not output |
| Take/top-k | Selected bounded-query coverage and the retained input requirements | Only the bounded result extent; never infer that its source was exhausted |
| Window/window-group | The selected window extent and its operation-specific coverage/validation requirements | Only that window result; neither a boundary column nor finite row count closes source coverage |

For the two-input premise, complete/complete may establish result completeness;
complete/partial and complete/unknown do not. A separately admitted complete
query result can satisfy a query extent while the larger source stays partial
or unknown. These cases are not contradictory: the extent and owner must match
before using any claim. An empty anti result, an unused projected column, or a
repeated producer edge does not remove a required premise. Failed validation or
an atomic limit breach yields no successful result-completeness conclusion.

In 0.1, formal check constructs this static, owner-bound requirement view and
binds the existing execution checks. It does not combine future observations
into a completed-coverage flag. Observation admission and execution apply the
above existing laws at their established boundaries. This is a division of
validation phases, not delegation of language semantics to the lowerer.
`WindowResult` is the window-qualified form of an operation extent, rather than
an extra whole-source completeness guarantee.

Indexed readers expose the existing typed operand occurrences without copying
or recursively expanding a dependency tree. Filter, projection and derive keep
their input dependency. Join, append and set operations retain both operands;
anti/except never discard the right-side coverage dependency merely because
right-side values do not appear in output. Repeated occurrences retain their
roles. A consumer walking the graph must charge its existing shared traversal
budget; constant-time reads themselves do not certify a completed traversal.

ProducedInput carries the dependency through its immutable producer pipeline
and target. Result projection remains attached to the import edge, so hiding
columns does not erase membership or source dependencies. Internal pipeline
ownership and target indices are not persistent Unit identities.
`program_check.unit_completeness_requirement` pairs a requirement with the
already checked Unit Definition CID. It derives both from the same immutable
Program; callers do not supply an independent identity or reconstructed pipeline.
The returned pair is a static read view, not a new serialized evidence preimage.

## Observation and closure

These requirements are conditional static information, never completed
observations. A leaf with no operand dependency is not automatically complete:
an input still needs its selected source/request and coverage, while a generator
still needs its own execution and validation obligations. A bounded-query
requirement retains its original input dependency; satisfying the bounded
output extent does not satisfy the larger source extent.

Existing Local snapshot materialization, Query Acquisition capture coverage,
lookup response coverage and operation execution checks retain their current
owners and validation responsibilities. No alternative wire proof, completion
flag or duplicate runtime checker is introduced here. Program closure binds
selected source contracts, required enforcement and persistent Unit subjects
statically. Admission of observations remains at the existing runtime boundary,
before the dependent use or publication, not a prerequisite that static check
must execute acquisition. The static view cannot by itself claim observed
completeness, authorize publication, or discharge
`RetainIdentityAndCompleteness` on its own. Unknown and partial observations
remain unknown and partial even when their row count is below a selected cap.

Formal check constructs one input-binding table, including unused inputs,
before returning CheckedProgram. Each input binds exactly one existing Local
admission subject, selected SourceView CarrierResponse check, or Result import
interface and producer. Missing or conflicting bindings fail construction.
Source selection uses the authored input name, not a Catalog contract name or
the position in a separate request list. Import bindings verify the producer's
checked pipeline and Unit CID together. Construction charges the shared work
budget; `unit_input_completeness` then reads the retained table in constant time.
The selected checks keep their original execution phase, prerequisites and
failure behavior. This closes static input ownership, not observation coverage
admission: a selected snapshot declaration or response contract is not evidence
that acquisition completed successfully.

Local input subjects retain their exact optional EnvironmentSnapshot, selected
by resolved stage/input reference rather than array position. Snapshot absence
and schema-only snapshots carry no materialization claim. A supplied complete
or partial claim stays attached to its input CID and environment member; neither
schema agreement nor successful static construction discharges it. It remains
available through Result-import dependencies after a bounded selection, without
being promoted to whole-source completeness. These observation claims are not
included in the Unit's static type projection or meaning identity.

This boundary preserves the existing semantic rules. In particular, atomic
bound failure remains failure, not successful truncation, and source coverage
is never inferred from physical enumeration order.
