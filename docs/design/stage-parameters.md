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
Program. This is an API composition requirement, not an additional restriction
on the language's accepted source documents.

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
