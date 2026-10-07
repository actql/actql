# Resumable retained output-port preparation

## Integration and completion boundary

This unit follows the public ordered-binding connection in #744 at
`2c65fd65b341e0d6edb61f7678356465abddfb39`. Main
`0f3ce2083bbdfca6a5f7de6eb34f8dfb8157d88b` was normally merged without
conflicts. Current Graph definitions, contracts and identities remain the
only production authority. #744 was an unmerged parent at the start.
Before publication, #744 reached main at
`98718f21f6e8c0993189ccde098ed66fa455e54c`; that main was normally merged
without conflicts. No parent dependency remains. The execution Relation,
Local connector and selected chain evidence sources are unchanged by this
second merge. The newer Host/SDK connection is checked on the final source,
separately from the earlier JS receipt.

The existing bounded Relation driver already resumes expression, row-name
and sort metadata work. However, its start function called
`prepare_trusted_output_port_with_inputs`, which synchronously traversed every
output name and both retained-target identity spellings before the first
resume. Moving only subsequent row copying into a bounded phase did not
make that admission interruptible.

An initial regression with a long output spelling and an insufficient name
budget failed inside start, before a resume could observe that boundary
(`run-dgGamm`, `focused-test-ZQQpK2`, 0/1). This demonstrates the synchronous
admission boundary, not a measured public cancellation delay or an erroneous
published Result.

## Existing owner connection

`trusted_output.mbt` now separates exact input/target admission from name
validation. The private `TrustedOutputPreparation` borrows the immutable
schema and advances through target bytes, retained-target bytes, exact UTF-16
identity comparison and canonical field names. Each transition examines at
most one Unicode scalar or one identity code unit. Entry and UTF-8 byte
limits remain finite; no normalization is applied.

`BoundedBindingRowsState.PrepareCompletionPort` drives this cursor through the
existing bounded session before any row evaluation. The existing stop and
input-availability checks execute between transitions. The ordinary trusted
completion APIs use the same validation, with their existing synchronous
calling convention; this is not a new public execution profile or fallback.

Only finished preparation can construct the private completion port. Partial
or cancelled preparation cannot issue completion evidence. On failure or
stop, the existing cleanup owner drops pending name references once and keeps
borrowed inputs available. On success, the exact name array transfers to the
port without copying. Later cleanup cannot clear that completed array. The
verifier captures only the existing live/rows Refs, not the enclosing state,
avoiding a state-to-port closure cycle.

This adds physical resume steps, not logical expression/value work. The
selected-take fixture independently derives 29 additional transitions:
16 name scalars (`limit_0` twice, `n`, `s`), seven identity units and six
phase/finish transitions. Its physical total changes from 61 to 90; its
logical exact/one-short control limits remain 49/48. No budget is rounded,
reset or increased to hide a refusal.

## Independent evidence and publication

The output name fixture uses `derive_0` twice, `id`, `next` and a 256-byte
ASCII spelling: 278 UTF-8 bytes. One-short is 277. Adding an emoji requires
282 bytes, not a UTF-16 length substitute. Tests fix the published cells
`id=1`, `next=2`, source value `7`, canonical column order, quanta 1/7/256,
unchanged cumulative logical charges and workspace peak. Separate stops
inside each preparation phase preserve borrowed inputs until cleanup and
verify single reclamation and no completion. Partial/closed cursor issuance
is rejected.

Focused working-tree JS validation passed 105/105 (`run-Y3PgWz`,
`focused-test-3MRnsN`), covering the new cases and existing bounded binding,
order metadata, exact input binding, Carrier trusted completion, retained
readmission and borrowed-binding callers. Two earlier diagnostics found
new-fixture mistakes: the lowered target is `derive_0`, not its authored
alias, and poll work is cumulative. The corrected byte/transition quantities
above are derived from the fixture and algorithm, not a successful run's
reported usage. The original logical work/workspace boundaries remain.

The resource route requires the new limit, quantum and stop fixtures for
derive; removing each role must fail its checker. Existing normal Program
fixtures reach this same output preparation owner through the actual retained
Store: ordered derive, sort/take and JSON Pick. They compare the producer and
two independent consumer Named Results, ordered rows/schema, repeated request
reuse, delivered post-progress cancellation, custody and final reclamation.
Their submitted-source execution receipts are recorded in the PR, separately
from the working-tree JS batch above. Runtime bundles are regenerated through
the existing generators and remain untracked.

## Capacity correspondence and remaining work

The structural census includes the optional port/preparation fields and the
private cursor's exact retained fields. The proof observer reports pending
and completed name counts without retaining observed objects. There is still
one admitted name-reference array bounded by output schema width, transferred
without a second backing. The filled-entry DISTINCT model is not expanded
into a physical-byte claim: the new persistent cursor changes fixed-record
shape and allocation timing. Native allocation/callback correspondence review
and campaign execution remain separate obligations for G; this unit does not
claim them from portable source checks.

The schema's required-field flag is already cached, and the bounded output's
live verifier compares the retained row identity without a whole-row scan.
Those findings do not certify arbitrary installed availability callbacks.
General producer preparation, other copied kernel views, legacy drains,
runtime package assembly and Native Host in-flight cancellation remain
separate. Full Core, Wasm/Native execution, packed Local/HTTPS, performance and
stop-latency measurement are not part of this limited validation. This unit
is not Local Compute completion or hosted CI success.
