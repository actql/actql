# Resumable Relation order and key metadata

Branch: feat/local-row-order-metadata. Implementation parent: #704 at
`99640c976e02038f5db3fc6dbb593c66d351cee2`. That unmerged parent remains a
dependency; the final integration target is main. Adopted main:
`edaa27e9733572b8b26944a28d5d646f6d827381`, by normal merge with no conflicts.
The pending changes were preserved before integration. Graph remains the sole
current contract; no legacy identity reinterpretation or alias is introduced.

## Implementation and scope

Before this change, wide or long-name sort, take, top-k, distinct, dedupe and
unique assertions built their complete name arrays and lookup Maps during
start. Sort/take name charges and authored key preparation also scanned a
complete spelling in one transition. This is a source-level counterexample;
no wall-clock stop-latency regression is claimed to have been measured.

These shapes now use the existing BoundedBindingRows metadata phases from
#704. They borrow checked schema spellings and resolve cached column sources
before input Value charging. Keyed distinct uses the existing opaque indexed
projection reader. Dedupe, unique assertion, sort and top-k terms retain a
typed schema lookup cursor, then a separate scalar-safe name charge cursor.
The completed term column is retained so reservation and entry charges occur
once, not once per resume. Sort/take schema-name charges likewise resume.

Lookup compares at most 64 UTF-16 units per transition; name charging visits
one Unicode scalar. Existing ordering, NULL, duplicate and authored-winner
rules are unchanged. Small metadata retains the prior direct bounded lane.
Logical control charges are unchanged and cumulative; temporary cursor slots
are additional admitted workspace, released once. Cleanup keeps borrowed input
custody and spent work, while clearing partial metadata and pending cursors.
No new evaluator, scheduler, ledger, public API, wire or CID rule is added.

## Independent evidence

- Start leaves metadata arrays empty for sort, take, whole/keyed distinct,
  dedupe, unique assertion, top-k and empty-partition top-k-by.
- Quanta 1/7/256 preserve fixed expected rows, control work and peak workspace.
  Top-k fixtures obtain their key proof through ordinary checked
  `assert_rows.unique_by`, not internal state construction.
- A supplementary-Unicode column name covers projected NULL equality,
  duplicate elimination, NULLS FIRST, descending tie terms and authored dedupe
  winners. Empty input still performs admitted metadata work and terminates.
- Independent sort-term control boundaries are 257/256 for 256 ASCII bytes
  and 263/262 with an additional emoji and e-acute. Metadata occupies eleven
  slots; sequential lookup/name cursors need one more, giving 12/11 temporary
  workspace limits. Rejections retain typed RowLimit and clean to zero.
  These are term/preparation limits, not a new whole-task capacity claim.
- Cancellation occurs inside sort/take name charging, sort and dedupe key
  lookup, and unique-key name charging. It returns Stopped, retains spent work
  and the live input, and releases the cursor/workspace once.
- A normal Program reaches the installed Host and real retained Store with
  `sort -> take -> derive -> select`. Three explicit Named Results preserve
  the independent order `[{id:1,value:7},{id:3,value:7},{id:2,value:null}]`.
  Both consumers read that order; repeated request reuse adds no dispatch.
  Delivered positive-progress cancellation does not report physical stop or
  release snapshots until the blocked observation returns; final resources
  are reclaimed and the unpublished results remain unavailable.
- The resource checker requires sort/take metadata quantum, stop and public
  evidence, plus the independent sort-term limits. Removing a required role
  fails the completion record. Existing operation-wide boundary evidence is
  retained rather than replaced by these narrower limits.

The implementation batch passed 101/101 focused JS tests
(`run-hD5gte`, `focused-test-jqkBAY`). Runtime dependencies were rebuilt from
integrated sources (`run-IdLR7h`) and ignored bundle freshness passed. The
targeted Host and evidence-removal selection passed 3/3
(`run-pcZyqH`, `focused-test-Pqgq5i`). These receipts were acquired before the
publication commits; exact submitted-HEAD checks are recorded in the PR.
An earlier 100/101 batch used an invalid zero take count in the empty-input
fixture. It was corrected to the existing accepted positive-count contract,
without loosening checker acceptance or resource expectations.

## Remaining boundaries

KernelBody defensive copies, JSON/window metadata, initial preparation and
availability validation remain distinct. Long-name runtime cursors do not
certify every start operation or the installed projected-read ceiling.

Native preparation correspondence is not closed. The #704 handoff identifies
an unreviewed BoundedBindingRowsState census, an outdated first-phase observer
anchor, and the parent's Array snapshot versus Map observer/FFI expectation.
This change additionally retains `term_column`. G must review actual
representation/model correspondence; neither an empty-Map compatibility shim
nor an unexplained census/pin refresh is acceptable. Logical slots are not
physical heap capacity evidence. This dependency is explicit before Ready.

Full Core, Wasm/native execution, packed Local/HTTPS, performance, wall-clock
stop latency and full retained-history/proof campaigns were not run. Draft
preparation CI is not merge verification, and no CI rerun is requested.
