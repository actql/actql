# Local Compute RelA baseline gaps

Baseline:
`5a305f3ce5cdac421985fb9a71878bc22af51237`.

This table is a review aid. The machine-readable authority for status is
[the coverage manifest](2026-09-18-local-compute-coverage.json), and the
operation mother set comes from the fixed normative specification rather than
the implementation.

## Contract gaps found during the initial audit

| Gap | Evidence | Required resolution |
| --- | --- | --- |
| `nest` has no canonical AoA mapping | It appears in the normative RelA inventory, but not the normative canonical mapping table | Define the common typed operation and register it before Local lowering |
| `REL.except_rows` is absent from the pinned pipeline registry | The target contract lists it as required | Add the shared registry operation and preserve row equality, duplicate, and order rules |
| `REL.intersect_rows` is absent from the pinned pipeline registry | The target contract lists it as required | Add the shared registry operation and preserve row equality, duplicate, and order rules |
| `REL.cross_join` is absent from the pinned pipeline registry | The target contract lists it as required | Add the shared registry operation, output order, and capacity contract |
| `REL.analytic` is absent from both the pinned registry and target requirements | The normative mapping requires it | Complete the shared machine contract before lowering or execution |

These are required-scope gaps, not reasons to remove operations from the Local
milestone.

## Current implementation layers

Legend: complete (`C`), partial (`P`), missing (`-`). `Host` means managed
standard-Host candidate and execution support, not a direct kernel call.

| Operation | Checked | Lowering | Kernel | Host | Main gap |
| --- | :---: | :---: | :---: | :---: | --- |
| filter | C | C | C | P | Complete NULL, demanded-failure, type, and performance coverage |
| select | C | C | C | C | Complete three-target and performance evidence |
| rename | C | C | C | P | Multiple rename, collision, type, and performance coverage |
| drop | C | C | C | P | Multiple drop, empty-schema, type, and performance coverage |
| derive | C | C | C | P | Demanded failure, type, overwrite, and performance coverage |
| sort | C | C | C | P | Managed stability and performance floor |
| take | C | C | C | P | Managed validation and boundary cases |
| top_k | C | - | - | - | Common lowering and execution |
| top_k_by | C | - | - | - | Partitioned lowering and execution |
| row_window | C | - | - | - | Fixed/sliding lowering and execution |
| window_group | C | - | - | - | Window projection and aggregate execution |
| lag | C | - | - | - | Ordered partition execution |
| watermark_rows | C | - | - | - | Finite watermark lowering and execution |
| pivot | C | C | P | P | Exact deterministic aggregates, including precision-38 Decimal sum, are connected; binary64 numeric observation, full variants/types, native layout aggregation, and performance remain |
| unpivot | C | C | P | P | Type matrix, native layout writer, and performance evidence |
| json_pick | C | C | C | P | Failure, type, budget, and performance coverage |
| unnest | C | - | - | - | Bounded expansion lowering and execution |
| join | C | P | P | - | Only inner equality join is lowered |
| nest | C | - | - | - | Canonical common contract is missing |
| group | C | P | P | - | Only count aggregation is lowered |
| distinct | C | C | C | P | Keyed/NULL/type and indexed performance evidence |
| dedupe_rows | C | C | C | P | Compound/NULL/tie and indexed performance evidence |
| assert_rows | C | C | C | P | Compound keys, Host failure locations, and performance evidence |
| append | C | - | - | - | Common two-input lowering |
| values | C | C | C | - | Genuine zero-input Host path |
| except | C | - | - | - | Registry, lowering, and execution |
| intersect | C | - | - | - | Registry, lowering, and execution |
| cross_join | C | - | - | - | Registry, lowering, and execution |
| analytic | C | - | - | - | Machine contract, lowering, and execution |

## Shared-boundary notifications

Before implementing a contract gap above, the Local branch sends the Engine
owner a notice containing the exact API, reason, counterexample, and expected
files. The change is kept in a separate commit so the Engine branch can adopt
the same boundary without adopting Local kernels.

The initial anticipated shared areas are:

- `spec/dependencies/aoa-pipeline-registry.json` and its generated pins;
- `spec/contracts/actql-aoa.json` and registry conformance fixtures;
- common typed payloads in `src/lowering_relation`;
- standard Host support for zero-input tasks and two-input ports;
- common managed storage only if existing retention cannot represent shared
  immutable views.

No shared change is authorized merely by appearing in this list. The required
notification happens before editing it.

## Completion evidence still absent at baseline

No operation yet has all of the newly agreed evidence:

- every formal source variant connected to common lowering;
- every allowed operation/type combination checked on JS, Wasm, and native;
- two actual downstream Computes with overlapping holding;
- storage-strategy failure, cancellation, and exact final reclamation;
- algorithm applicability, complexity, and fixed performance diagnostics.

Existing lower-level tests remain valuable evidence for their exact scope, but
they do not satisfy these broader completion claims by themselves.
