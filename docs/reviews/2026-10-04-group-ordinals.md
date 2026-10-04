# SQL GROUP column positions

## Adopted requirement and selected counterexamples

Initial parent: #348 at `79d6cf73be340edabea5d692f1273b3d9d178c18`.
Initial integrated baseline: `ae7007bdd987a26c9f866daa341e6b4996f82571`,
including main `04e0d806c7927c3aeb1f1dd9908eeb761f013473`.
Subsequently integrated parent #348 at
`0f04634056845ea17fc3f4ccc34245d89ef1363e`, which normally merges main
`8899d1041b390bb7c60742ce79277859e229da61` including merged #338.
Runner registration conflicts retain GROUP-star, GROUP-position and
DISTINCT-ORDER cases in both their narrow selections and ordinary CI corpus.
Main CI settings and existing history declarations are preserved.
This repair depends on #348's preserved pre-group visible column mapping.
It does not reopen the completed meaning-preservation audit.

The selected GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`:

- [GROUP column positions](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#group_by_col_ordinals): integer positions select expressions from the SELECT list, starting at one; positions and names may be mixed.
- [Independent aggregation cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/aggregation.test): positions count expanded star columns; invalid positions, untyped literals and aggregate positions are rejected.
- [Pipe AGGREGATE cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/pipe_aggregate.test): positional GROUP references are not allowed in the Pipe operator's scope.
- [Resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc): resolution separates selected expression positions from ordinary key expressions and Pipe aggregation.

Before repair, selected focused cases fail **0/3** (`run-bY1Paz`):

| Input, visible columns `x,y` | Actual defect | Required behavior |
|---|---|---|
| `SELECT y,x,COUNT(*) AS n FROM t GROUP BY 2,1` | Refused | Group by selected input expressions `x,y`; publish `y,x,n` |
| `SELECT *,COUNT(*) AS n FROM t GROUP BY 2,1` | Refused | Group by `y,x`; publish original input order `x,y,n` |
| `FROM t \|> AGGREGATE COUNT(*) AS n GROUP BY 1` | Accepted as a constant key | Typed `UnsupportedGrouping` refusal |

## Repair and semantic boundaries

`resolved_group_key` resolves SQL positions against the expanded SELECT list
without parsing a synthesized expression string. Named/computed selected keys
reuse the existing expression lowering and grouped-slot evidence. Star positions
refer directly to the original logical-name/physical-slot pair; the numeric
position is not recorded as evidence for a literal expression of that value.
This prevents `SELECT *,1 AS one` from substituting an input slot for constant 1.

Selected expressions resolve over the input snapshot, without a second lookup
through output aliases. Repeated selected expressions share the existing grouped
value; aliases do not cause evaluation twice. Scoped JOIN slots remain private.
Positions are decoded within the expanded output width; huge, zero, negative,
noninteger, out-of-range, aggregate and analytic references are rejected.
An ordinary arithmetic expression such as `1 + 0` remains an expression, while
SQL `SELECT 1 AS one ... GROUP BY 1` groups by the selected constant expression.
Pipe AGGREGATE does not inherit SQL SELECT's positional-reference rules.

All generated Programs use the existing builder, admission, checker, planner
and Host. No presence/key/order evidence, execution owner or checker is invented.
There is no provider, transport, public API, grammar, schema, law/version pin or
wire change. Stored Programs retain their meaning. Corrected generated Programs
use their ordinary canonical identities. D's CTE/assert/Effect implementation
and A/C's common owners are outside this diff.

The existing negative caller fixture changed from GROUP position 1 to position
2: position 1 is an adopted valid input expression; position 2 selects COUNT
and is invalid. This corrects an obsolete unsupported-feature assertion, rather
than weakening a rejection requirement or matching product-generated output.

## Independent Program and public expectations

`group_ordinal_test.mbt` contains a complete hand-authored expected Program for
grouping `x,y` and publishing `y,x,n`, checked by the ordinary checker. Other
focused cases cover alias collisions, expression reuse, mixed star/aggregate
order, star plus literal, CTE/scoped JOIN and exact refusal reasons.

`scripts/fixtures/group-ordinal-source-input.mjs` provides a separately authored
JSON control and text corpus. Input contains a NULL amount, duplicate ID 3 and
excluded ID 0; the independently calculated grouped output is:

```json
[{"id":1,"amount":null,"n":1},{"id":2,"amount":20,"n":1},{"id":3,"amount":30,"n":2}]
```

The existing packed consumer compares Named Result rows and `describe()`'s
ordered full column contracts. Other cases distinguish selected-expression
alias resolution, star positions and constant preservation; include scoped JOIN,
CTE, ordinary arithmetic and empty typed output. It checks one Source acquisition
per acquired input and same-Run resubmission without additional acquisition.
Refusals require the existing public input-error classification with zero Run
admission/provider I/O. The normal packed corpus includes these cases; the
local `--group-ordinal-only` flag only narrows execution. No post-lowering Program
correction or independent execution harness is used.

## Executed checks and remaining coverage

- Focused JS `*GROUP*`: **16/16**, including eight new positional cases and
  affected GROUP-star callers (`run-NMmsyI`).
- Existing JS `*group*` callers: **7/7** after the obsolete negative position
  assertion was corrected (`run-o2wlyG`). The preceding **6/7** result
  (`run-QZ1eBQ`) is preserved as the assertion correction's evidence.
- Node public-case controls: **2/2** (`run-kb1zT0`).
- After the current-parent integration, focused JS `*GROUP*` remains **16/16**
  (`run-iRVN1E`).
- Pinned Moon formatting, Node syntax and diff checks pass.
- Fresh packed Embedded Local/authenticated HTTP at
  `bf39d807dd5ad2253e9167727c61bad9b8d7970b`: **9 positives and 6
  pre-admission refusals per transport pass**. The complete
  `public-query-evidence-E7J4xm` receipt has no evidence errors. Acceptance
  command 012 exits 0, signal null, with complete output (50.0s). The installed
  consumer runs outside the checkout without a MoonBit runtime or fixture
  overlay. Successful temporary installations are removed after retaining
  SHA/digests, logs and complete receipts.
- Automatic CI at `875d543cb754b5e782842cbcab6c6b03eccecbc8`
  ([37189301150](https://github.com/actql/actql/actions/runs/37189301150))
  failed in preflight: the actual `bf39d807dd5ad2253e9167727c61bad9b8d7970b`
  dependency merge lacked a `package.json` resolution declaration. Product
  jobs were not reached; this is not a product execution failure.
- Append-only repair `f9f5afa60d0b1efd53cdd6a465f314a91d2cf222` binds the actual
  ordered parents, both maximal merge bases, parent/result blob and mode,
  and all 41 ancestral package source revisions. The actual retained-history
  validator passes; the focused history/foundation Node tests pass **194/194**
  (`run-cCRtKF`). No validator or inherited declaration was changed.
- The current-parent integration retains main's ORDER-position corpus together
  with GROUP-star/GROUP-position acceptance. Its submitted-HEAD automatic CI
  remains pending. No prior-SHA receipt is relabelled as new-HEAD success.
- Focused JS `*GROUP*` after that integration: **16/16** (`run-jz8qH2`).
- No full local Core, all-target, proof, performance or manual CI rerun.

Reproduce the selected public corpus using the repository-pinned toolchain:

```sh
node scripts/test-packed-public-query.mjs --group-ordinal-only
```

Normally packed distributions at the product SHA above:

| Package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| actql-sdk-0.0.0-development.tgz | `fe9a883871c2c506df607a21dc5431e9aa0e484bab9673dd44b32213a0ab074f` |
| actql-run-host-core-0.0.0-development.tgz | `9ae236c22d7bc32bbd9e6751eee0686cf7f6e2f65735ce90b5cab30c8b80f919` |
| actql-local-node-0.0.0-development.tgz | `a279a4c0f4d0d752160238b037d5698b00fefa942235bc9a8c89c937f052791a` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

This is one existing-contract Frontend coverage repair, not completion of the
entire GoogleSQL, Pipe or Frontend r1 profile.
