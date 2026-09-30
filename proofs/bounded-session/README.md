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

The first derived scope is `intersect/all`, selected from the current registered
set implementation. Its local obligations remain set comparison, duplicate
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
it cannot be admitted by copying a binding. This initial runner accepts the set
family only, rather than pretending to verify an arbitrary new provider's fixture.

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
