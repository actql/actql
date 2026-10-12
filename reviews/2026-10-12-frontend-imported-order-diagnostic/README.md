# Imported Result publication order: independent common API diagnostic

This is a diagnostic handoff, not a repair or permanent refusal expectation.
The three remaining Frontend failures retain their original positive assertions.
No product, key, predicate, ceiling, order policy or Result-port API is changed.

## Executed evidence

- Clean source `ce73a9cd33134ce2a5533110233441aa00cd0d82`, run-gJnMJi,
  focused-test-BjE2cP: **JS 4/4**. One independently authored common API comparison
  plus the original three static/order-debt controls in
  `with_binding_static_order_gap_test.mbt`. Budget 60 seconds, grace 5, nonHeavy.
  Complete exit 0, output complete, lock released, actual Owner 76067 absent.
- Earlier source `a1ddeda188d0b91239a64b9107961bf44faf82ab`, run-oeBnBp,
  focused-test-Ox083c: JS 1/1, same comparison before formatting.
- Pinned one-file formatter run-M05xg8 completed. Initial bba5755 diagnostic
  used an incorrect object sort body and failed before the comparison;
  run-30wEgC/focused-test-J0m7pG remains preserved. The array sort body was
  corrected from the independently selected existing machine contract.

## Minimal comparison and retained owners

`independent-program.json` uses one local id/primary-key declaration in a capture
Stage, publishing id. The next Stage imports that same Result once, filters one
consumer by id=1, performs CROSS JOIN with the complete shared input, selects
only right id, then sorts id. Original Cross JOIN ceiling 1,000,000 is retained.
Input ids 1,2 imply output ids 1,2, independently; rows were not executed here.
The complete Program is handwritten from the selected contract, not regenerated
from a product's lowered output.

For the **same source and limits**, `prepare_local_program` returns Ok, while
`check_local_program` returns precisely
`Order(1, PipelineOrder(UnresolvedOrder))`, cursor `stages[1].steps[3]`.
Strict preparation can close the producer's Result publication order before
importing it. Check-only preparation instead calls `prepare_checked_inputs`,
which projects the original producer's logical order without Result ordering.
For this capture that logical order is absent, although the common publication
owner can select a key/field order. The subsequent CROSS JOIN loses that order
in check-only traversal; after projection its composite key is also unavailable
for the final sort. This is an actual common API discrepancy, not a fabricated
Source order or a public Run execution result.

Affected common boundary: `stage_results/local_program.mbt` check-only branch,
`relation_results/checked_inputs.mbt::prepare_checked_inputs`,
`pipeline_typing/produced_projection.mbt`, and the original producer publication
order dependency. The Frontend reaches that boundary through
`query_program/query_binding_check.mbt::check_query_bindings`, before demand.
Any repair must retain the source/producer/projection/import edges and unresolved
publication obligations, use the existing Result/order owner, and preserve strict
publication. Do not manufacture an order/port, catch an Order refusal and ignore
it, or waive operation-required order. The three original missing-order controls
remain passing at the diagnostic source.

## Original Frontend cases remain open

Two `cte_capture_predicate_test.mbt` cases still fail at the common local order
boundary. Their Sources and local declaration are retained separately in
`original-cte-source-cases.json`; original tests and positive checker assertions
are unchanged. Original missing Source Catalog failure is independently repaired
by #1638. Its Catalog-enabled Pipe experiment still fails at
`SourceProgram(Program(Order(1, PipelineOrder(UnresolvedOrder))))`,
`stages[1].steps[9]`; that experiment is in e08e2c335/run-KajyLh, not a repair.
The exact relationship of all three original failures to this minimal comparison
must be verified after the common repair; they are not counted as fixed.

Source Catalog parent #1638 is fixture-only; this diagnostic needs its prepared
wrapper only and no Catalog at runtime. Adopted main is
`82dbe9fa8bd065a3fc9c88baf99b18329b632950`. No full Core, Heavy, Provider,
public Host/packed Local/HTTPS, Native/Wasm runtime or Hosted CI was executed.
Raw original logs remain outside Git; tracked manifests publish hashes only.
