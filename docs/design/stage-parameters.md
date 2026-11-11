# Source-bound stage Parameter collection

`stage_parameters.prepare` reads the shared Parameter declarations directly from
an admitted `stage_syntax.Program`. The opaque source retains that Program,
its stages and the resulting declaration owner. Callers use `declarations` when
checking each stage pipeline, including an explicit empty owner when `params`
is absent. Preparation does not accept an independently supplied declaration map.

`collect` selects an actual stage by index and requires:

- the exact declaration owner produced by preparation;
- exactly the authored stage input-name set, including unused declarations;
- the exact source arena and node for that stage's `steps`;
- the exact optional source node for its authored initial `from`, including
  presence versus absence.

Equal text, equal paths or equivalent declaration values do not substitute for
these owners. A separately prepared owner is distinct even when it uses the same
Program unless preparation explicitly forwards that original Source. This is
an API composition requirement, not an additional restriction
on the language's accepted source documents.

## Completed declaration and binding reuse

The Source retains the declaration limits that admitted its private declaration
owner. `prepare(..., original=...)` returns that same Source only for the same
opaque complete Program and component-wise equal or relaxed declaration
ceilings. A foreign Program, a prefix, or reduced limits goes through the same
ordinary declaration reader. Equal source text or a matching CID is insufficient.

`prepare_bindings` retains the existing completed `BindingReadInput` in a new
immutable Source snapshot. The parameter owner matches the exact declaration
owner, supplied tree and node, and current value limits. An accepted binding may
be forwarded under fitting node/text ceilings measured by its original
cumulative preflight and per-value admissions. Depth remains equal or relaxed;
no smaller-depth proof is inferred from these scalar measurements. A failed outcome is
forwarded only under identical limits because a different budget can change the
first refusal. Absent input remains distinct from supplied NULL. Pending readers
are never advanced by reuse. Other inputs use the same semantic binding engine.
Neither entry accepts a caller-authored successful Result or proof.

The public Program check passes this same Source into the actual bound or
template checker. Catalog admission and visibility still precede their original
disclosure boundaries. The topology's binder forwards completed values while
charging their original node/text usage against its remaining allowance.
Template scope never binds supplied values and still rejects a supplied object
before preparing its declarations. No Run, Account, clock, permission, resource
currentness or external callback is part of these immutable facts.

The Source adds two reference fields and retains the original four-word
declaration-limits record. The strict Closed Values topology inventory includes
that additional header, two references and four words. Its binding-reader field
is empty on that path. A retained nonempty binding reader and Source snapshot
remain part of the enclosing preparation consumer's actual live inventory;
semantic reuse alone does not establish physical backing or settlement.

`prepare_from_declaration_read` consumes only a completed reader whose original
source position is this Program's actual `params` field. It shares the ordinary
Source constructor and retains the reader's original limits and declarations.
Pending or foreign readers are not advanced, and completed typed refusals remain
refusals. `retain_completed_binding` similarly assembles the existing Source
snapshot from a completed reader belonging to the same declaration owner. It
does not bind values again or turn a failed binding into effective values.

The enclosing Parameter construction driver grows its existing parent before
the Source root Map, correspondence carriers and Stage copy. The Source owns
their [constructor inventory](../../src/stage_parameters/source_construction.mbt),
using the generic collection owner's Map/Array growth rules and the actual
Program width. This inventory does not borrow a Values execution layout. One
original work receipt covers the root fields and Stage copy; capacity retries
retain the same Program, reader and quote. The binding driver separately grows
before the Source snapshot while the original Source, declarations, values and
reader remain charged. Reconciliation returns only the synchronous scratch of
a successful constructor. Clearing either driver drops its references without
settling the parent, refunding work or asserting a physical cleanup ACK.

The entering caller still supplies backing for the admitted Program/input and
the pre-resize/current/getter frame. These Source phases do not supply numerical
first-entry backing, complete checker/Context funding or an execution grant.

After these checks, the
[local pipeline collector](pipeline-parameters.md) derives operation references
relative to the stage body. `/steps/0/...` coordinates do not include the stage's
position in the enclosing Program. The immutable result retains both the prepared
source and local collection. Invalid stage indices and ownership mismatches
reject before local collection; collection failures retain their nested issues.

Input-name matching is set-based: object enumeration or caller registration order
does not change acceptance. Missing or extra inputs reject; an equal-size set
with a substituted name rejects with that name. This prevents an otherwise
source-owned pipeline from introducing an undeclared input or omitting an unused
one. It checks registration correspondence, not the input Carrier, key evidence,
SourceView selection, receipt contract or runtime admission. The currently
supported pipeline input registry is not a substitute for a future separately
typed acquisition-template registry.

