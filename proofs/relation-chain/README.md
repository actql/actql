# Conditional serial Relation chain evidence

This pilot extends `../bounded-session/` using the existing production owner in
`src/connectors/local/selected_relation_provider.mbt`. It adds a contract model,
finite real-code correspondence, and report-only derivation checks. It does not
prove the MoonBit implementation, physical liveness, capacity, or arbitrary DAGs.

The inspected main baseline is `6011cb8fb4bd85f832a62e16ff8358a45dcad44e`.
The chain source blob is `ff0f475c5708de5e953da216ba86d4934af6a019`, also present
in A's retained-source worktree at `dd907c1201fc30911cf83c201080a314c03cfd1b`.
Reports pin the actual source digest, revision, toolchain and built artifacts;
these baseline references are not substitutes for that evidence.

## Contract and proof boundaries

`Chain.lean` has 22 model theorems. The checker also imports and audits the 14
existing Session theorems. `Claims.lean` fixes the consumer-side propositions.
A weakened theorem with the same name is rejected by a separate negative test.
Only `propext` and `Quot.sound` may occur in audited axiom dependencies.

| Obligation | Model evidence | Real-code evidence |
| --- | --- | --- |
| Child deltas telescope | `session_child_cost`, `finite_children_cost`, existing Session theorem | Independently drain each actual selected child |
| Child work plus handoff charges | `chain_accounting`, arbitrary finite `Run` | Compare real chain against independent children at the same remaining limits |
| Budget is not refreshed | `handoff_budget_not_reset`, `finite_run_budget` | Short, exact physical-cost, surplus and large limits; quantums 1, 2, 7 |
| Every started child retains cleanup responsibility | `chain_responsibility`, `failed_handoff_keeps_responsibility` | Failure after output binding; pending and error cleanup retries preserve output |
| Cleanup cannot restart Compute | `cleanup_does_not_compute`, `terminal_run_no_compute` | Start/advance/cleanup probes and all cancellation prefixes |
| Terminal observation is not reclamation | `terminal_is_not_reclaimed` | Terminal true while cleanup returns false or error |

The model begins after the first child successfully starts. A `Step` represents
an accepted child poll, attempted one-unit handoff, prompt stop confirmation, or
cleanup callback. It is a contract abstraction, not a translation of every
production branch. A failed handoff is charged even when the next child never
starts. Cleanup false and callback error both retain the obligation; only a true
completion callback may discharge it. Stop/reclaim liveness is not assumed.
Natural counters denote nonnegative representable accepted counters. Runtime
integer checks remain concrete obligations, including Session overflow guards.
No MoonBit/SMT theorem is substituted for those guards.

Physical poll work and each kernel's logical charges are different. For the
2-step fixture, the independent large-budget physical cost is 36, but a limit of
36 may fail after reporting 29 because the filter checks logical charges too.
The limited-child oracle preserves those checks. The theorem does not claim
that a physical-work lower bound is a sufficient successful-execution budget.
Setup, allocator time and cleanup wall-clock cost are not this poll-work metric.

## Concrete pilot and reuse

The fixture is `src/query_integration/relation_chain_evidence_wbtest.mbt`.
It uses the real registered `local_tea_provider.time_series_provider`, followed
by actual selected binding-row children, through `local_module_managed_provider`.
It does not substitute a second chain implementation for the production owner.

Reviewed paths are `time_series/filter`, `time_series/filter/select`, and
`time_series/filter/filter/select`. All use three nonnullable UTC Timestamp
rows, `filter true`, `select time`, and exact checked predecessor bindings.
The independent child fixture verifies cancellation before and after a poll;
the real chain fixture also cancels at every one-unit prefix. Both confirm that
the next advance stops without added Compute work. The Session unit fixture
checks the kernel-call boundary. The actual Session start/advance route and
cancel control forwarding remain reviewed connection premises.

Adding the selected `select time` suffix needs its own semantic obligations and
this exact input/output binding confirmation. It reuses the same finite-chain
accounting/responsibility laws, Session contract tests, protocol oracle, and
prefix generator. It needs no additional hand-written `select`-specific
quantum × budget × cancel × cleanup protocol matrix. These domains are finite
correspondence evidence; the arbitrary finite-chain theorem remains conditional
on each new child's premises. A new primitive/backend requires its own evidence.

