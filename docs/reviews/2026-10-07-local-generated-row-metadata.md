# Resumable generated Relation metadata

## Scope and integration

This unit extends the existing bounded Relation owner to JSON Pick, fixed
Watermark rows and Lag with wide or long schema names. It depends on the
unmerged metadata owner in #704 and order/key extension in #708. Its final
merge destination is main, not a dependency branch.

The branch normally merged main
`90c4801a40d57bada514108586ac29f070add8ca` without conflicts. The latest
Graph naming and identity contracts are retained; this change adds no public
API, wire schema, CID domain, compatibility alias or evaluator.

## Counterexample and implementation

Before the change, the new `generated row metadata is not materialized before
bounded resume` regression failed: start had already built the input/output
name arrays and ordinal maps. JSON Pick also required its generated output
to be the final schema column, despite canonical schema order. Output copying
compared generated names again on every row.

Wide/long-name shapes now use the existing `PrepareInputNames`,
`PrepareOutputNames` and `PrepareRowSources` phases. A checked generated role
is matched with the existing UTF-16 fragment comparison, at most 64 units
per poll. The role is cached once, including an exact seen mask; an absent
input column is not a generic generated-column fallback. The new
`PrepareOperationMetadata` phase resolves the borrowed typed JSON source,
Watermark time or Lag value field through the existing schema lookup cursor.

The borrowed operation source reserves one metadata slot. Lookup reserves
one temporary slot, closes once, and releases the borrowed-source slot on
success or stopped cleanup. Per-row output copying reads the cached role,
not an entire generated spelling. The admitted short lane remains bounded
to eight names of at most 64 UTF-16 units and retains existing exact budgets.
Logical name-byte charges are unchanged; cursor transitions do not invent
additional logical work. Borrowed inputs and spent work survive cancellation.

## Independent and public evidence

`row_window_metadata_wbtest.mbt` checks all three shapes across quantum
1, 7 and 256, fixed rows, NULL, supplementary Unicode, canonical columns,
empty inputs and generated outputs preceding their source column. It stops
inside generated-role matching and source lookup, before input charging,
and verifies no output, zero local workspace and live borrowed input.

The JSON fixture derives preparation workspace independently: path view 3,
input names 2, output names 3, input ordinals 2, projection 3, cached sources
3 and borrowed source 1 total 17; the lookup requires one more, so 18 succeeds
and 17 fails with `Rows(RowLimit)`. This is a preparation boundary, not the
whole-execution workspace claim.

Whole JSON control work is independently 1037: two input and two output row
opens, two copies of name bytes `2 + 256 + 256`, and one non-NULL leaf probe
with one entry plus four bytes. Copying outside take does not add a second
cell-entry charge. At 1036 the fixture fails with `Rows(RowLimit)`; 1037
succeeds for each quantum. No successful-run meter sets the expected limit.

The normal Programs use Values -> JSON Pick / fixed Watermark / Lag ->
derive -> select, with an ordinary unique-row assertion for Lag ordering.
`public-property-name-retention.test.mjs` goes through Embedded Local, the
real retained Store and committed Named Result readers. Source and generated
names are 513 units. Handwritten expected rows are:

- JSON: `(1, 7), (2, NULL)`.
- Watermark: `(1, false), (2, true), (3, false)`.
- Lag: `(1, NULL), (2, 95), (3, 100)` in original occurrence order.

Each case checks the exact three public names and their declared types, two
consumers, repeated-request dispatch reuse, delivered post-progress
cancellation, no early physical-stop confirmation or custody release, no
partial publication, no extra dispatch/advance and final Store reclamation.
The resource inventory requires generated metadata quantum, stop and public
roles for all three operations and the independent JSON limits. Removing any
required role makes the focused checker regression fail.

## Executed checks and limits

Diagnostic evidence is retained locally under `_build`, not committed.
The pre-fix JS regression failed 0/1 at the initial metadata assertion
(`run-hHaLFW`, `focused-test-PNly5D`). The implementation batch passed 24/24
on JS (`run-a6VV4N`, `focused-test-HJjrUY`), including existing JSON,
Watermark, Lag and order metadata tests. This batch preceded the final main
merge; it is not relabeled as evidence for a later clean SHA.

After integrating main, the selected JS runtime build passed
(`run-XkN6OE`), and the three public Host cases plus missing-evidence
regression passed 4/4 (`run-UqqVW2`, `focused-test-ZS4uv2`). These checks ran
on the implementation working tree based on
`3d596fa29ff23dba40d891d06eef1057389f0c3d`, before its implementation commit.
The PR records the submitted clean SHA and its focused results separately.
Ignored runtime assets were regenerated from integrated source, not committed.

Not executed here: full Core, Wasm/Native execution, packed/HTTPS campaigns,
performance measurements or proof campaigns. Draft CI is not merge evidence.
Native capacity census and observer correspondence remain unreviewed: the
state now borrows `metadata_source`, tracks generated-role index/seen mask
and uses typed cached source roles. G must review these concrete differences
together with #704/#708, rather than refreshing pins without a premise check.

Remaining start-time KernelBody/path copies, producer preparation,
availability validation and the installed projected-read metadata ceiling
remain separate. This unit does not claim all-start boundedness, all Local
completion or Native physical capacity certification.