Preparation uses the existing declaration limits and the Program's prior source,
tree and stage bounds. Single-stage collection uses the local collector's shared
limits per call; repeated calls do not establish a Program-wide work bound.

`collection_work` includes one source-name registration and one pipeline-name
lookup per input, charged before building the name index, plus the local
operation collector's work. All-stage collection consumes this total from its
remaining allowance. Names are retained by earlier owned source/pipeline trees,
so this pass does not charge them as newly admitted direct-operand text. This is
logical work accounting, not a string-hashing or heap-size bound.

## All-stage operation collection

`collect_operations` requires exactly one pipeline for every stage, in source
order. Missing, repeated, foreign or reordered registrations reject. It calls
the source-bound collector for each stage with the remaining work, slot,
reference, pointer and direct-text allowances, never a reset per-stage budget.

`collect_prepared_operations` uses the same aggregate indexing path but retains
already collected stages, including the exact owners used by producer ports and
input attachments. It requires the same source owner and the correct stage index
at every position; equal-looking foreign stages cannot substitute. All prior
collection costs are admitted against the aggregate limits before gathering
occurrences, and only the Program-coordinate index is newly built. This allows
dependency-ordered Program preparation to attach the existing Result checks
without reissuing either Stage or Result owners. The retained stage array is
independent of the caller's registration array.

The result retains each local index and one combined index in Program coordinates.
For example, equal local `/steps/0/take` positions in two stages become distinct
`/stages/0/steps/0/take` and `/stages/1/steps/0/take` pointers. The combined index
reuses occurrence owners; expressions and direct operands are not admitted again.
Records retain the common canonical sorting, escaping and declaration projection.
The caller's pipeline registration array is not retained.

`operations_usage` reports the consumed allowances. Slots and references count
semantic occurrences once, while pointer units count both local and Program
indexes because both are retained. Work includes each stage registration, all
local collector work, gathering each slot handle, registering each combined
reference and constructing the combined pointer units. As with the underlying
collector, these are logical-work limits, not a comparison count or process-memory
quota. Exact limits pass; exhaustion exposes no partial result. Stage failures
retain their index and nested issue.

The combined index covers operations only. Its used-declaration projection cannot
stand in for whole-Program or whole-stage use until the remaining grammar slots
have been included. In particular, unreferenced declarations are not rejected by
this entry. The [source-bound Result pass](stage-results.md) now validates actual
stage Result maps and their structural-only reference positions while retaining
publication obligations. Complete traversal must also charge additional slots against
the enclosing budget, rather than give them another independent full allowance.

## Source-owned operation bindings

`bind_operations` attaches one complete admitted Parameter value set to the
combined Program-coordinate index and every stage-local index. The declaration
owner is the one prepared from the same admitted Program; an equal-looking
declaration set from another preparation fails. The caller cannot supply an
independent value set for each stage or omit a stage from this binding pass.
Each index uses the common typed value projection, retaining repeated reference
locations but selecting each used name once. Local and Program paths remain
different even when their selected value preimages happen to be equal.

The opaque result retains the collected operations and indexed bound selections,
not caller arrays. Its work cap includes all earlier operation collection work,
the combined binding work, one registration per stage and each local binding
cost. Other usage counters remain the retained collection's counts: no paths
or expression occurrences are reconstructed. A late stage budget failure exposes
no partial result. Tests verify exact source/value/index owners, repeated names,
fixed projected bytes, aggregate exact/short limits and foreign preparations.

These are operation-only selections, not completed whole-Program or stage
identities. Input/Result/Effect/binding slots, stage input wiring, static
obligation discharge and semantic envelope construction still require their
enclosing integration. A bound operation index does not discharge a guard's
numeric constraint or prove that another independently assembled checking
context used the same bindings.

This boundary proves source correspondence for declarations, steps and initial
selection only. It does not prove the supplied input Carrier contracts, inspect
input/Result/Effect/binding reference slots, establish complete usage or generate
stage/Program semantic CIDs. Structural Program admission itself is not a full
semantic check. In particular, passing this boundary cannot authorize capacity
applications or runtime execution.

Tests cover two equal-looking stage pipelines, separately parsed Programs,
foreign declaration owners, omitted authored `from`, stage-index bounds, nested
collection failures and declaration-free Programs with explicit empty owners.
All-stage tests additionally cover local versus Program coordinates, aggregate
exact/one-less limits, registration completeness and ordering, and mutation of
the caller's registration array after success.
