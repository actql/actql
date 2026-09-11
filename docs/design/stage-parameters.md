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
tree and stage bounds. Collection uses the local collector's shared limits per
call. A future complete Program traversal must aggregate allowances across stages;
repeated calls here do not establish a Program-wide work bound.

This boundary proves source correspondence for declarations, steps and initial
selection only. It does not prove the supplied input Carrier contracts, inspect
input/Result/Effect/binding reference slots, establish complete usage or generate
stage/Program semantic CIDs. Structural Program admission itself is not a full
semantic check. In particular, passing this boundary cannot authorize capacity
applications or runtime execution.

Tests cover two equal-looking stage pipelines, separately parsed Programs,
foreign declaration owners, omitted authored `from`, stage-index bounds, nested
collection failures and declaration-free Programs with explicit empty owners.
