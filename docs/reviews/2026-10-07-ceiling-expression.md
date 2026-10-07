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

## Fixed distribution and failed public boundary

Implementation/package source: `aa25a420683ff1980c0173c2349f3b5878f325b4`.
Five packages were normally packed with prepack enabled into
`/private/tmp/actql-b-ceiling-aa25a4206-pack`. Its manifest records that revision
and the following SHA-256 digests:

| Package | Digest |
|---|---|
| client-wire | `1702b53d4d6ed0596966ef37df25d0057afc08005ca190037574207278f9e281` |
| sdk | `43b6d6bfb498c7a72d7f0481393cb080cc045bd77dec42c8a0db7f7bada61713` |
| run-host-core | `c30ec73dbc24d074d9d887b0eaab3387b95d55cd4b5ac11879cfe5775f7542de` |
| local-node | `a142c5fbf9d21fe020793977d067cb03ce47f38f39ec4e25fc599e7a6339230c` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-ceiling-aa25a4206-pack
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
  npm_config_offline=true npm_config_include=optional \
  ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-ceiling-aa25a4206-pack \
  node scripts/test-packed-public-query.mjs --ceiling-only
```

The external installation uses no MoonBit toolchain at runtime. The wrapper's
11 profile/routing checks, README Local/HTTPS Named Result quickstart and missing
asset refusal smoke passed. The changed ceiling corpus did **not** pass:
`packed-local-ceiling-json-control` returned `SubmissionUnknown`, caused by
`ClientHostFailure` (500). No ceiling source success, preparation-refusal matrix,
execution-failure assertion or HTTPS ceiling execution was reached.

Evidence:
`worktrees/.codex-scratch/public-query-evidence-E5jMc8/008.stderr.log` and
`summary.json`; command 008 exited 1 after 1,402 ms. Logs, package digests and
command results were saved, then the private installation was automatically
removed (`artifactsRemoved: true`, `evidenceErrors: []`). The evidence's general
source `dirty` flag reflects protected untracked review artifacts; the producer's
tracked sources/build inputs were clean and its manifest revision was not edited.

## Common-owner handoff: existing FLOOR lowering is absent

A focused diagnostic uses the bridge produced by that normal pack and the
existing `sourceFreeValuesPlan` / `runtimeCore(...).publicationControl` boundary.
It adds the same Graph construction capacity declarations required by the
installed Host, without changing any capacity or numeric limit to admit CEIL.

| Input | Ordinary preparation | Existing Run compilation |
|---|---|---|
| Independent JSON ceiling control | ready | `RunHostCompilationRejected` / `ExpressionNotImplemented("floor")` |
| `SELECT 2.3 AS value` | ready | Plan issued |
| `SELECT FLOOR(2.3) AS value` | ready | Same `floor` refusal |
| `SELECT CEIL(2.3) AS value` | ready | Same `floor` refusal |

The root chain is Values compilation → Plan Graph → Fragment → AoA pipeline →
sequence kernel 1 → expression lowering. `src/lowering_relation/expression.mbt`
rejects `floor` in `check_supported_tag`; its `UnaryOperator` and the common
execution unary handler have no floor case. This is an existing common execution
gap, not a failed CEIL formula, parameter problem or source acquisition problem.
A should own the common lowering/evaluation connection and its bounded execution
regressions. B does not add a frontend evaluator, remove the operation, alter
expected rows, raise a ceiling or route these cases through another compiler.

Minimal independent common Program (expected `[{"value":2}]`, nonnullable number):

```json
{
  "version":"actql/0.1", "id":"fixture.floor_probe",
  "stages":[{"id":"main", "inputs":{}, "steps":[
    {"as":"seed", "values":{"schema":{"unit":{"type":"boolean","nullable":false}},"rows":[{"unit":true}]}},
    {"from":"seed", "derive":{"value":{"floor":{"literal":2.3}}}},
    {"select":["value"], "as":"selected"}
  ], "results":{"rows":{"from":"selected","fields":["value"]}}}],
  "results":{"answer":{"from":{"stage":"main","result":"rows"}}}
}
```

The retained diagnostic is
`review-artifacts/b-resume-2026-10-07/ceiling-preparation-probe.mjs`; invoke
`node review-artifacts/b-resume-2026-10-07/ceiling-preparation-probe.mjs` after a
normal runtime build. `ceiling-plan-probe.log` contains the full nested cause;
`ceiling-plan-final-probe.log` retains the positive control and compact floor
refusals. Earlier import-path/environment setup errors are separate diagnostic
logs, not product failures. This diagnostic is an internal boundary probe;
it does not establish HTTPS execution or successful public acceptance.

## Completion and remaining work

Frontend syntax/lowering and independent fixtures are ready for review; public
execution remains incomplete and the PR stays Draft. The 12 normal / 7
preparation-refusal / 1 execution-failure cases per transport remain unchanged
acceptance obligations. After the common floor connection is available, adopt
its fixed SHA and rerun this same public selection from normal distributions.
The failed invocation is not a substitute for those obligations or CI success.
The submitted follow-up documentation commit does not change package build
inputs; no public success is attributed to that later HEAD.

## Subsequent main integration

Main advanced while the fixed distribution was being exercised. Adopted the
additional main `0d65b7bb0e06f788b993fa2fb66ae99713b6a97e` by normal merge,
without conflicts or rewriting existing declarations/pins. This includes the
merged delimiter-chunk unit #718, row-metadata preparation and new common Table
contracts. These changes are not represented by the earlier aa25a4206 package
manifest; no old package/Run identity is reinterpreted as the integrated HEAD.

On the integrated source, the same focused JS selection passed 6/6
(`_build/focused-evidence/focused-test-tCJdyf`) and Node selection passed 6/6
(`_build/focused-evidence/focused-test-du9yEp`). JS ran at unpublished merge
`7f5701ecdf57868bc9f27a25c39f183dc24f739f`; its title was corrected to Conventional
Commits before publication, yielding `2565f2aa0aa190fcc75b0b48b7e6a081a3957d40`.
Both Git trees are exactly `5061504534679620024e8b7a5f55bbb74ea7ed54`; the Node
check ran at the latter SHA. No source was edited during either gate. The final
report commit changes only this documentation. The integrated HEAD has not been
repacked or publicly accepted; the existing floor execution gap remains open.

Automatic CI for the pre-integration submitted
`1cdacab7a66a3fd2ab49be70891135ca79a87d7f` completed with
[run 37556896889](https://github.com/actql/actql/actions/runs/37556896889).
`select-targets` failed with no steps, final `check` failed and all 26 other jobs
were skipped. This is not product-job success or evidence that the new code
caused the startup failure. No manual rerun was requested.
