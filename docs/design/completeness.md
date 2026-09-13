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
flag or duplicate runtime checker is introduced here. Joining this static view
to selected source contracts, admitted observations and persistent Unit subjects
belongs to Program closure. Until that join is validated, the view cannot be
used to claim observed completeness, authorize publication, or discharge
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

This boundary preserves the existing semantic rules. In particular, atomic
bound failure remains failure, not successful truncation, and source coverage
is never inferred from physical enumeration order.
