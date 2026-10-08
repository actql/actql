# Quoted window function names in QUALIFY

This independent Frontend unit starts from main
`861715d844b1835615bccf57f80affcc856e4696`. It does not depend on the
quoted scalar or aggregate changes and does not add analytic signatures.

## Requirement and fixed counterexample

`docs/spec/query-text.md` requires QUALIFY calls to use the same supported
inline OVER signatures and common analytic contract as SELECT. The selected
GoogleSQL reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:

- [Parser](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/parser/googlesql.tm):
  function calls use identifier paths, including decoded quoted identifiers.
- [Resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc):
  `GetFunctionNameAndArguments` uses `ToIdentifierVector()` for ordinary
  catalog function lookup. Quotation does not select a new window operation.

```sql
SELECT x FROM t
QUALIFY `ROW_NUMBER`() OVER (ORDER BY y) <= 1
ORDER BY x
```

With rows `(x=1,y=20)` and `(x=2,y=10)`, the independent result is `x=2`.
The expected complete Program uses Values, row_number ordered by y, a filter
on its evaluated private slot, projection of x, explicit sort, and Named
Result. The ordinary checker accepts that Program and the unquoted control.
Before the fix, the quoted source is incorrectly rejected with
`QUALIFY requires a window function`.

The explicit pre-fix receipt is `_build/local-checks/attempts/run-wekh17`
(one test, zero passed), with focused evidence
`_build/focused-evidence/focused-test-xd57sG`. An earlier generic unwrap
receipt, `run-30KMrd`, is retained separately; it does not provide the same
precise diagnostic. Expected Programs and result fixtures were not obtained
from compiler output.

## Minimal connection and retained owners

Only the name-token pattern in `QueryParser::qualify_expression` changes:
the existing seven-name window table accepts `Word` or decoded `QuotedName`.
The following opening parenthesis is still required. Existing expression,
OVER, alias, scope, hidden projection, signature, checker, planner and Host
owners remain responsible for their current contracts.

Unknown names do not gain a namespace. A quoted column named ROW_NUMBER is
still a column when no call follows. Invalid rank/row_number arguments and
three-argument LAG retain `UnsupportedAnalytic`; missing OVER retains the
existing syntax refusal. No CTE, predicate, assert, Effect, common execution,
wire, machine contract, structural grammar, identity preimage or pin is changed.
This unit connects nonaggregate window calls; quoted aggregate handling is a
separate unit.

## Verification and public obligations

- Corrected working tree: **12/12 JS tests passed**, selecting only the new
  parser/complete-Program/signature tests and existing QUALIFY alias/scope
  controls. Receipt `_build/local-checks/attempts/run-DeATRo`; focused
  evidence `_build/focused-evidence/focused-test-A1Ljq5`.
- Pinned direct moonfmt formatted the three changed MoonBit files. Fixture
  Node syntax and `git diff --check` passed. These are pre-commit working-tree
  results, not exact-clean-HEAD package, CI or backend conformance evidence.
- The existing public QUALIFY fixture adds mixed-case and escaped quoted
  hidden ROW_NUMBER, quoted RANK preserving duplicate rows, and a quoted
  window-name column control. Three invalid signature/OVER cases are added.
  The default corpus and existing `--qualify-only` selector both include
  **20 successes, 8 preparation refusals and 1 demanded execution failure**.
  Original cases, independent rows, column order/types, NULL checks, stream
  completion, acquisition counts, retries and refusal I/O checks are retained.
- Normal five-package generation and packed Embedded Local/HTTPS execution
  for this source remain unverified. No failed case is excluded and no
  post-lowering Program correction or alternative runner is introduced.

Keep Draft until public execution and applicable review/CI are recorded.
Reference inspection and selected tests do not establish full GoogleSQL
conformance, full Core, Wasm/Native or broad packed acceptance.
