# Positive navigation offset connection

Source baseline: `195fc902a6041432190d9f84272d47ce4bb2622b`, independently
confirmed as public main through the GitHub branch API. Ordinary SSH fetch
failed with DNS resolution; the exact matching commit was already present in
the shared local Git object database. No submitted predecessor branch changed.

## Counterexample and selected meaning

```sql
SELECT id,
  LAG(amount, +2) OVER (ORDER BY id) AS previous,
  LEAD(amount, +@p) OVER (ORDER BY id) AS next
FROM orders ORDER BY id
```

The baseline parser already emits numeric `Unary("+", child)`. However,
`query_program/query_analytic_offset.mbt::lower_analytic_offset` handles
parentheses, a Number atom and a whole Parameter reference, then rejects unary
plus as `UnsupportedAnalytic`. The baseline's grouped-offset test explicitly
expects `(+1)` to be refused. These are source-derived counterexamples;
baseline compilation and public Run execution have not been performed here.

The selected GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`:

- [Integer lexical forms](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md#integer_literals)
  admit a positive sign.
- [Navigation functions](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/navigation_functions.md#lag)
  require a nonnegative integer literal or parameter for the offset.
- [The numeric unary-plus resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc)
  resolves and retains the numeric operand without constructing another
  evaluation node. It rejects nonnumeric operands and literal NULL.

The Frontend now traverses parentheses and unary plus in the same bounded
offset walk. A Number stays a Number; a numeric parameter stays the existing
whole parameter reference. Each wrapper consumes work and preserves its
original source origin. No arithmetic evaluation, literal folding, new cast,
analytic owner, parameter contract or execution path is added. Dynamic fields,
arithmetic, NULL, nonnumeric atoms, unsafe/fractional literals and invalid
bound parameter values retain their existing refusals. The existing negative
zero and parenthesized-negation support distinctions are unchanged.

This PR is independent of the unmerged hexadecimal literal PR #1465. Its
offset atoms use the baseline decimal admission, so it does not claim hex
execution. The later integration should keep both the transparent wrapper walk
and #1465's exact token decoder.

## Independent expectations and public preparation

Four authored MoonBit tests compare SQL/Pipe to the complete independently
written Program in `grouped_analytic_offset_test.mbt`, check parameter refusal,
zero/safe bounds, exact failure classifications and work exhaustion. The prior
`(+1)` refusal was removed because it is the connection repaired here; all
other prior grouped-offset refusals remain.

The existing `analytic-offset` public cohort remains five normal cases:
independent JSON control, SQL literal/parameter, Pipe parameter/literal,
zero-offset duplicates and typed empty input. Four source variants now use
positive wrappers. The independent expected Program, source rows, parameter
values, expected rows, ordered full schemas and one acquisition-session counts
are unchanged. They remain separately authored in
`docs/reviews/fixtures/analytic-offset.expected*.json`. Four added refusals
exercise `+(id)`, `+(@p + 1)`, `+NULL` and `+(-1)` with the existing
`ClientProgramInvalidInput` public projection. The existing normal corpus and
`--analytic-offset-only` already register this fixture; no driver or selector
was added. The prepared cohort is **5 normal + 13 refusal** per transport.
Attach/resend/lookup, Result values and schemas, refusal admission/I/O counters
and cleanup remain the existing consumer's obligations, not successful evidence
in this PR yet.

`baseline-public-inventory.json` preserves main's 3916 declarations.
`registered-public-inventory.json` enumerates source declarations only:
3920 occurrences, 2469 normal / 50 execution-failure / 1401 refusal and digest
`17e67cb1c80681c7b6a8fa1481fc2d4fced1748e875f947b270c0c5785902697`.
These are registration counts, not executed tests. No expected product rows
or schemas were regenerated from product output.

## Normative identity closure

The query rules document is part of the grammar manifest. Existing generators
updated that manifest, its normative imports and canonical vectors; the grammar
EBNF and common expression/analytic contracts did not change. The manifest CID
is now `sha256:1c6f5352332aa0f32e2e8aede213f34fd1a97bbda86b6a56a64fb90a6d007a15`.

`identity-preimage-preparation.mjs` evaluates only the independent, normative
preimage oracle declarations, without registering tests or importing the
product compiler/evaluator. Complete old inputs are preserved in
`scripts/fixtures/pre-positive-navigation-offset-values-identities.json`.
The old Values Run `sha256:eb21384725cf00fd1f92cd651308d9918cd713547fce1aacdd35fb0b34212290`
remains an explicit historical assertion. `current-values-preimages.json`
records the independently calculated new template, executable/compiled plans
and Run `sha256:70d2caa120943cdf754c434673b32d75e0c0af31e3617ffc0182f403e469141f`.
Both current Node assertions, dependent plan assertions and the MoonBit
consuming Run assertion follow those preimages. Program/Unit/ResultPlan
definition and dependency bodies are unchanged; grammar-bound invocation and
execution identities change. Old persisted Runs are not reinterpreted.

## Executed evidence and unverified coverage

- `generator-checks.json`: actual source generators, all exit 0.
- `format-syntax-checks.json`: four individual pinned `moonfmt -w` invocations
  and six pinned Node syntax checks, all exit 0. The preceding incorrect
  `moon fmt -w` invocation exited 2; its failure is retained and is not a pass.
- `static-checks.json`: read-only source/pin freshness and links checks.
- `git diff --check`: completed without errors.

No compiler, MoonBit runtime test, Node test, Wasm/Native caller run, package
producer, public Local/HTTPS consumer or CI gate was executed for this unit.
No shared API changed, so no hand-written or newly generated interface is used.
B's earlier process-inspection automatic rejection is not retried or bypassed.
`prepared-checks.json` gives the existing bounded focused commands for Root's
independently authorized review worktree. Shared Heavy is unreserved, the
original producer/public 300-second caps and current resource ceilings remain,
and no new public execution is started by this preparation.
