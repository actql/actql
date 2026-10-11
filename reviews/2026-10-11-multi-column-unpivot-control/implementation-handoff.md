# Multi-column UNPIVOT frontend connection

Status: implementation prepared on adopted main
`54630b093276191b88b7b5bb7d99f4d31db48d63`; normal merge
`325eb40eaeafb9989cd241bce935bea1d19ce1d7`. This is a separate unit from
completed String row-value aliases (#1407). No common Owner, evaluator, cast,
wire format or nullability rule changes are included.

## Connection and independent obligations

The parser retains ordered output names and ordered input tuples. The lowerer
resolves each current input slot, constructs one non-NULL closed object per
input tuple, projects the selected bundles, calls ordinary common UNPIVOT, and
projects each child via ordinary property expressions. EXCLUDE uses the OR of
component IS NOT NULL predicates. It never tests the non-NULL bundle receiver.
Fresh output scope contains kept inputs, positional outputs, then the name
column. Default labels join current resolved column names, not internal slots.

The complete eight-step Program expectation is authored independently in
`src/query_program/unpivot_multicolumn_test.mbt`. The direct connection has an
independent five-step wire expectation in `unpivot_multicolumn_wbtest.mbt`.
The new public fixture declares seven normal and six refusal cases, including
ordinary JSON controls, DATA/SQL, Pipe/fresh range, current RENAME labels,
partial NULLs, all-NULL exclusion, duplicates and typed empty output. Existing
packed registration, transport inventory and completion-data receipts are
reused. There is no post-lowering Program repair or new acceptance runner.

Corresponding positions with different nullability remain an unadopted common
contract gap. The refusal fixture supplies a valid non-NULL value for its narrow
parameter declaration; it cannot pass merely by rejecting parameter binding.
Different types, arity, output collisions, removed inputs and old ranges also
have declared refusal cases. Their public codes still require execution.

## Evidence separation

Root's byte-identical ordinary control passed JS 1/1 at Root HEAD
`6a193057661522ec10d096d85733d95b4f6b85b0`, run `run-hBDJmI`, original
60-second non-Heavy guard, exit zero and release. Root's record is
`reviews/2026-10-11-integration-owner/b-multicolumn-control-source.json` and
`b-multicolumn-control-check.log` in its independent worktree. This proves only
ordinary common checker acceptance. It is not evidence for this parser,
lowerer, evaluator or public Result.

B executed source formatting with the pinned standalone moonfmt, `node --check`
for the five changed fixture/driver/vector modules, and `git diff --check`.
The standard compilation-manifest, document metadata, family and canonical
writers were used. Read-only compilation freshness and canonical freshness
completed (510 canonical identities). These are generation/static checks,
not execution of MoonBit or Node test cases. The independent fixture enumerator
records 3,882 full-corpus occurrences with digest
`9c666ddb74b415adc888bdec6148be953c09f41e7840e029c837bb9eef6cb019`.

The preceding complete Values identity preimages are retained in
`scripts/fixtures/pre-unpivot-multicolumn-values-identities.json`. Current fixed
CIDs are derived from normative preimages by the existing independent oracle;
`identity-preimage-preparation.mjs` records that data-only preparation. No
compiler-issued CID or actual Result supplied an expectation. Grammar changes
alter containing invocation/plan/Run identities, not the Values Unit contract.

## Remaining checks and bounded handoff

B's prior guard rejection remains preserved; no retry or unguarded test/build
was performed. Compiler-produced `src/query_syntax/pkg.generated.mbti` still
needs the existing API-generation procedure; it is deliberately not hand-edited.
A coordinator-owned lightweight check may first regenerate this affected API
and run the selected files under its existing authorized guard:

- `src/query_syntax/unpivot_multicolumn_test.mbt` plus existing `unpivot_test.mbt`
  and `from_unpivot_test.mbt`.
- `src/query_program/unpivot_multicolumn_control_test.mbt`,
  `unpivot_multicolumn_wbtest.mbt`, `unpivot_multicolumn_test.mbt`,
  `unpivot_multicolumn_public_source_test.mbt`; existing single-column caller
  cases must remain intact.
- Node fixture/vector/inventory tests: `scripts/unpivot-multicolumn-source-input.test.mjs`,
  `scripts/client-values-run-materials-vector.test.mjs`,
  `scripts/public-query-profiles.test.mjs` (no packed producer invoked).

MoonBit compilation/test execution and these Node test cases are unexecuted by
B. Public Local/HTTPS values, schema, refusals and same-request behavior are
unverified. The existing packed entry is prepared as
`node scripts/test-packed-public-query.mjs --unpivot-multicolumn-only` with the
normal five-package manifest. No producer/public Heavy command was started;
existing 300-second producer/public bounds and shared-window coordination remain
unchanged. The completed #1407 cohorts, old failures and author070 are untouched.
No Ready transition, Hosted CI success, merge or full feature completion is claimed.
