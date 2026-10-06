# Graph projection bounded-step work

## Corrected parent work premise

Base: 77e83a8ada9fcb4186a6cf916c3d6ecd8e28755b (PR #627, unmerged).
Four Graph presence work-boundary cases already failed on that parent's
production code and on the earlier parent comparison recorded by #627.

Each full typed identity has eight value nodes and eleven container/child
frames. The shared runtime JSON recheck now also steps its data Text:
definition N takes one TextUnits poll, its 71-unit domain two, and kind
number one. Together with the final empty-stack poll, identity recheck
costs 8+11+4+1=24, not the old 20. Field names contribute 32 text bytes,
data Text 78, for total 110. A literal independently authored identity
fixes all three numbers without obtaining an allowance from product output.

The old projection's work is therefore 44 for one node, 105 for one edge:
the edge contains three such identities. Static definition selection adds
one poll; the two short label selections add ten. Exact and one-short
ControlWorkLimit checks and stop at every charged private phase remain.
No implementation, logical value limit, schema or identity rule changed.

Focused JS command on the corrected candidate tree:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/property_graph_rows_presence_wbtest.mbt
```

All eight cases passed (run-ANaCvq, focused-test-ZAvabD). The prior four
failures remain recorded as historical observations, not passing evidence.
This premise repair does not itself split Graph name matching or output
materialization, and is not full-target, packed or CI acceptance.
