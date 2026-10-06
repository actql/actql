# Stepped Graph label output

## Scope and ownership

Parent: bae96c9c09a901f75dbe5f3498b3bb561628f188 (unmerged PR #635).
This component completes label Text construction and label-array finalization
inside the existing Graph-to-Relation owner. It does not change selector,
ordering, schema, CID, Graph identity or NULL/presence semantics.

Each label uses the existing runtime Text recheck, at most 64 UTF-16 units
per advance. Its returned byte count replaces both synchronous Text admission
and a second full UTF-8 encoding. Labels append individually to the existing
private ArrayBuilder; sealing transfers its backing without a final copy.

The complete provisional label count is reserved before growing the builder.
After sealing, that reservation remains until the shared row commits: the
row cursor receives only the remaining workspace. Thus freezing the array
does not make its private elements disappear from accounting. Pending Text,
builder and sealed-row custody remain owned on failure/stop and are released
by existing cleanup once. Accepted output moves to the existing row budget.
No scheduler, ledger, new completion authority or mutable output is added.

## Independent boundaries

Empty-label node/edge control work remains 104/255. A 513-unit ASCII label
adds eleven construction polls, eleven first-row recheck polls, eleven shared
row recheck polls and twelve output measurement polls: 149/300 total.
128 four-unit labels add 384 construction, 384 per recheck and 257 measurement
polls: 1513/1664. No successful execution determines these allowances.

| Input | Control work | Workspace | Logical nodes | Text bytes | Logical work |
| --- | ---: | ---: | ---: | ---: | ---: |
| Node, one long label | 149 | 37 | 12 | 641 | 653 |
| Edge, one long label | 300 | 41 | 28 | 865 | 893 |
| Node, 128 labels | 1513 | 164 | 139 | 640 | 779 |
| Edge, 128 labels | 1664 | 168 | 155 | 864 | 1019 |

Workspace is order four + matched width + borrowed depth/custody 23 +
provisional label count + row width/handle + two measurement frames.
The existing long-name/nested-property fixture now needs 915 control polls
and 39 slots (one reserved label); its logical limits remain 783/782.
Two selected short labels add twenty control polls and two provisional slots.

The four new variants assert independent label content/order, quanta 1/7/256,
control/workspace/logical-work/Text exact and one-short failures, unpublished
shortage outcomes, stop within construction, live input and once-only cleanup.
Stored/viewed wrapper cases retain cancellation at every charged private phase.

## Reproduction and selected verification

Before the production change, the long-label case completed in 139 polls,
not the independently derived stepped boundary 149 (run-MJcvUE,
focused-test-0Rx12G). Its label Text scan remained inside one nominal poll.
This is component evidence, not a measured public Run stop-latency claim.

Two initial fixture mistakes are retained separately: an unused extra input
violated the constructor binding (run-rua5eI), and the first read used presence
access for a dense row (run-1lO9hk, nine other cases passed). Both were corrected
without changing product input or row-access contracts.

Final candidate JS cases passed 10/10 (run-grsXZl, focused-test-kMPFZ9):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/property_graph_label_steps_wbtest.mbt \
  src/query_integration/property_graph_rows_presence_wbtest.mbt \
  src/query_integration/property_graph_row_steps_wbtest.mbt
```

Only affected Local Node runtime dependencies were rebuilt (run-Wk71vU),
followed by build-local-node-assets and its read-only check. Ignored output:
connectors_builtin_node SHA-256
05038aeb56dbfd144401c18c055230926d8be3cdd9fe678b672b720d7a61eedc.
Unchanged client_values_host_abi SHA-256
afd59ea3984645a1e8112c0470133b80846bd10cb7d6a417e5abf88aabd2ad22.

The real Store/public Named Result case, two delivered Host cancellation
cases and ten focused resource-gate cases passed 13/13 (run-Xiy0bg,
focused-test-bzM49H). Store evidence: local-NYkYLD. The public case uses
independent expected rows, reread and attach. It does not specifically observe
the long-label frame; the new component fixture supplies that stop evidence.
The gate rejects removing staged Text, capacity reservation, array transfer,
cleanup or the registered boundary fixture. These are executable connections,
not operation-name evidence alone.

Node Host and Workers fixture freshness passed. Formatting and diff checks
are recorded with the final source SHA in the PR. These are checkout runtime
checks, not pristine packed acceptance. No full Core, Wasm/native execution,
proof, performance or full integration campaign was run for this component.

## Remaining boundaries

Definition/label selection, identity ordering-key acquisition and runtime JSON
object-name admission retain synchronous scans. Constructor preparation,
Events identity/comparison, intermediate aggregate bytes and whole-Run
accounting remain separate work. Inventory totals are unchanged and do not
establish complete Local closure. Final-SHA automatic CI is separate from
the selected local evidence above.
