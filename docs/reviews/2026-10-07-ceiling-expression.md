# CEIL / CEILING: connect the existing finite-number expression contract

## Selected semantics and scope

Adopted main: `b5a3f9e18d8f87566a0a968771be4a83e7db43a5`.
The pinned GoogleSQL reference `d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/mathematical_functions.md`, defines CEIL as the least integral value not
less than its operand and CEILING as its synonym. The
[official function reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#ceil)
also lists domains beyond the currently admitted ActQL number profile.

This unit connects one finite binary64 number operand, including strict NULL
propagation, to the existing common expressions:

```json
{"negate":{"floor":{"subtract":[{"literal":0},{"field":"amount"}]}}}
```

For every finite admitted operand, subtraction from numeric zero gives its
exact negation; flooring and negating gives the ceiling. Negative zero follows
the existing normalized-zero number contract. The operand occurs once. The
numeric zero supplies ordinary peer typing for an untyped NULL; simply nesting
negate around NULL would lose that typing context. Both spellings use the same
expression without a new operation, evaluator, wire form, contract pin or Owner.
Common checking rejects nonnumber/decimal operands and validates parameters.
Decimal, nonfinite values and the other GoogleSQL overloads remain unsupported;
this is not a claim of complete GoogleSQL numeric conformance.

## Independent regression and acceptance obligations

The complete independent Program is parsed and normally checked before
comparing Frontend output. Before the fix, the number Program passes common
checking but `SELECT CEIL(2.3) AS value` fails query compilation. The red 0/1
regression is retained in `_build/focused-evidence/focused-test-hFzzR4`.

The explicit tree fixtures check one occurrence of the operand, lazy IF input,
parameter identity, exact arity and qualified/quoted function refusal. Complete
Program/checker fixtures cover positive/negative operands, NULL and invalid
number overloads. No expected Program is generated from compiler output.

The authored public cases cover SQL/Pipe, independent JSON control, positive and
negative fractional values, integral values, smallest/largest positive finite
binary64, untyped and typed NULL, nullable parameters, lazy and demanded errors,
empty results and duplicates. Alias-first and qualified-input ORDER produce
opposite orders. The shared acceptance harness checks Named Result rows and
Result.describe column order/type/nullability, private-column absence, stream
completion, one source acquisition, same-request Run identity and reread/attach
without repeated acquisition. Preparation refusals retain zero Run admission
and zero provider I/O. The same cases are registered in ordinary packed
acceptance, with `--ceiling-only` selecting them locally.

The adjacent unary-plus registration test assumed its selector was the first
term of a boolean/list expression, although adopted main already put other
selectors first. It now checks membership, retaining all normal/focused corpus
assertions. The initial focused Node invocation (5/6) and correction are
recorded separately; this is not a product unary-plus behavior change.

## Verification record

Focused JS: 6/6, evidence `_build/focused-evidence/focused-test-9jGjSg`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_expression/ceiling_test.mbt src/query_program/ceiling_test.mbt \
  src/query_program/unary_plus_test.mbt
```

Focused Node: 6/6, evidence `_build/focused-evidence/focused-test-1x2Meq`:

```sh
node scripts/local-checks.mjs test node -- \
  scripts/ceiling-source-input.test.mjs scripts/unary-plus-source-input.test.mjs
```

The final registration-matching wording is included in that Node result.
Clean-revision public execution is recorded below after its actual invocation. Core-wide, Wasm/native,
proof campaigns, Cloud, performance and the full packed corpus are not claimed.