The gate independently fixes the executed fixture coverage. Copying a binding
and changing both connection and derived profiles, lengths, child providers or
stop contracts cannot widen it. Source/artifact hashes pin executions; they do
not establish semantic applicability. The original operation/path inventories
and resource gates remain authoritative and unchanged.

## Capacity: deferred obligation

The unchanged conservative policy applies when a chain contains a family
provider or any built-in outside the reviewed early-cleanup set:

```
retained = base.retained_bytes
execution = max(base.execution_bytes,
                sum(child.retained_bytes + child.execution_bytes)
                + child_count * 256)
```

Such chains retain every successfully started execution until terminal parent
cleanup. Their execution readers are cleaned in reverse order, with pending
cleanup custody preserved.

A chain containing only selected binding-row kernels, `Groups`, `CountGroups`
and `JoinStep` now uses those same kernels' existing cleanup after each accepted
intermediate completion. Cleanup must confirm before the child execution is
removed from both `current` and `children`, and before the next child starts.
Accepted `CompletedOutput` values remain retained for all their exact later
checked edges; external input ownership and per-use logical budgets are unchanged.
The final child remains owned until normal parent cleanup. This lifetime permits:

```
retained = base.retained_bytes
execution = max(base.execution_bytes,
                sum(child.retained_bytes) + max(child.execution_bytes)
                + child_count * 256)
```

False/error cleanup keeps the child and its reservation responsibility; it never
permits another child to start. This early retirement while the parent is running
is outside `Chain.lean`'s terminal-only cleanup transition. The existing TimeSeries
pilot retains the conservative policy, and its laws do not prove the new lifetime
or capacity argument. Old source-bound certificates cannot be reused after this
source change; focused lifetime/capacity regressions are separate implementation
evidence.

Still unproved: each child capacity's bound on actual live allocations, identity
and alias accounting across intermediate outputs, the 256-byte handle allowance
on each runtime, and the whole reservation's bound on the live allocation set.
Existing arithmetic guards and capacity/workspace acceptance tests remain.
This pilot does not establish the chain's complete resource guarantee.

## Delayed-stop accounting: runtime correction and conditional extension

The active-child branch at `selected_relation_provider.mbt` cancels and polls a
child with quantum 1 after productive-budget exhaustion. Historically it
discarded the child poll, returned a fixed `Continue(work=1)` while not-stopped,
and returned terminal work zero. The runtime now forwards the actual stop delta
and its existing provider owner counts all reported work, including terminal
work. `used` remains the productive admission counter; stop polls never restore
Compute or handoff permission. Total diagnostic work can exceed `max_work`.
This is not covered by the model's prompt-stop constructor and does not widen
this pilot's formal guarantee.

Accounting was traced independently:

* `connectors/local/managed_provider.mbt` counts validated per-poll deltas once
  in the existing execution owner, with sticky invalid-report/overflow errors.
* `connectors/local/materializing.mbt` retains that owner's result across
  cleanup. Its old getter remains successful-completion-only; the additive
  cumulative accessor is available after failure and close, not billed success.
* `connectors/local/driver/managed_dispatch.mbt` passes valid Continue work to
  `LocalManagedAdvance`; it does not compare aggregate poll work with this
  chain's `used` counter. Failed/Stopped polls become errors; the additive
  cumulative accessor still exposes the provider total through the same owner.
* `adapters/local-node/strategy-bundle.mjs` checks per-poll quantum/positivity,
  yields to the host and waits for completion; it does not restore the chain's
  internal cumulative accounting.

Reachability is not a provider-name claim. `prepare_local_compute_module` accepts
caller-supplied family callbacks, and `bounded_relation_step_provider` can choose
them for Relation-valued TimeSeries/IntervalJoin/AsOfJoin/SequenceMatch/session
assignment. Registration checks matching/capacity, not a prompt-stop certificate.
Therefore that extension boundary cannot inherit this pilot's evidence.

The executed TimeSeries/filter/select paths confirm prompt stop in real child,
adapter and chain paths, including active budget exhaustion. The standard other
Relation family adapters forward `request_cancel` to kernels using bounded
Session; that source audit is not an executed correspondence certificate for
those families. The deterministic delayed-stop fixture in
`src/query_integration/relation_chain_delayed_work_wbtest.mbt` covers a registered
child and the real chain/standard managed-driver route: productive budget 1,
child work `[1, 1, 1]`, cumulative chain/driver work 3, one Compute entry, retained
limit failure, and cleanup retry. These remain finite runtime regressions rather
than a correspondence proof for arbitrary delayed-stop providers.

