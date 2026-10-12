# F04: candidate binding through JOIN continuation

This is a finite follow-up to #1692, with the same roles and ordinary NEAREST
owner. The JOIN continuation previously passed no candidate inputs to
`compile_steps`: both the Relation and typed Vectors cases returned
`UnknownRelation`. The original valid-source failures are retained in
`run-QT7oDs` and the precise diagnostic run `run-m90NTY` (0/2).
The first prepared counterexample accidentally omitted the Pipe delimiter;
its parser failure `run-G2mpy4` is not evidence of a lowering defect.

`query_join_bindings` now binds NEAREST candidates through the existing WITH
input owner. Actual admitted Vectors metadata is forwarded through the JOIN
chain to its existing Pipe compiler. The shared row scope is selected for a
NEAREST continuation even after an initial SELECT, retaining the original
qualified roles, WHERE and LIMIT. No alias resolver, Source acquisition,
identity conversion, evaluator or order policy is added.

The two installed Values seeds remain shared when `candidates` supplies both
the JOIN right operand and the NEAREST candidate. Explicit JOIN ceiling 4,
metric dot, K 2, and checker step ceiling 20 are unchanged. The original
independent data has no matching JOIN keys (`q1` versus `a`/`b`): its expected
public rank rows are empty. Dropping that JOIN would produce ranks 1 and 2.
Public execution of this counterexample is still pending.

A third positive control checks SELECT-before-NEAREST: its evaluated `qid`/`v`
slots must enter the same shared JOIN row scope, and the output query key keeps
its declared name `qid`.

Working-source `run-DNKDAF` passed 15/15: the two counterexamples, original
WHERE/LIMIT and typed-set continuation controls, Pipe JOIN input scopes and
JOIN-chain consumers. This is distinct from later fixed-HEAD evidence.
Complete parent preimages/rules are retained; the current rule digest and
dependent Values identities come from the independent oracle and existing
generators. Machine contracts, EBNF, numeric laws and resource limits do not
change. Old CIDs do not acquire new meanings.

Use the tracked `prepared-checks.mjs --final` with the pinned Node/Moon tools
for the existing 60-second/grace-5 nonHeavy selection. Native/Wasm checks are
compile only. New installed E2E is 0; Local/HTTPS, Native/Wasm execution,
Hosted CI and the original finite F01–03/F04 public matrix remain unexecuted.
Composite Relation identity conversion is a separate common bridge gap;
this change does not claim complete F04 or whole-Frontend acceptance.
