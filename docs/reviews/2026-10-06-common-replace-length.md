# Common REPLACE and LENGTH execution

## Scope and source

Starting main: `660c48375b782e4d2c3aa7b405caf17bf61915d5`.
Branch: `feat/common-replace-length`; final merge target: main.
This closes the shared executable dependency of Frontend PRs #608 and #645.
It does not adopt their source spelling changes or implement another evaluator.
No unmerged parent branch is required.

The existing scalar specification already requires literal, non-overlapping,
left-to-right REPLACE, empty-search identity, eager NULL propagation and
Unicode-scalar LENGTH. Raw scalar sequences, including decomposed Unicode and
CR/LF, remain unchanged. The expression 0.1 wire and its existing identity laws
are unchanged; generated public interfaces add the two typed operator cases.

## Production route

The normal checker supplies typed expression nodes. The shared lowerer now
produces Unary(Length) and Many(Replace), with their original canonical len
and replace bodies. Normal backend traversal, encoding and ordered references
already handle those child shapes.

The existing ExpressionFrame evaluates operands in order and retains their
roots. LENGTH advances one scalar per poll. REPLACE advances one candidate
code unit or one emitted scalar per poll, first sizing the output and then
building it. Each poll consumes existing control work; suspension never resets
logical work or re-evaluates operands.

Sizing reserves canonical output bytes and charges the produced value's scalar
weight under the existing logical owner. Only after that pass does the frame
reserve the exact output UTF-16 capacity and allocate its builder. Native's
pinned exact-capacity builder finalizes without another full copy; JS retains
the builder's String. Allocation is still a single admitted allocation, not a
claim of a hard wall-clock bound on allocator/GC latency. The algorithm's
search, scalar counting, sizing and filling are resumable.

The completed cursor attaches its exact measurement to the same root and uses
the existing prepaid result event. It does not double-measure or double-charge
the output. Cancellation/failure closes the existing frame, releases temporary
roots and cursor/buffer reservations once, and preserves caller-owned input.
No scheduler, ledger, Frontend evaluator or compatibility fallback is added.

## Independent resource vectors

For a borrowed 256-byte ASCII input:

| Operation | Logical work | Peak live wire bytes | Workspace slots |
| --- | ---: | ---: | ---: |
| len(payload) | 517 | 258 | 11 |
| replace(payload, 'a', 'bb') | 1041 | 779 | 524 |

LENGTH: two entries + twice input weight 257 + Number result weight 1.
REPLACE: four entries + twice operand weights (257 + 2 + 3) + output
weight 513. Its input roots are 258 + 3 + 4 canonical bytes and output is
514 bytes. Twelve fixed slots plus 512 output UTF-16 units dominate the
twenty-slot child-measurement peak. Exact and one-short work, live bytes and
workspace use these hand-derived quantities, never successful-run estimates.
Quanta 1, 7 and 256 retain the same values and logical totals.

A 513-byte output ceiling rejects before builder allocation. Additional
fixtures stop inside a 128-unit common-prefix candidate, output sizing,
output construction and LENGTH scalar counting. Borrowed roots survive;
double close neither refunds work nor releases those roots.

## Counterexample and focused evidence

Initial independent expression regression failed 0/1 in common lowering:
`run-trB2m5` / `focused-test-NEUYkG`.

The original main refusal was then restored as a controlled negative mutation
of only the len/replace admission tags. The two independent node/wire tests
failed with the exact typed causes ExpressionNotImplemented("len") and
ExpressionNotImplemented("replace"). The complete handwritten JSON Program
also failed at the ordinary retained Host factory. Result: 0/3,
`run-kq0CS8` / `focused-test-JLvFKP`. This is a controlled restoration of the
original rejection, not a pristine baseline packed campaign.

After restoring the connection, the identical Programs and focused callers
passed 36/36: `run-LiQrZj` / `focused-test-pc8qfm`.

The public Node regression sends normal JSON Programs through
connectEmbeddedLocal, prepare/submit, the bounded Local route and real retained
Store. It reads independent Named Result rows and full column contracts for
NULL, empty, Unicode and long Text cases, preserving VALUES occurrence order.
Re-read/attach and the same request do not dispatch again. A separate barrier
delivers Host cancellation after ten positively charged advances; before
release, cancellation is not yet physically confirmed, and after release the
Result remains unavailable. This public case establishes delivered cancellation,
not a claim that its opaque progress barrier identifies a particular internal
Text phase; the typed frame fixtures separately identify those phases.

Public tests passed 2/2: `run-HFppT0` / `focused-test-JtoIDl`.
The source tree was uncommitted during these candidate checks. Final submitted
SHA and exact-SHA receipts are recorded in the PR; earlier receipts are not
relabelled as checks of that SHA.

Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/lowering_relation/text_functions_test.mbt \
  src/query_integration/text_function_program_wbtest.mbt \
  src/execution_relation/text_functions_wbtest.mbt \
  src/execution_relation/expression_frame_wbtest.mbt \
  src/execution_relation/expression_text_comparison_wbtest.mbt \
  src/lowering_relation/expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  adapters/host-node/public-text-functions.test.mjs
```

Only Local Node and Run Host Core runtime dependencies were built from this
checkout. The runtime bundles remain ignored, not committed. These are checkout
artifact checks, not pristine packed Local/HTTPS acceptance. Missing borrowed
DuckDB dependencies and an outdated borrowed client-wire export initially
prevented test loading; the worktree now borrows only third-party dependencies
and resolves its own client-wire. The first public oracle incorrectly assumed
id sorting instead of VALUES order; its expectation was corrected from the
existing occurrence-order contract, without changing production ordering.

## Handoff and remaining acceptance

The smallest ordinary Program control is in
`src/query_integration/text_function_program_wbtest.mbt`. Its expected row is
`{"id":1,"replaced":"bXna","length":3}`. Public controls and full expected rows
are in `adapters/host-node/public-text-functions.test.mjs`.

B can adopt this common source SHA, then rebuild normal packages with its
Frontend changes and run the unchanged REPLACE/character-length Local/HTTPS
fixtures. The ordinary public entry remains client.aql(JSON.stringify(program),
{format: "json", requestId}), followed by run.wait() and
run.result("answer").all()/describe(). No special provider registration is
needed for these source-free Local Programs.

Wasm/native execution, packed source-syntax acceptance, full Core, proof and
performance campaigns were not run locally. API generation inspected all
three portable targets but is not execution evidence. Automatic submitted-SHA
CI is reported separately; no manual retries or CI-success inference is made.
