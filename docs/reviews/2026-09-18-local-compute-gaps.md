# Local Compute RelA baseline gaps

Baseline:
`5a305f3ce5cdac421985fb9a71878bc22af51237`.

This table is a review aid. The machine-readable authority for status is
[the coverage manifest](2026-09-18-local-compute-coverage.json), and the
operation mother set comes from the fixed normative specification rather than
the implementation.

## Contract gaps found during the initial audit

The initial `nest` canonical-mapping gap is closed. The normative mapping now
binds `nest` to its finite expansion over existing registered AoA operations.
The common typed lowering retains both checked ports, resolved child order,
projection, reference identities, and authored item guard. Local execution may
fuse the expansion but does not define a Local-only opcode or reopen frontend
syntax.

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
| nest | C | C | C | C | Complete |
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

The manifest records 29 complete operations. `nest` now reaches common typed
lowering, indexed Local correlation, managed completion, two actual downstream
Computes, individual release, and final reclamation. Its runtime checks retain
parent order and duplicate occurrences, resolved child order, NULL no-match,
item ceilings, and distinct grouped and attached recursive-value byte scopes.
The performance fixture bounds correlation by input indexing plus emitted
payload, rather than a per-parent scan of all children.

`window_group`, `pivot`, and
`analytic` now route binary64 sum and average through the selected,
attempt-owned numeric executor. Their managed two-consumer fixtures and
three-target conformance include the numeric paths. Analytic performance
fixtures separately cover one-row, cumulative, fixed-width, full-partition,
and empty frames. They bound work by input rows `N`, total frame memberships
`B`, demanded expression evaluations `E`, and output rows `R`; peak workspace
is bounded by the widest live frame and the `N` by call-count indexes rather
than by total `B`.

Numeric aggregate conversion retains the admitted `Array[Value]` while it
builds an `Array[Double]` of the same contributor count. The shared aggregate
evaluator now reserves that second array before allocation. Group,
window_group, and analytic exact/one-short workspace fixtures cover the
overlap; window_group and analytic reach the same shared evaluator rather than
carrying a Local-only reservation rule. Released per-aggregate temporaries do
not remain in the completed output's retained-storage count.

The managed lag cancellation fixture covers cancellation before execution,
completion rejection, and reclamation. Cancellation during a running Local
kernel remains dependent on the common Engine interruption contract: long
loops need an adopted interruption point, stop confirmation must precede
release, and an interrupted task must not publish completion. Local does not
introduce a separate scheduler or resumable execution contract for this gap.
