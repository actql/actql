# Frontend ORDER column positions

## Selected existing-contract boundary

Baseline: `605d42356c29ff926e046e73a87a54cf3a420f0a` (`origin/main`).
This is an independent Frontend repair, with no dependency on the DISTINCT
output-expression repair in #338. It does not reopen the completed semantic
audit or assert completion of every Frontend feature.

| Boundary | Current evidence | Action / ownership |
|---|---|---|
| ORDER expressions after DISTINCT | Separately repaired in #338 | Keep its evidence and submitted-HEAD CI separate |
| Integer ORDER positions | SELECT treats them as constant expressions; set ORDER refuses them | This unit: B's lowering connection to existing named-field sort |
| GROUP BY integer positions | `group_key_expression` explicitly refuses them | Separate Frontend coverage item; not implemented by this unit |
| Graph row definition/label and Traverse node selectors | Existing public source paths are integrated on main | Reuse them; no second Graph bridge or runtime |
| Shared CTE predicate capture | D's repair is integrated on main | Preserve the existing owner; this unit exercises shared CTE consumers |
| INFER / NEAREST execution, composition and recovery | Separate common-owner/public-connection units | No replacement executor or speculative completion claim |

Before repair, both selected counterexamples fail (`run-cT5oWv`, 0/2):
`SELECT y, x FROM t ORDER BY 2 DESC, 1` does not emit the required named-field
sort, and the equivalent set ORDER rejects. A constant ORDER key can preserve
the wrong input order even though parsing, checking and execution succeed.

## Adopted rule and primary references

The selected GoogleSQL source is
`d82db99a923a46571f543a13899dc791a7b6f743`, already pinned in the workspace
reference inventory. These are reference requirements, not expectations
generated from ActQL output:

- [ORDER BY column positions](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#order_by_clause): integer literals count from one in SELECT output order.
- [Pipe ORDER](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#order_by_pipe_operator): the same ordering rule applies to the current Pipe output.
- [Independent analyzer cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/orderby.test) reject zero, negative and out-of-range positions and noninteger literals.
- [Pipe position cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/pipe_order_by.test) use visible output order, rather than private physical columns.
- [Literal resolution](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc) and [unary resolution](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc) distinguish positional integer literals from ordinary expressions and explicitly typed values.

`ORDER BY (1)` and unary `+1` retain the integer-literal meaning. Decimal and
exponent-spelled literals, strings, booleans and NULL are not positions or
silently accepted constant sort keys. A directly negated numeric token is
rejected. Arithmetic such as `1 + 0`, a parameter, an explicit CAST, or
negation of a parenthesized expression remains an ordinary expression; this
repair does not invent general constant folding. Hexadecimal numeric token
support is outside the current lexical subset and this unit.

## Implementation and independent obligations

`query_order_ordinal.mbt` is one private resolver over the existing source AST.
It bounds decimal accumulation by the visible column count before multiplying,
without converting a position through floating point. Existing source, token
and expression limits still bound its work. It returns an already evaluated
output name; it does not build a second expression parser or expression owner.

The ordinary SELECT, scoped Pipe, JOIN and combined-set ORDER paths call this
resolver. Deferred SELECT mappings still use their existing physical slots;
ordinals do not duplicate SELECT expressions. Current Pipe columns determine
positions after SET/DROP/RENAME. Snapshot ranges and hidden helpers are excluded.
Combined-set positions use the left output's declared column order, never an
operand's private input. ORDER direction and NULL placement are unchanged.

The independent complete Program fixture spells `sort.field` as `x` then `y`
for `SELECT y, x ... ORDER BY 2 DESC, 1`. Caller tests include computed SELECT,
DISTINCT, GROUP output, SELECT star, JOIN and CTE JOIN, valid parentheses/unary
plus, noninteger/invalid/huge positions, and ordinary arithmetic. The old set
refusal list removes only the two valid ordinal cases; its removed-column,
range and invalid-literal refusals remain.

The public corpus is authored separately in
`scripts/fixtures/order-ordinal-source-input.mjs`. Input amounts are 2,2,1,NULL
and an excluded 99. SELECT negates them once; ORDER position 1 is `score`,
position 2 is `id`. With NULLS FIRST, second-key DESC and LIMIT 3 the expected
rows are:

```json
[{"score":null,"id":4},{"score":-2,"id":3},{"score":-2,"id":1}]
```

It includes a hand-authored machine Program, SQL/Pipe, shared CTE JOIN,
UNION ALL duplicate rows, DISTINCT, empty input, and current Pipe scope. The
existing packed consumer checks Named Result rows and ordered full column
contracts, complete reads, one acquisition session, request/Run reuse, and
no additional acquisition on attach/resubmit. Invalid positions require zero
Run admission/provider I/O and the existing typed input error codes. No
test-side Program correction is allowed. The corpus also joins ordinary CI's
public-query cases; `--order-ordinal-only` merely selects it locally.

## Verification record

- Focused JS ORDER selection: **33/33** (`run-7CNwof`).
- Node public-case merge controls: **2/2** (`run-LLVp8E`).
- Pinned Moon formatting, Node syntax and diff checks pass.
- Fresh packed Embedded Local/HTTP: **8 positives and 5 pre-admission refusals
  per transport pass** at `24caaf26d789e68cd762b7e1d43260a8a6d4fa24`.
  Evidence `public-query-evidence-OPpnfU` is complete/passed with no evidence
  errors. The acceptance child (012) exits 0, signal null, with complete output.
  Ordinary prepack builds all five packages; the consumer runs outside the
  checkout without a MoonBit runtime. Successful temporary installations are
  removed after evidence and digests are retained.
- No full local Core, all-target, proof, performance or manual CI rerun.

| Normally packed package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| actql-sdk-0.0.0-development.tgz | `494cafc4a5e4615dc47bba3b46bfd3c163c06690a258c8e619cc13a4198b2123` |
| actql-run-host-core-0.0.0-development.tgz | `26032d6a2baa9798a093dc5be5293b757fd75232eb817368cef9f5aa012c8d91` |
| actql-local-node-0.0.0-development.tgz | `b0df338e753f11d7d98ca3e199e44edaa7a3e5ac118e024a143275a794a97cc6` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Reproduce with the repository-pinned toolchain:

```sh
node scripts/test-packed-public-query.mjs --order-ordinal-only
```

This result belongs to the verified product SHA above. A following evidence-only
commit does not relabel it as a fresh packed run of the final submitted HEAD;
that HEAD's integration and normal public corpus are checked by automatic PR CI.

Subsequently integrated main:
`4cd79be2d720d60288c2816aee318aeb7bd2b3e6`, by normal merge without conflicts.
It adds E's separate nested supplied Check diagnostics. Frontend repair,
fixture and acceptance-driver bytes are unchanged by the merge. Its public
Check bridge changes are retained; the earlier packed result is not relabeled
as validation of that later bridge. No broad local rerun is added solely for
the integration; submitted-HEAD CI covers the combined tree.

No common checker/planner/provider, Run/Effect owner, SDK or transport is changed.
The existing grammar already parses these expressions; no grammar, wire,
schema, contract version or canonical law changes are introduced. Corrected
generated Programs have their ordinary identities; stored Programs keep their
existing meaning. Former constant-literal ORDER behavior is not preserved as
a compatibility fallback. Public execution and exact submitted-HEAD CI remain
distinct from source parsing and focused checker evidence.
