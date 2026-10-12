# Retire unused Graph LABELS token metadata

Baseline: normal main `538c56e78f6f7f6a9d5e2c3f5074050c9e7adad6`.
The existing `scripts/frontend-profile.test.mjs:295` cutover assertion fails
because the generated syntax API still exposes `Token.annotation_compatible`.
The current-main counterexample is `run-skBsmh`: Node 9/10, exit 1. Its original
receipt, API and lexer are preserved in
`/Users/t14i/workspace/20260822/reviews/2026-10-13-b-retired-annotation-evidence`.
This independently confirms the earlier #1786 inherited failure; it does not
retarget or erase that failed aggregate.

The flag was introduced with the historical Graph LABELS annotation profile
at `48cfd20377bbe230799ced6a1a43dae1770787db`. Its only semantic graph-text
reader was removed by the WITH/Graph cutover at
`7de5fd69f9ee47841ccb8415964e57694e514764`. A current-tree search finds writes,
private tuple transport, the generated field and the existing retirement test,
but no semantic reader. Remove the flag, its compatibility-only computations
and the corresponding unused tuple component. Keep the original assertion.

`StringLiteralOrigin.raw` and `.backslash` remain current input-spelling evidence
for LIST_FILES. Retain them for each adjacent chunk, including raw/triple and
quoted spelling. No decoded value, delimiter, error branch, start/end offset,
UTF-8 accounting or logical-work charge is changed. No grammar/rules/pin,
Source request, Selector, Common Owner or Vector contract is changed.

The API field removal is generated with the pinned compiler using
`prepared-checks.mjs --info` (JS `moon info src/query_syntax`). Only that one
interface line changes. The selected regression covers existing lexical
values, offsets, limits/refusals, raw/triple/JSON literals, quoted aliases/
aggregates/QUALIFY, LIST_FILES chunk origins, and the unchanged cutover profile.
`prepared-checks.mjs` retains the existing 60-second, TERM-grace-5 non-Heavy
guard and nonzero-test wrapper. `--before` selects the current-main failing
profile without a compiler build.

No package producer, Native/Wasm execution, Hosted CI, Provider or new installed
public scenario is included. #1786 VectorScalar and #1780 Sequence remain fixed
separate branches and evidence. Their external Local/HTTPS acceptance is not
established by this metadata retirement.
