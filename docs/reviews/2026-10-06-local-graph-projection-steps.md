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

## Stepped Graph row admission

Graph projection now initializes indexed checked-cell slots one per poll.
Its field matching compares at most 64 UTF-16 units under the existing
ASCII-folded Graph name identity rule. It does not construct a lowercased
String or hash the pending field. Non-ASCII spelling and normalization rules
are unchanged; this comparator neither admits names nor changes identities.

Both dense and conditional Graph rows enter the existing AdmittedOutputRow
owner. Conditional cells explicitly describe presence: unavailable coordinates,
absent conditional fields and present NULL are distinct. Required absence and
value-contract violations remain invalid. No Missing value, schema relaxation,
execution authority or independent ledger is added.

The existing row owner rechecks one node/text fragment at a time and drives
the same logical-value charge cursor. Presence charges each physical slot and
field name, including absence, under the existing cumulative output budget.
The final commit transfers the provisional array without another full row
copy or measure. Output remains locked until commit or stopped cleanup;
failure retains row scope, recheck/measure custody and unfinished output.
Repeated cleanup cannot release a later active row or reclaim accepted output.

The stored/viewed wrappers, Graph input binding, completion port, retention,
ordering, logical row bytes and CID preimages are unchanged. Intermediate
provisional cells reserve width+1, with nested measurement frames under the
remaining existing workspace. Graph ordering retains its original four slots
per source row; matched cells and borrowed recheck custody are charged as well.

### Independent boundaries

- Small node: 104/103 control work, 36/35 workspace.
- Small edge: 255/254 control work, 40/39 workspace.
- Static definition selection adds one control poll. Two short labels add
  sixteen, including their second row recheck.
- Three presence rows `{id:1,p:7}`, `{id:2,p:null}`, `{id:3}` charge nine
  nodes, nine name bytes, eighteen work. Retained wire and reread preserve
  omission versus NULL; required access to p stays rejected.
- One shared Array of 128 scalars in a conditional cell charges 131 nodes
  and three name bytes, hence 134 logical work. 133 fails; stop inside
  recheck and measurement releases the same scope once.
- A real Graph projection with a 513-unit property name and 128-element
  Array has 325 setup/field polls plus 588 shared-row polls = 913/912.
  Logical output is 141 nodes, 642 text bytes, 783/782 work; workspace 38/37.
  Quanta 1/7/256 preserve complete wire and work. Stops 54/128/400/800 lie
  in long-name matching, nested rechecks and nested measurement.

The long-name fixture's first 912-poll ledger omitted the separate setup
poll before its nine output-name fragments. The corrected phase sum above
includes that operation, not an allowance sampled from a successful run.
The initial fixture also used JSON in Values, which the existing constructor
contract rejects; it now uses the supported typed Array contract. Neither
failure was used to change the product's semantics or ceiling.

### Executed candidate checks

The affected JS caller batch passed 121/121 (run-WTw3oY,
focused-test-uvBSZh). It includes dense/presence row owners, canonical presence
retention, Graph presence variants and existing Events/Vectors projection.
The long-name Graph case passed 1/1 separately (run-jZcLzL,
focused-test-WwQvQF), including all three quanta and typed shortage/stop checks.

Only local-node runtime dependencies were rebuilt (run-FSZ8TX). The ignored
connectors_builtin_node runtime SHA-256 is
730545fa6e2d1d936786676b41385cf8ba7f036c22cdb5415f5d098924fba2be.
The unchanged run-host-core runtime SHA-256 is
afd59ea3984645a1e8112c0470133b80846bd10cb7d6a417e5abf88aabd2ad22.
This is checkout runtime evidence, not pristine packed acceptance.

The public Local/real Store presence-selection case and installed node_rows /
edge_rows delivered-cancellation cases passed 3/3 (run-hjkbF2,
focused-test-CiqU23). The public case compares independent full retained rows,
Named Results, reread and attach; it includes heterogeneous definitions,
omission/NULL, both projection families and empty/selected inputs. Host cancel
proves actual delivery after positive work, not a particular nested frame.
Nested-frame stop evidence is supplied by the separate kernel cases.

The focused API generation inspected js/wasm/native interfaces for
execution_relation and carrier_contract; that is not Wasm/native test
execution. Final checks and source identities are recorded in the PR.

The resource validator's first candidate run passed 214/221: its success/CLI
cases rejected an unregistered executable public-suite label. Registration
now points to the existing, explicitly named Local presence-selection case.
The new Graph mutations and six affected success/CLI cases passed in
the focused eight-case rerun (run-pAyhTB, focused-test-hFhPQG). The read-only
resource summary passed with unchanged counts (69 operations, 62 mapped,
seven refusals, 62 full records, 114 path records); these counts do not prove
the remaining synchronous boundaries are complete.

## Remaining boundaries

Graph label Text construction/UTF-8 measurement and final label-array copy,
definition/label selectors and identity ordering-key acquisition still have
their existing synchronous scans. Runtime JSON object-name admission retains
its canonical identifier scan. This change does not claim those are stepped.
They remain separate work under the existing owners, as do constructor
preparation, Events identity/comparison, intermediate aggregate bytes and
whole-Run accounting. No full Core, full-target, packed, proof or performance
campaign was run for this unit, and Local completion is not asserted.
