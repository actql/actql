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
| `REL.analytic` is absent from both the pinned registry and target requirements | The normative mapping requires it | Complete the shared machine contract before lowering or execution |

These are required-scope gaps, not reasons to remove operations from the Local
milestone.

## Current implementation layers

Legend: complete (`C`), partial (`P`), missing (`-`). `Host` means managed
standard-Host candidate and execution support, not a direct kernel call.

| Operation | Checked | Lowering | Kernel | Host | Main gap |
| --- | :---: | :---: | :---: | :---: | --- |
| filter | C | C | C | C | Complete the formal predicate/operator and admitted type matrix, including the shared owned-reference runtime boundary |
| select | C | C | C | C | Add the shared owned-reference runtime boundary for `resource_ref` and `artifact_ref`; all directly admitted domains, source variants, two consumers, and the performance floor are covered |
| rename | C | C | C | P | Standard-Host evidence, collision matrix, and shared owned-reference runtime boundary; swap/empty variants, direct value domains, NULL, branches, and linear work are covered |
| drop | C | C | C | P | Standard-Host evidence, all-column rejection connection, and shared owned-reference runtime boundary; repeated/empty variants, direct value domains, NULL, branches, and linear work are covered |
| derive | C | C | C | P | Standard-Host evidence, full result-type and overwrite matrix, and shared owned-reference runtime boundary; empty/ordered/parameter/failure variants and linear work are covered |
| sort | C | C | C | P | Standard-Host evidence, parameter-derived ordering requirements, exact budget boundaries at scale, and the shared owned-reference comparison boundary; stable direction, NULL placement, compound terms, scalar domains, two consumers, and indexed scaling floors are covered |
| take | C | C | C | P | Standard-Host evidence, the full admitted value-domain retention matrix, and large-scale exact/one-short budgets; literal and parameter counts, offsets, inherited order, boundary rejection, whole-input validation, branches, two consumers, and linear scaling are covered |
| top_k | C | C | P | P | Standard-Host evidence, the broader orderable type matrix, and large-scale exact budget boundaries; literal/parameter counts, compound NULL order, stable completion, two consumers, and indexed scaling are covered |
| top_k_by | C | C | P | P | Standard-Host evidence, the broader key/orderable type matrix, and large-scale exact budget boundaries; repeated/nullable partitions, literal/parameter counts, two consumers, and indexed scaling are covered |
| row_window | C | - | - | - | Fixed/sliding lowering and execution |
| window_group | C | - | - | - | Window projection and aggregate execution |
| lag | C | - | - | - | Ordered partition execution |
| watermark_rows | C | - | - | - | Finite watermark lowering and execution |
| pivot | C | C | P | P | Count, min/fill, empty axes, and Decimal sum are managed with fixed scaling evidence; binary64 numeric observation, full variants/types, and native layout aggregation remain |
| unpivot | C | C | P | P | Empty and repeated-column managed paths and linear scaling are covered; type matrix and native layout writer remain |
| json_pick | C | C | C | P | Standard-Host evidence, opaque-json shapes, parameter paths, exact budget boundaries, and the shared owned-reference runtime boundary; direct leaf domains, malformed retained values, NULL, and linear scaling are covered |
| unnest | C | C | P | P | Inner/outer managed paths and linear scaling are covered; nested-value matrix and native layout writer remain |
| join | C | P | P | P | Equality kinds, compound nullable keys, self joins, cardinality, and indexed scaling are covered; cross-stage full identity transfer, broader types, and diagnostics remain |
| nest | C | - | - | - | Canonical common contract is missing |
| group | C | P | P | P | Count is managed for empty, nullable, and compound keys with two consumers, result limits, and subquadratic work; non-count aggregates and remaining key domains remain |
| distinct | C | C | C | P | Standard-Host evidence, the broader whole-row domain matrix, and shared owned-reference comparison; keyed nullable projection, first occurrence, two consumers, and indexed scaling are covered |
| dedupe_rows | C | C | C | P | Standard-Host evidence, the broader key/orderable domain matrix, and shared owned-reference comparison; compound nullable keys, tie failure, two consumers, and indexed scaling are covered |
| assert_rows | C | C | C | P | Standard-Host failure-location evidence, exact budget boundaries, and the full KeyComparable domain including the shared owned-reference runtime boundary; compound nullable keys, demanded failures, and linear scaling are covered |
| append | C | C | C | C | Add the shared owned-reference runtime boundary for `resource_ref` and `artifact_ref`; all source variants, two consumers, and the performance floor are covered |
| values | C | C | C | C | Complete: all fixed-contract variants, three targets, two consumers, limits, and performance floor |
| except | C | C | P | P | Empty sides, layout pairs, and sort-merge scaling are fixed; reference-value and failure evidence remain |
| intersect | C | C | P | P | Empty sides, layout pairs, and sort-merge scaling are fixed; reference-value and failure evidence remain |
| cross_join | C | C | P | P | Layout pairs and product-proportional scaling are fixed; full types and cancellation lifetime remain |
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

## Completion evidence

`values` is the first operation with all newly agreed evidence. `select` and
`append` now have complete source, managed two-consumer, and performance
evidence; their remaining gap is the shared owned-reference runtime boundary.
The remaining 28 operations still need one or more of:

- every formal source variant connected to common lowering;
- every allowed operation/type combination checked on JS, Wasm, and native;
- two actual downstream Computes with overlapping holding;
- storage-strategy failure, cancellation, and exact final reclamation;
- algorithm applicability, complexity, and fixed performance diagnostics.

Existing lower-level tests remain valuable evidence for their exact scope, but
they do not satisfy these broader completion claims by themselves.
