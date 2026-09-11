# Source-bound stage Parameter collection

`stage_parameters.prepare` reads the shared Parameter declarations directly from
an admitted `stage_syntax.Program`. The opaque source retains that Program,
its stages and the resulting declaration owner. Callers use `declarations` when
checking each stage pipeline, including an explicit empty owner when `params`
is absent. Preparation does not accept an independently supplied declaration map.

`collect` selects an actual stage by index and requires:

- the exact declaration owner produced by preparation;
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

Preparation uses the existing declaration limits and the Program's prior source,
tree and stage bounds. Single-stage collection uses the local collector's shared
limits per call; repeated calls do not establish a Program-wide work bound.

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
this entry. Complete traversal must also charge those additional slots against
the enclosing budget, rather than give them another independent full allowance.

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
