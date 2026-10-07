# Frontend expression reuse: admitted numbers and resolved references

Baseline: `c2c2e12a8edf6c097d73662ea349025f2be7e715` (main).
This is a local Frontend connection fix, independent of ARRAY execution issue
[#784](https://github.com/actql/actql/issues/784). It changes neither the common
expression owner nor the machine value/type contracts.

## Counterexamples and selected contract

The initial audit found that an ordinary GROUP BY alias already resolves to its
SELECT expression. No change is required to that path. The independent numeric
counterexample exposed a different boundary:

```sql
SELECT x + 1.0 AS next, COUNT(*) AS n
FROM t GROUP BY x + 1e0 ORDER BY next
```

Both literals have the same admitted finite Number value. The original
`same_expression` compared their token text and therefore failed to reuse the
grouped value. The pre-fix focused run executed two tests: one passed and the
positive independent-Program test failed at compilation. The fix checks both
literals with the existing `query_expression.numeric_literal` owner and compares
the admitted values. Failed admission never establishes equivalence. Different
values and unsafe integer tokens remain rejected through the existing rules.

The selected GoogleSQL reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`.
Its [expression matching implementation](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/expr_matching_helpers.cc)
compares resolved literal type and value. The counterexamples use FLOAT64
spellings on both sides, without claiming that the current finite Number
profile implements exact INT64 or all GoogleSQL coercions.

A second counterexample still failed after the numeric correction:

```sql
SELECT DISTINCT x + 1.0 AS next FROM t ORDER BY t.x + 1e0
```

The original ORDER comparator required identical reference spelling even when
`x` and `t.x` resolve to the same physical input. Reuse now uses the existing
receiver-prefix and property-path comparison after proving that ORDER's
alias-first reference has the same meaning as its input reference. Unknown
receivers do not establish equality. Different ranges or properties remain
different; an output alias that displaces an input still prevents reuse.
No removed column is reconstructed, and SELECT is not evaluated twice.

Independent complete expected Programs cover GROUP and DISTINCT, including
their evaluated slots, COUNT, sorting and exported column order. They are
authored directly rather than captured from compiler output. Existing
alias/property/aggregate/JOIN ORDER regressions remain in the selected tests.

## Public acceptance and identity

The existing GROUP SELECT public fixture adds one independent JSON control and
four authored SQL cases: numeric GROUP reuse, nullable GROUP reuse, qualified
DISTINCT reuse with LIMIT, and an alias collision that reverses the order if
SELECT is incorrectly reused. Two additional preparation refusals cover a
different unselected expression and an inadmissible integer token.

Run the same ordinary packed harness, with its existing narrow selection:

```sh
node scripts/packed-client-packages.mjs /tmp/actql-expression-reuse-pack
ACTQL_PACKED_CLIENT_PACKAGES=/tmp/actql-expression-reuse-pack \
  node scripts/test-packed-public-query.mjs --group-select-scope-only
```

This selected corpus has 13 positive and 7 refusal cases per Local/HTTPS path.
The ordinary campaign also includes every added case. Expectations retain
NULL, COUNT multiplicity, Result.describe type/column order, hidden-field
exclusion, one Source acquisition, no extra work on reattach/resend and no Run
admission/provider I/O for preparation refusals. The test does not patch a
lowered Program or alter ceilings.

The grammar, normative specification and common contract bytes are unchanged;
no pin/vector regeneration is warranted. Previously accepted machine Programs
keep their existing identities. Previously rejected equivalent source trees now
lower to the existing ordinary Program meanings.

## Source-preparation verification record

- Before the fix: focused JS 1/2 passed, with the numeric GROUP positive failing.
- After the numeric fix: selected GROUP/DISTINCT scope JS 13/13 passed.
- Adding the qualified DISTINCT counterexample: focused JS 2/3 passed, with
  that new positive failing; the numeric GROUP case remained successful.
- After both connection fixes: focused JS 23/23 passed across the new file and
  DISTINCT, property ORDER, aggregate ORDER and JOIN DISTINCT consumers.
- Public-fixture and ordinary-campaign registration: focused Node 2/2 passed.
- Public packed execution, submitted-SHA CI and Wasm/native execution were
  pending at this source-preparation checkpoint. Subsequent fixed-SHA evidence
  is recorded in the PR body; local JS success does not establish these boundaries.

The retained logs are `/private/tmp/actql-b-group-numeric-before.log`,
`/private/tmp/actql-b-group-numeric-after.log`,
`/private/tmp/actql-b-group-numeric-final.log` and
`/private/tmp/actql-b-expression-reuse-final.log`, with bounded wrapper receipts
under this worktree's `_build/local-checks/attempts` and `_build/focused-evidence`.
