# Bounded Session evidence pilot

The pilot reuses the production bounded Session and cumulative-poll adapter.
Its purpose is to let a provider supply local obligations and a connection
witness rather than repeating token, delta-accounting and cleanup-protocol
tests for every operation. Existing Local resource inventories and gates remain
authoritative. This report does not close their unresolved physical obligations.

## Contract and proof boundary

`Session.lean` proves 14 contract-model theorems. `Claims.lean` checks expected
proposition types; `check.mjs` compiles them with the existing Lean pin and audits
every theorem's axiom dependencies (only `propext` and `Quot.sound` are permitted).
No AoA foundation is copied: this first unit concerns an operational protocol,
not canonical Carrier semantics. AoA morphisms, Events instances, chain resource
composition and DAGs remain later units.

The model separates cumulative accepted counters, token generations, terminal
observations and reclamation obligations. The accounting theorem telescopes an
arbitrary finite monotone report list. A quantum bound requires the kernel's
work-bound premise. It does not prove the work of internal kernel loops or
unreported physical work on callback errors. Cleanup preserves the terminal
outcome and counters; eventual environmental recovery is not assumed or proved.

Session cleanup returns **changed**. The provider callback must return
**complete**. The concrete set cleanup currently disposes pending results and
reclaims scratch synchronously; its state callback always succeeds. Therefore
its first changed=true is complete, and the adapter caches that completion.
The formal counterexample `changed_is_not_completion` prohibits treating this
as an unconditional rule for other providers. A provider with partial/retryable
lower reclamation must check the lower pending obligations before reporting true.

Evidence kinds are preserved:

| Evidence | Scope |
| --- | --- |
| formal-model | `Session.lean` contract propositions and their premises |
| tested-refinement | finite production Session/adapter correspondence domains |
| tested-refinement | actual registered set provider/driver execution and reviewed source connection |
| derived | conditional reuse of the above for a named operation/variant/target |

No verified-refinement or physical-acceptance claim is created. A source or
artifact digest pins the tested input; it does not prove semantic correctness.

## Correspondence domains

`session_contract_wbtest.mbt` uses an independent remaining-demand/history
oracle, without reading Session fields, for all 6,561 four-command base-9 traces.
Each trace is extended with stop, cleanup failure, readiness change and retries.
The alphabet includes two positive quanta, zero quantum, current/original/foreign
tokens, both cancellation reasons, readiness changes and cleanup. Additional
traces exercise ordinary completion and positive-work cancellation/deadline.
Separate checks retain machine-counter endpoints and reentrant resume rejection.
This is finite testing, not a proof over all production states. Existing tests
for unaccepted-result disposal, stop during a kernel call and overflow custody
are retained because they observe additional ownership behavior.

`bounded_session_contract_wbtest.mbt` checks all two-poll combinations of progress
and work in {-1,0,1,2,7}, with failure, stop and callback-error endings (1,875
cases), plus Int64 endpoint cases. It checks exact failure observations, deltas,
telescoping, counter regression, terminal sealing, cancellation forwarding,
cleanup error/pending/retry and cached completion. Complete(output) reaches the
same terminal grouping via the actual set-provider integration fixture; its
payload and consumers remain covered there. Counter endpoints outside a valid
kernel quantum are adapter robustness cases, not evidence of physical work bounds.

`mutations.mjs` changes production sources and runs replacement tests, not the
old hand-written protocol tests. A compile error is not an accepted kill. An
additional mutation makes the common adapter terminal at construction and runs
the real set/driver fixture, witnessing that this production route reaches it.
All files are restored in `finally`; the final source snapshot must match.

## Pilot and residual obligations

The pilot derives scopes for `intersect/all` and `except/all` from the current
registered set implementation. Its local obligations remain set comparison, duplicate
multiplicity, NULL equality, ordering, kernel phase costs, exact work/workspace
limits, scratch reclamation, ordered two-input ownership and two-consumer custody.
These are not derived from the common adapter. In particular, the operation-specific
tests in `bounded_set_wbtest.mbt`, `bounded_resource_boundary_wbtest.mbt`,
`set_rows_wbtest.mbt` and `local_managed_set_wbtest.mbt`, and the physical/packed
backend fixtures, remain in place.

`bindings.json` is a pilot supplement to the existing operation/route inventory.
The runner checks that its entrypoint agrees with that inventory and that the
reviewed provider calls the selected kernel and adapter. Source matching alone
does not constitute refinement: the registered fixture also executes, and the
production-route mutation must fail it. The same connection fixture intentionally
retains all four except/intersect × all/distinct semantic cases and its two consumers.