`Chain.lean` and `Claims.lean` retain their conditional `reported <= budget`
propositions. Their cancellation premise adds no work and confirms stop on the
next advance. They are not stop-inclusive hard caps for the delayed-stop branch.
The source/artifact snapshot changes require fresh evidence; old certificates
must not be reused for this revision. Delayed-stop liveness, arbitrary child
behavior and capacity soundness remain explicit residuals. No stop calls are
cut short and no work is hidden to make the model fit. See the
[runtime accounting contract](../../docs/design/local-provider-work-accounting.md).

### Stop-inclusive model and executable connection

`StopAccounting.lean` wraps the existing productive `RelationChain.State` rather
than replacing its 22 laws. Fourteen additive laws reuse its checked step,
accounting, responsibility and cleanup properties for finite stop traces:

```
reported = productive child work + attempted control work + accepted stop work
productive used <= original budget
```

Request does not confirm physical stop or release a child. A bounded accepted
stop poll charges its delta, including the terminal delta, while preserving used
budget and cleanup responsibility. Once requested, no productive step or handoff
is admitted. Cleanup false/error keeps the same responsibility and does not call
Compute. The explicit legal trace `[1,1,1]` has reported work 3, productive budget
and used work 1, one Compute entry and a stopped but still owed child. No theorem
claims that total reported work is bounded by productive `max_work`.

`StopClaims.lean` independently fixes the application types. The existing
checker executes all 14 Session, 22 prompt-chain and 18 stop-inclusive laws and
audits their axioms. Weakening terminal-work accounting, productive budget,
request/stop separation or stopping no-Compute conclusions fails real Lean
admission. Natural counters model accepted representable reports; overflow and
sticky invalid-report behavior remain implementation obligations. Zero-work
The original six-case delayed-stop connection does not establish Waiting/Settling
pause correspondence. Its new sibling claim below supplies that finite scope.
Arbitrary family behavior, early scratch retirement, stop liveness and physical
capacity remain outside this extension.

The same existing runner now executes the six delayed-work fixture cases for
each selected target and records their exact command, source, artifact and
independently fixed coverage. Its graph adds the scoped
`registered-child/stop-accounting` claim alongside the three original prompt-stop
claims. It depends on the executed model and its own connection; it does not
borrow the prompt-stop premise or claim that the diagnostic child uses bounded
Session. Fewer cases, substituted fixtures/targets, widened scope, missing
premises/model/coverage or a total-work cap are rejected. All existing prompt-stop
obligations remain mandatory.

Current input binding is checked in its actual metadata cursor owner:
`relation_chain_input_preparation.mbt`. Exact predecessor selection, receiving
owner/step/port, completed output and common read/cancel routing are retained.
Source guards are reviewed route checks, not a universal refinement proof.
New child implementations still need their own independently reviewed connection
and remaining semantic/resource obligations; they can apply these common laws
without inventing another protocol matrix. No Actions reuse permission or CI
saving follows from this model/finite correspondence addition.

## Retained acceptance and test retirement

No test is retired in this evidence PR. The existing window-group chain tests
carry exact logical work, exact workspace, failure and real managed cleanup
observations absent from this three-row pilot. Retained-sequence registration,
family semantics, unique failures, Store/process and backend tests remain.
There is no demonstrated identical-obligation duplicate to retire here; a test
retirement PR must supply a replacement map and is not manufactured to meet a
count target.

## Reproduction

Use the pinned MoonBit toolchain and Lean `leanprover/lean4:v4.30.0-rc1`:

```
node --test proofs/relation-chain/evidence.test.mjs proofs/relation-chain/proof-check.test.mjs
node proofs/relation-chain/mutations.mjs
node proofs/relation-chain/run.mjs all
```

The mutation runner changes one production source at a time, executes only the
four new correspondence tests, and restores the source in `finally`. Compile
failures are not mutation kills. Reports/logs are under `.artifacts/relation-chain/`.
Do not edit this worktree or run another gate while a runner is active.
CI extends the existing `session-evidence` job, preserving the old gate and
uploading both evidence directories. The runner records proof/test durations;
mutation cost and total job time remain separate from the operation-addition
burden. `formal-model + tested-refinement` is not verified implementation
refinement or physical Store/Host acceptance.

