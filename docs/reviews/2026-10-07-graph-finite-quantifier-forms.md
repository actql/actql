# Graph finite quantifier spellings

## Existing meaning and missing syntax

This unit connects fixed-count `{n}` and omitted-lower `{,n}` edge
quantifiers to the existing finite homogeneous traversal operation.
The [selected GoogleSQL quantified-path clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-patterns#quantified_path_pattern),
consulted 2026-10-07, defines a fixed count and a default lower bound of zero.
The existing ActQL zero-hop traversal contract is retained. This is not a
claim of complete GQL subpath, group-variable or path-context conformance.

At parent `0e30ba931e4915fbc31c481eaca8425640c0c5b2` (#844), the parser
required both a first integer and a comma. Thus `{2}` and `{,2}` failed
before the supported common `min_hops` / `max_hops` contract was reached.
The new parser lowers the former to 2..2 and the latter to 0..2. Existing
explicit bounds, directions, fillers, anonymous-edge admission and source
positions use the same path. No upper bound is removed or clamped.

Zero upper bounds, negative/non-integer/unsafe bounds, reversed intervals,
open upper bounds and named quantified edges retain refusal. A terminal-node
predicate is not installed as a homogeneous every-hop filter. No common
execution owner, Graph representation, resource ceiling or fallback changes.

## Independent counterexamples

`graph_quantifier_forms_test.mbt` compares the complete Program with an
independently authored fixed-hop control whose traversal bounds are explicitly
changed; compiler output is never an expected-value input. The common checker
admits those controls. Parser coverage includes all full/abbreviated directions.

Public fixtures reuse independent authored constructor inputs and machine
controls from the abbreviated-edge unit, not lowered product output. One
node has two differently keyed self-loops, one R and one S. At exactly two
hops, WALK has four sequences, TRAIL has two and ACYCLIC has none. At 0..2,
they have seven, five and one respectively. A full R-filtered edge has only
one two-hop WALK path. These counts detect an accidental default lower of
one, changing a fixed count to an interval, edge identity collapse and a
dropped authored label filter. The empty case retains its number column.

The unchanged public consumer checks Result rows, complete column contracts,
column order, hidden-column absence, same-request Run identity and refusal
before Run admission/provider I/O. Both focused and normal packed selections
include this corpus, and its independent shared fixture is staged transitively.

## Evidence and canonical impact

Before the fix, the four-test selection recorded one pass and three failures
(`run-QYKJ81`, `focused-test-QLyZRh`), at the parser entry. After the fix,
the selected JS tests passed 15/15 (`run-3DqgpO`, `focused-test-wNyoHB`),
including existing edge forms and the affected Values Run fixture. Targeted
Node vectors/fixture registration passed 12/12 (`run-vxjzqK`,
`focused-test-lUsK0h`). These are precommit worktree checks, not CI results.
Read-only compilation-manifest freshness and `git diff --check` passed.

Grammar/rules generation uses the existing generator. Independent canonical
preimages give grammar manifest
`sha256:883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135`
and Values Run
`sha256:ea1d3abc7d1e52de2b35574a26c62cfe8fea84beed67a4e1c6c0afba5d30ffa2`.
Historical grammar and Run vectors remain separately pinned. Values Program,
Unit, proof and ResultPlan bodies/identities remain unchanged.

Fresh packed Local/HTTPS evidence, exact revision, five-package manifest and
remaining CI are recorded in the PR. Full Core, Wasm/native execution, proof
campaigns, full packed acceptance and full hosted history are not covered by
these focused checks. This branch depends on #844 until it reaches main;
source acceptance alone is not an execution or merge-completion claim.

## Public acceptance before final main integration

At `3ad4a048546659aafd3c224a1bd6db8d51ecc10c`, normal five-package
packing passed (`run-vLrvNO`). The existing focused public command passed
Embedded Local and HTTPS, each with 11 normal inputs and 9 pre-admission
refusals (`run-i5VT9w`). Independent Named Result rows, complete declared
columns, empty-result type retention, read/attach/resend identity and unchanged
Run/source-I/O counters on refusal are covered. The complete receipt is
`worktrees/.codex-scratch/public-query-evidence-2re9QH/summary.json`;
all ten commands exited zero with complete output and no evidence errors.
The normal producer manifest is
`/private/tmp/actql-b-quantifier-3ad4a0485-pack/packed-client-packages.json`.
All five digests agree with its revision and the consumer receipt. The broad
receipt records untracked review evidence as dirty; tracked/build inputs
passed the existing clean-HEAD checks. No overlay or skipped prepack was used.

## Main integration and current identity closure

Parent #844 reached main at `ae1f273bc1174e50598d86ab932daa0bc28c5f4d`.
Main was merged normally. Its current Table source contract, workflow and
history changes are retained. The only conflicts were the independently
authored Values Run vector and its consuming MoonBit fixed-CID assertion.

The grammar remains
`sha256:883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135`.
Main's Table dependency changes the Values Unit to
`sha256:54f5a2da3c5f2439a13630dec8a8098ef550d9befcca8ac298ac22aac3cecd8f`,
proof to `sha256:b9b589e8f084c3ba2b8abaf6d888f037d76e56c2ceb23a0120ffe8c027912e8e`,
and ResultPlan to
`sha256:6286d2d4d7603a61da71d464c0043b98647e94b1997ae9b1dc94bda51fa34a3a`.
The independent normative-preimage oracle derives integrated Run
`sha256:ebd0959e213d515f8fe993989cc39976660e5a45918ea6fa8951a5a41e08cc4c`.
Both historical dependency closures and main's abbreviated-edge Run vector
remain frozen separately. No product-issued CID supplied an expectation.

Conflict verification passed 11/11 targeted Node tests (`run-7tUvFG`,
`focused-test-l6Vegz`), read-only compilation-manifest freshness and diff checks.
The three-file focused MoonBit selection reached its 120-second guard limit
before returning results (`run-9yyauw`, `focused-test-2dArEh`); it is incomplete,
not a pass or a demonstrated assertion failure. The owned process group was
confirmed absent by a kernel group probe before recovering only its matching
worktree lock. The timeout receipt is preserved unchanged, with a separate
manual recovery record. No full Core or repeated broad suite was run.

The earlier distribution success remains evidence for `3ad4a048...` only.
Fresh packed execution of the integrated Table closure and required CI are
not established by that predecessor. Exact submitted SHA, current base and
subsequent public evidence are recorded in the PR.