The fixture's reviewed operation/variant/profile coverage is fixed independently
of `bindings.json` in `evidence.mjs` and recorded with the successful connection
execution. Both `checkBindings` and `validate` compare the requested scope with
that witness. Changing the connection and derived labels together, while keeping
the execution record and source/artifact digests unchanged, is rejected. Missing
coverage or a relabeled execution scope is also rejected. This pilot deliberately
uses an exact reviewed table; it does not infer profile inclusion from labels.

For a new provider using this adapter, review its callback premises, add its
operation-specific law/boundary checks and an executed connection witness, and
instantiate the existing model claims. A different kernel, ownership handoff,
backend, counter representation or cleanup meaning creates a residual obligation;
it cannot be admitted by copying a binding. The runner now accepts the reviewed
set and Nest routes, each with its own independently fixed executed coverage;
it does not verify arbitrary providers from their names or self-declarations.

## Reproduction and audit

Set up the repository's pinned MoonBit toolchain using `node scripts/setup-moonbit.mjs`
and put its bin directory on PATH. Install the existing Lean pin in `lean-toolchain`.
CI uses `setup-lean.mjs` with a pinned Linux release archive SHA-256.

```sh
node --test proofs/bounded-session/evidence.test.mjs
node proofs/bounded-session/run.mjs all
node proofs/bounded-session/mutations.mjs
node proofs/bounded-session/run.mjs js
npm run check:local-resource-completion
```

Reports and execution logs are written to `.artifacts/bounded-session/`. Each
target records HEAD, whether the worktree is dirty, the exact source snapshot,
toolchain, commands, executed counts, built artifact digests, durations, claim
dependencies, premises and residual obligations. When dirty, HEAD identifies
the parent revision and the snapshot identifies the actual tested working tree.
The runner rejects source changes during execution and stale binary evidence.
The negative gate suite covers operation/variant/profile/target mismatch, missing
premises/dependencies, cycles, stale sources/artifacts, empty/unrelated tests and
attempts to upgrade tested-refinement to verified-refinement.

The evidence job runs beside all existing CI jobs; it does not replace a coverage
row, remove a physical fixture or weaken an existing gate. After mutation tests,
the JS source and artifacts are rebuilt; Wasm/native were not mutated.

## MoonBit proof capability experiment

`probe-moon-prove.mjs` mechanically extracts the exact production `add_counter`
body and attaches a range/postcondition contract in a temporary module. It is a
capability experiment, not an accepted implementation proof or a second runtime.
With MoonBit `0.10.12+1634b282e` and Z3 `4.15.3`, the annotated production body is
rejected with E4207: `Int.to_int64()` is an unsupported primitive operator in a
contracted function body (and its logic contract). Without annotations the tool
reports zero proved goals; that result is also not counted as evidence.

```sh
Z3PATH=/path/to/z3 node proofs/bounded-session/probe-moon-prove.mjs
```

No new external declarations are trusted to hide the conversion. Runtime range
and overflow checks/tests remain. The current official guide also distinguishes
mathematical arithmetic from runtime overflow; this experiment is tied to the
repository's fixed compiler rather than assuming nightly capabilities:
<https://docs.moonbitlang.com/en/latest/language/verification.html>.

## Test retirement and marginal operation cost

The evidence-addition revision is `b1685224abca14a3680b3d9e000a69440ee058c2`.
It retained every old test. The follow-up retires two basic common-Session examples:

| Previous example | Replacement and preserved obligations |
| --- | --- |
| bounded session advances with fresh tokens and finite work | generated histories check exact counters, fresh/stale/foreign tokens, normal completion, stop/pending flags, one-time cleanup; token and accounting model laws are reused |
| stop confirmation precedes retryable cleanup | generated histories check positive-work cancel/deadline, unchanged counters at stop, pending cleanup, recovery and callback counts; terminal/reclamation model laws are reused |

`retirements.json` records the exact previous body digest, every old observation,
replacement test, theorem references, premises, implementation connection,
mutations and retained unique regressions. The runner checks the structural
mapping and retained regression references; the Lean checker and executed suites
provide the substantive evidence. The deletion is not justified by matching names.

The deleted examples had no pending unaccepted result. The five existing
Session ownership/error regressions remain, including the regression additions
from `f56eed506` (unaccepted-result retention, disposition retry, accepted custody
transfer and overflow cleanup). All set-specific and physical suites are unchanged.
This is a replacement of duplicated protocol examples, not removal of kernel or
backend acceptance. It removes two hand-written tests (79 lines) after the
replacement domains and mutation checks passed.

