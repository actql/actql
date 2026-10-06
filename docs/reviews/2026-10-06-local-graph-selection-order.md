# Stepped Graph selection and order comparison

Parent: 30a83acb48b9a54a592fcdc401bc83845580bdbb (unmerged PR #637).

## Closed boundaries

Graph row selection retains a candidate index and UTF-16 offset. A long
definition comparison keeps raw spelling equality; label comparison keeps the
existing ASCII-folded identity rule. The selector is not lowercased or copied
when execution starts, and a candidate cannot advance until its comparison
settles. Each charged visit reads at most 64 code units of one candidate.
There is no new selector meaning, normalization, admission or fallback.

The shared tuple sorter retains a component index and code-unit offset in its
existing Sort record. Each merge poll compares one fragment of one component.
Equal components advance individually; the deciding comparison and bounded
index move share the final poll. Existing stable ties and raw UTF-16 order
remain unchanged. No extra comparison array or root is allocated; the existing
two index arrays keep their 2N workspace ceiling. Cleanup resets both offsets.

Graph snapshot now uses the existing deferred sort preparation for node and
edge keys instead of scanning all key shapes synchronously before Initialize.
Canonical JSON and value JSON admission already use this same deferred owner.
Completion still requires every key shape to be validated and sorting finished.

Earlier records called ordering-key acquisition itself a synchronous residual.
Current production Storage reads are indexed references to a retained identity
token (property_storage.mbt); the managed Graph view forwards those same reads
(managed_graph_runtime/output.mbt). They do not re-encode identity. The actual
remaining scan was tuple comparison, which this change splits. Arbitrary
third-party ProducerView callbacks are not proved bounded by that observation.

## Independent resource and semantic evidence

Two tuple keys cost two initialization visits, one run setup, comparison
fragments, one unopposed tail move and one swap. A 1024-unit equal prefix takes
16 fragments followed by one deciding component: 22 total. 128 equal components
take 128 comparison polls: 133 total. Four workspace slots suffice; three reject
before initialization. Quanta 1/7/256 preserve work, stable ties and UTF-16 order
(supplementary Unicode sorts before the private-use BMP example). Cleanup during
an unfinished comparison leaves no index output. No successful run determines
these allowances.

Before the fix, the long-prefix case completed in six polls instead of 22
(run-tS32QQ / focused-test-rVaDSK). This fixes a component's synchronous scan;
it is not an observed public Run stop-latency measurement.

Selector vectors fix nine visits for a 513-unit definition (equal or last-unit
mismatch), one for its raw case mismatch, eighteen for two 513-unit label
candidates, and one for no selector. Offsets reset only after a candidate settles.
The normal typed Graph fixture exercises both node/edge projection with long
or wide label selection: add nine or 128 control polls to its existing ledger.
Logical node/Text/work and workspace limits remain unchanged. Exact/one-short,
selected-result content, quantum invariance and cancellation within selection
remain typed and keep the input available through once-only owner cleanup.

## Selected verification

Final candidate JS selection passed 32/32 (run-nwqML5,
focused-test-tcYSbT):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/canonical_value/compare_steps_wbtest.mbt src/bounded_tuple_sort \
  src/local_bridge src/query_integration/property_graph_rows_presence_wbtest.mbt \
  src/query_integration/property_graph_label_steps_wbtest.mbt \
  src/query_integration/property_graph_row_steps_wbtest.mbt \
  src/canonical_json/cursor_admission_wbtest.mbt \
  src/bounded_graph_snapshot/snapshot_wbtest.mbt \
  src/bounded_graph_snapshot/property_snapshot_wbtest.mbt \
  src/value_admission/key_order_text_wbtest.mbt
```

This includes real sorter consumers, not compilation alone. An earlier candidate
passed 32 cases but emitted unused derive warnings; the test-only comparisons
were moved to a test helper without adding production traits.

Affected API generation inspected JS/Wasm/native interfaces (132 tasks), not
Wasm/native test execution. Local Node and Run Host Core dependencies were
rebuilt together from the changed source (run-kAVUCG), with both asset checks.
Ignored runtime SHA-256 values:

- connectors_builtin_node:
  9a9a86b207beaca5059b6fde045b3cc6cf1325ea134a8355861a102eae101a5a
- client_values_host_abi:
  18e6e732bbba1450f2576d70ca547f5e0aaee70ec100af49d91fdfbfa9691f4b

Public Local/real Store, two delivered Host cancellations and eleven selected
resource-gate cases passed 14/14 (run-HSoHIs / focused-test-S3X2kH).
Store evidence: local-HR6oA8. Independent retained/published rows, reread and
attach remain asserted. These public cases do not specifically measure the
long-name selector frame; component and typed Graph fixtures supply that stop
evidence. No pristine packed campaign is claimed.

The first read-only resource scan rejected an unregistered bounded_tuple_sort
suite. The suite is now connected to the existing root Core test invocation
and its JS/Wasm/native-supported package, keeping all-target evidence checks.
Mutation cases reject removing selector offsets, raw/folded fragment calls,
tuple offsets or registered boundary evidence. No refusal became execution
evidence and route totals did not change. Final source SHA, freshness checks
and automatic PR CI are recorded separately in the PR.

## Remaining work

Runtime JSON object-name canonical admission, constructor preparation, Events
identity/comparison, intermediate aggregate bytes and whole-Run accounting
remain separate boundaries. Other algorithms that compare Text outside this
tuple owner are not covered. This component does not assert complete Local
closure, full Core, packed, proof, performance or full-target execution.
