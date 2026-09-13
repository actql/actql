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
The selected mode must be snapshot without a checkpoint contract, whether
selected explicitly or by default. A checkpoint on an unselected mode does not
prevent derivation. This check does not require a provider snapshot token.
`pipeline_check_context.program_identity_stage_requests` returns the Stage's
already-owned requests; it does not reconstruct them from equal contents.
It returns `None` for invalid Stage indices or when no SourceView requests were
prepared, including Local-only preparation.

The API accepts no backend, price or placement. Physical candidates implement
the same unit. A native candidate has to preserve admission and demanded failures,
not merely return the same successful rows. A broad read runs residual operations
inside the unit, before capture. The semantic contract is owned by
[Execution](../spec/execution.md#query-acquisition), with closed wire schemas in
[the acquisition contract](../../spec/contracts/actql-query-acquisition.json).

The requirement is static. Its `owner.program_source_cid` uses the authority-bearing
Program Definition, read through `program_identity_definition_cid`, together with
authored stage/input locations. It is not the root-ID-free Program semantics CID,
an object address, internal target index or future Invocation CID. This resolves
the earlier ambiguous phrase “Program source CID”; the Definition and semantics
preimages themselves are unchanged. A consumer that previously substituted the
semantics CID must change its owner and dependent acquisition identities.
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

## Resource selection

Acquisition guards are common to all realizations. Fragment limits belong to
the exact selected fragment, including logical work and logical live roots;
logical does not mean universally selected. The initial filter/select shape
contains no ordered derive and cannot synthesize its `row_kernel_limits`.
This clarifies the existing fragment ownership and measurement contracts.

The explicit realization choice is that a Local-only fragment ceiling is not
promoted into a canonical acquisition guard. Native can succeed when that Local
ceiling alone fails. This fixes a previously unspecified cross-realization
boundary without discounting any limit of an actually selected fragment.
It keeps backend choices out of acquisition identity and consumer budgets.
Native common-guard enforcement requires exact measurements and trusted demand
and full-admission evidence, not Local reevaluation or approximate SQL metrics.
The existing receipt and observation representations remain unchanged.

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

An authorized Host-local adapter may own that validation inside its source engine,
provided it also owns the consistency and execution provenance linking validation
to the query and retention. The shared contract defines that relationship, not a
database-specific connection API. A read-only transaction can implement the read
view; its identity remains private and is not a source snapshot token. Merely
placing an external-provider driver in the Host does not establish this trust.

The initial wire records describe one logical Host receipt. Internal engine
validation plus a native result receipt fits. Exporting the full scan once and
reusing it for residual evaluation fits with broad access. Exporting both a
validation scan and a separate native result does not: it needs a multiple-access
contract before capture, not concatenation or a receipt that hides one read.
Resource accounting still distinguishes both transfers from engine scanning and
retention. This clarifies the existing scope without changing record preimages
or introducing database-specific fields; the strengthened interpretation has its
own updated process-evidence contract pin.

## Two-receipt Host-local specialization

The [two-receipt profile](../spec/execution.md#query-two-receipt) explicitly
represents one exported validation scan and one independently exported native
result. It is a new execution-profile contract, not a widening of the old receipt
scope or a change to canonical acquisition derivation. Both receipt bodies bind
their role, complete typed-wire row content and counts to the same task and
consistent read view. Three execution records reference both receipts; a distinct
observation version references those records and the selected profile contract.
This acyclic structure keeps role-specific access separate from the retained
output even when their row contents coincide.

Issuance follows full Host value admission and query/limit/retention success.
The verifier requires live Host provenance and exact private read-view ownership;
wire identifiers do not authenticate a session. Engine-specific consistency
mechanisms and type conversion implementations stay inside the adapter. Physical
receipt totals count both transfers once, while retention and engine work remain
separate. Existing single-broad receipts remain unchanged. Supporting this
profile requires its selected verifier and adapter implementation; the original
single-receipt verifier cannot silently accept the new observation.