The operation-reuse demonstration adds the `except/all` binding beside the
`intersect/all` pilot. The existing registered fixture already exercises both
operations and variants with independent expected rows. The additional binding
uses the same source-checked provider, existing executed connection witness,
model theorem and common correspondence suites. It adds **zero** Lean theorems,
common-mechanism tests or operation×protocol fixtures. The generator and graph
derive a second claim per target from the same checked premises. This is a
retrospective acceptance comparison using two existing operations, not a claim
that a new semantic algorithm needs no local tests.

| Adding the second operation scope | Observed change |
| --- | --- |
| Local semantic/boundary tests | existing except expectations and boundaries retained |
| Connection review | existing `set_provider` route and registered fixture reused |
| Evidence descriptor | one explicit operation/variant binding |
| Common protocol proofs/tests | no additional theorem, trace suite or hand-written combination |
| Derived report | one additional conditional claim on each target |

Initial setup adds proof/generator/gate maintenance work. This pilot demonstrates
reduced marginal verification/review work; it does not claim lower total CI cost
or an overall test-count reduction relative to the pre-pilot repository. The
reports measure proof time, correspondence time and integration build/execution
time separately. Historical developer/reviewer time was not measured and is
not invented. Different provider families still need their own connection and
kernel premises checked before using the common guarantees.

## Retrospective Nest acceptance comparison

`nest-obligations.json` separates inherited and local obligations before the
evidence changes (commit `3b85cb458`, baseline `22507d140`). This applies the
evidence infrastructure to an **existing** operation. It does not report that a
new operation, kernel or semantic algorithm was implemented.

The reviewed `correlated-parent-major` scope uses four checked parents,
nullable correlation keys, ordered child projection and two independent
consumers. `local_managed_nest_wbtest.mbt` executes the actual module registration
and managed driver with two ordered reads, quantum 1 and `require_provider=true`.
Its independent expected rows cover duplicate parent keys, NULL nonmatching keys,
NULL projected amounts and empty child arrays. The gate requires this fixture's
own execution, rather than relabeling the passing set fixture.

The concrete route is `module.mbt` → `nest_provider` → `start_bounded_nest` →
production `bounded.Session`; provider polling passes through the unchanged
`bounded_session_execution` adapter. Both inputs must match the checked owner,
step and operation positions 0/1. Kernel scratch cleanup is synchronous;
`cleanup_bounded_nest_state` frees its scan, sort and value/workspace state and
returns true. After completion, accepted output custody remains with its owner.
Treating scratch cleanup as permission to reclaim accepted output is not an
inherited guarantee.

| Verification when admitting Nest | Added / reused work |
| --- | --- |
| Connection | Execute Nest's existing registered 2-input/2-consumer fixture on JS/Wasm/native; independently fix its scope and verify source connections |
| Local semantics/resources | Execute existing bounded Nest, sequence, scaling and exact-workspace fixtures; retain order, NULLs, item/grouped/attached bytes, phase costs and one-short boundaries |
| Misimplementation detection | Two new JS mutations witness the common adapter route and reject swapped parent/child ports; eleven existing common mutations remain |
| Evidence gate | Reject set-to-Nest evidence reuse, symmetric profile/provider relabeling, missing local obligations and partial/missing fixture execution |
| Common verification | Reuse the same 14 Lean model propositions, 6,561 Session histories and 1,875 adapter cases; add no theorem, shared-protocol test or operation×protocol fixture |
| Existing combinations | Add no hand-written Nest × existing-operation matrix; the already-existing downstream/consumer cases remain |

The frozen common artifact digests are checked before admission. No production
source or MoonBit test is changed or retired. Unique two-input binding/custody,
per-phase cleanup, item/value/workspace boundaries, real Store and delivered
cancellation/failed-publication/reclamation tests remain. The existing Local
resource inventory still owns their physical acceptance. The evidence runner's
conditional protocol claim does not turn them into an implementation proof.

Only cumulative-to-delta accounting, terminal sealing and cleanup retry without
Compute are inherited, under the existing callback premises. Nest's kernel work
costs, NULL/order/multiplicity semantics, input authority, nested allocations and
output ownership remain local. No straight-line chain theorem is used for the
two-input operation. The allocation sizing gaps from #117, including child and
runtime bounds and the 256-byte allowance, remain unresolved; this comparison
does not establish unconditional live-byte or whole-process memory bounds.

The marginal result is a checked connection, preserved local acceptance and a
derived protocol claim without repeating common proofs or protocol exploration
for Nest. Actual implementation/reviewer hours and total CI savings were not
measured and are not claimed.
