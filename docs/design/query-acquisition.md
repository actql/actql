# Query-shaped acquisition

The initial boundary is an exclusive finite Relation source read followed by one
filter and one select. The canonical unit ends after select, before downstream
consumers. A source or filter output shared outside this chain needs a separate
derivation rule and is not accepted by this entry. This is bounded implementation
support, not a restriction on authored Programs.

`sourceview_resolution.derive_query_acquisition` consumes owned `PipelineRequests`.
Those retain the exact checked pipeline, selected SourceView and bound Parameters.
Its opaque result exposes the source slot, input target, filter occurrence,
checked filter/select operations and completed output target. Existing operation
readers expose expression demand and pending obligations; these are not discharged
by derivation. Source mode, authority, policy, capacity and runtime support remain
requirements. Unbound Host request bindings are outside this initial entry.

The API accepts no backend, price or placement. Physical candidates implement
the same unit. A native candidate has to preserve admission and demanded failures,
not merely return the same successful rows. A broad read runs residual operations
inside the unit, before capture. The semantic contract is owned by
[Execution](../spec/execution.md#query-acquisition), with closed wire schemas in
[the acquisition contract](../../spec/contracts/actql-query-acquisition.json).

The requirement is static. Its owner uses source identity and authored stage/input
locations, not an object address, internal target index or future Invocation CID.
In-process handles enforce ownership separately. Completion evidence binds the
requirement to the actual access and retained output; its CID cannot authenticate
the facts it claims. The Host must verify execution evidence before admitting it.

Process retention is a deliberately narrow additional execution boundary. It
does not satisfy durable Run, recovery, checkpoint or numeric-observation capture
contracts. This allows the initial consumer experiment without inventing a future
observation identity or weakening durable capture requirements.

The source-wide admission rule is made explicit for this execution profile:
known fields throughout the selected scan are checked before its filter, even
when physical pushdown hides them from the Host. This preserves existing full-row
admission rather than optimizing away invalid unused fields. A provider unable to
attest that behavior needs a broad read; an unsupported backend is not repaired
by attaching a coverage claim. It does not imply scanning unrelated source data
outside the selected request.

Aggregate absorption, shared scans, brought-in captured inputs, changes feeds,
prefix demand, take and checkpoints are separate contracts. The entry is not a
replacement for `program_check.check` or a runnable-plan constructor.
