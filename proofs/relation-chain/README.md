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

The current reservation is preserved:

```
retained = base.retained_bytes
execution = max(base.execution_bytes,
                sum(child.retained_bytes + child.execution_bytes)
                + child_count * 256)
```

`children` retains every successfully started execution until parent cleanup;
`previous` keeps the intermediate output for the exact next edge. Cleanup visits
children in reverse order, retries the pending child, and drops references only
after all children complete cleanup. Thus child scratch and intermediate outputs
may coexist. Replacing the sum with `max(child)` would require a different
lifetime argument and is out of scope.

Still unproved: each child capacity's bound on actual live allocations, identity
and alias accounting across intermediate outputs, the 256-byte handle allowance
on each runtime, and the whole reservation's bound on the live allocation set.
Existing arithmetic guards and capacity/workspace acceptance tests remain.
This pilot does not establish the chain's complete resource guarantee.

## Exhausted-budget stop branch: separate residual

The active-child branch at `selected_relation_provider.mbt` cancels and polls a
child once with quantum 1. If the child still reports not-stopped, it currently
returns `Continue(work=1)` without increasing `used`, and discards the child poll.
This is not covered by the model's prompt-stop constructor and is not declared
correct by this pilot.

Accounting was traced independently:

* `connectors/local/materializing.mbt` adds positive Continue work to
  `attempt.provider_work`; its public counter is exposed only for successful
  completed attempts. Failure/stop returns an error, not a billed success.
* `connectors/local/driver/managed_dispatch.mbt` passes valid Continue work to
  `LocalManagedAdvance`; it does not compare aggregate poll work with this
  chain's `used` counter. Failed/Stopped polls become errors.
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
those families. Arbitrary delayed-stop callbacks remain an explicit residual:
their admissible stop work, cumulative accounting and physical-stop progress
must be resolved together. No stop calls are cut short and no work is hidden to
make the model fit. No existing-contract violation has yet been reproduced on
an executed standard provider path; this is not a finding that the general
callback branch is safe. A reproducible violation requires a minimal production
fix and dedicated regression in a separate PR under the approved scope.

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