## Stop-only pauses reuse the common accounting and responsibility laws

The current chain forwards `Waiting` and `Settling` while the child retains
stop/Store custody. A zero-work pause is admissible; zero-work `Continue` remains
invalid. Neither pause kind establishes physical stop or permits child cleanup.
The stop model adds an explicitly tagged pause transition with the same bounded,
representable delta premise. It preserves the productive state, request and owed
child while charging accepted pause work exactly once. Zero work is an identity
transition. All original 14 stop-law propositions and the 22 prompt-chain laws
remain checked; four additional typed laws cover the pause boundary and the
independent `[1,0,1,0,0]` witness.

`relation_chain_stop_pause_wbtest.mbt` uses the real chain/provider owners with a
finite diagnostic child. Its two cases enter stop-only polling via an explicit
cancel or budget exhaustion, then observe `Waiting(0)`, `Settling(7,1)`,
`Settling(7,0)` and terminal `Stopped(0)`/`Failed(InputLimit,0)`. At each pause it
checks the exact tag/slot, cumulative work, no successor/Compute, no early child
cleanup and the same holding marker. Terminal still retains that marker through
cleanup false/error/true; repeated successful cleanup must not invoke it again.
The marker is callback custody evidence, not physical memory measurement.

The new `registered-child/stop-pause` derived claim reuses the existing model
root and has its own target-specific execution record and independent coverage.
The old six-case stop record cannot substitute for it. Missing pause premises,
one executed trigger, widened slots, missing coverage or a physical-stop claim
from a pause are rejected. The regular chain runner executes this connection for
each selected target; local JS acceptance does not claim Wasm/Native execution.
No semantic operation matrix, product owner, test retirement or CI reuse policy
is introduced. Model/Store authority, arbitrary provider refinement, machine
faults, physical capacity and eventual stopping remain separate obligations.

## Early intermediate retirement reuses the productive accounting model

The existing built-in-only chain can reclaim a completed intermediate execution
before starting its successor. `Retirement.lean` supplies 19 conditional lifetime
laws over the existing `RelationChain.State`. It reuses that model's accepted
child/control accounting and responsibility proofs. The original 54-law checker
and all prompt/stop/pause claims remain unchanged. The additional checker audits
55 laws: 36 existing Session/chain laws and 19 new retirement laws; that is not
55 additional guarantees.

Pending in this model means an accepted, already stopped intermediate child. It
is not an arbitrary cancel request. False/error cleanup keeps execution custody;
success transfers the one owed child to released exactly once. The parent's
completed-output references survive that transfer. A successor can start only
with no owed execution, a pending checked handoff and a running parent. Metadata
preparation may charge additional control work without starting that successor.
Finite admitted traces preserve the original productive budget, each started
child's responsibility and at most one owed child execution. This count does not
include retained outputs, cursors, closures or other live allocations. Pending
cancellation keeps custody and forbids new Compute; active-child cancellation
and delayed stopping retain their separate original claims.

`retirement-evidence.mjs` fixes one finite `builtin-chain/early-retirement` scope
for the eight existing `relation_chain_lifetime_wbtest.mbt` cases. These use real
binding/group/JOIN and Values/UNNEST children, observe `current`/`children` plus
accepted output generations, preserve pending/error cleanup, exercise scoped
cancellation and confirm conservative fallback for an unaudited step. They are
not a new operation-by-fault matrix. The shared runner executes the additional
model and existing fixture for each selected target; the same final graph gate
requires both, common Session correspondence, actual target/artifacts and every
local premise/residual. Original model or prompt fixture substitution, missing
cases, widened scope and a physical-memory guarantee are rejected.

The lifetime law does not certify kernel semantics, checked input identity,
GC completion, physical sizing, an unconditional max-scratch capacity or arbitrary
family/provider refinement. New eligible kernels still need their own semantic,
resource and connection evidence. The formal model and finite actual connection
can be reused without copying these common laws or eight cases per operation;
source-input changes still invalidate old evidence. No additional cached action
or Actions reuse qualification is authorized.
