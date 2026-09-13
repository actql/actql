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

## Process evidence trust boundary

The initial [process-evidence profile](../spec/execution.md#query-process-evidence)
uses a Host-authorized private issuer and live immutable completion handles. Shared
record preimages bind all three validation roles to one requirement, execution
attempt, source scope, access and retained output. Their hashes name records;
they do not authenticate them. Capture admission is responsible for checking live
provenance and exact task ownership. Rehydration from JSON is outside this profile.

This is an explicit specialization of the previously abstract execution-evidence
references, not an assertion that the earlier label-hash fixtures established
authenticity. The original acquisition contract and its pins remain unchanged;
the process-evidence contract pins that dependency separately. Host-private code
implements issuance and admission, while the shared schema fixes the identity
representation and the normative rules fix the trust boundary.

Source order is independently unresolved by those earlier fixture labels. This
profile uses null, preserving input-relative order without manufacturing a total
order witness. Non-null order requirements need a different supported evidence
profile. Native execution still needs full selected-scan validation provenance;
receiving fewer rows or fields is not a reason to omit their required checks.
