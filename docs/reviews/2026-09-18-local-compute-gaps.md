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

These are required-scope gaps, not reasons to remove operations from the Local
milestone.

The fixed baseline does not define parameterized `json_pick` path components.
Its paths are nonempty arrays of exact object-key strings. The same baseline
also retains opaque `json` traversal as an unsupported evidence boundary and
defines no Host API for supplying that evidence. Local coverage therefore
includes typed-object traversal, retaining an opaque `json` leaf, and rejecting
further opaque traversal without evidence. It does not claim support for an
undefined parameter-path form or for a future shape-evidence API.

## Current implementation layers

Legend: complete (`C`), partial (`P`), missing (`-`). `Host` means managed
standard-Host candidate and execution support, not a direct kernel call.

| Operation | Checked | Lowering | Kernel | Host | Status |
| --- | :---: | :---: | :---: | :---: | --- |
| filter | C | C | C | C | Complete |
| select | C | C | C | C | Complete |
| rename | C | C | C | C | Complete |
| drop | C | C | C | C | Complete |
| derive | C | C | C | C | Complete |
| sort | C | C | C | C | Complete |
| take | C | C | C | C | Complete |
| top_k | C | C | C | C | Complete |
| top_k_by | C | C | C | C | Complete |
| row_window | C | C | C | C | Complete |
| window_group | C | C | C | C | Complete |
| lag | C | C | C | C | Complete |
| watermark_rows | C | C | C | C | Complete |
| pivot | C | C | C | C | Complete |
| unpivot | C | C | C | C | Complete |
| json_pick | C | C | C | C | Complete |
| unnest | C | C | C | C | Complete |
| join | C | C | C | C | Complete |
| nest | C | - | - | - | Canonical common contract is missing |
| group | C | C | C | C | Complete |
| distinct | C | C | C | C | Complete |
| dedupe_rows | C | C | C | C | Complete |
| assert_rows | C | C | C | C | Complete |
| append | C | C | C | C | Complete |
| values | C | C | C | C | Complete |
| except | C | C | C | C | Complete |
| intersect | C | C | C | C | Complete |
| cross_join | C | C | C | C | Complete |
| analytic | C | C | C | C | Complete |

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

## Completion evidence

The manifest records 28 complete operations. `window_group`, `pivot`, and
`analytic` now route binary64 sum and average through the selected,
attempt-owned numeric executor. Their managed two-consumer fixtures and
three-target conformance include the numeric paths, and analytic numeric frames
have an indexed scaling floor.

`nest` is the only remaining operation. It requires a canonical common AoA
contract before lowering, Local execution, managed lifetime, and coverage can
be completed without frontend rediscovery.
