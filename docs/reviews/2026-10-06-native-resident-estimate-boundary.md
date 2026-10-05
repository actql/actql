# Native resident estimate observations

This is G's connection work for #170 and #488. It does not establish a latency
improvement, Native/Broad paired acceptance, or completion of the performance
task. Host remains an explicit experiment condition. Product resident offers
remain disabled by default.

## Completed connection

The optional trusted Native Host observer brackets the existing environment
provisioning, actual producer import, and resident task execution. Reusing an
environment or a committed table does not invent a new provisioning/import
interval. Events contain phase and task/producer numbers, not backing references.
The probe buffers timestamps and prints them after task execution. The normal
Host installs no observer.

Admission pairs successful boundaries, rejects clock retreat or overlap, checks
the actual resident choice, and compares interval counts with the existing
Owner's environment/import/Compute attempt observations. Serial phase durations
must fit inside their enclosing task interval. These are time observations, not
logical work or physical-memory bounds.

The experiment can supply a typed resident duration profile to the existing
planner: preparation, cleanup, per-task execution, and producer-indexed imports.
Missing import estimates remain unknown. This input does not alter capacity,
transfer, activation, attempt limits, or the execution Owner. The real 100-row
acceptance additionally compares supplied rates with the serialized pre-execution
offers; an echoed `selectionInput` is not connection evidence.

## Fixed-source observation

Native source revision: `bf062efd7eddbbe3509329051b728909302e469e`.
Platform: macOS arm64. Node: 22.23.2. MoonBit: the repository-pinned
`moonbit-0.10.12+1634b282e`. Release probe:

`sha256:af9ec8ba0fc9953adff4e45a5df46d707be95eeaff1ac32d37a93382ce0b3c29`

The selected release build succeeded; a clean fixed-HEAD incremental build then
reported no work. The 31 selected tests passed at this revision: 9 fresh-profile,
13 phase-admission, 8 typed-profile, and 1 actual Native acceptance test containing
8 settings. These are not 31 Native experiments or a performance matrix.

```sh
node scripts/local-checks.mjs test node -- \
  benchmarks/retained-results/native-estimate-profile.test.mjs \
  benchmarks/retained-results/native-physical-phases.test.mjs \
  benchmarks/retained-results/native-resident-estimates.test.mjs \
  benchmarks/retained-results/native-owner-acceptance.mjs
node benchmarks/retained-results/native-case-probe.mjs \
  native-acquisition-full-validation-low-selectivity/narrow/100 \
  --resident-policy=true --phase-observer=true
```

The single 100-row diagnostic selected resident Compute for all three tasks and
verified the independent output CID, holding/release and attempt correspondence.
Its observed physical intervals were 6,857 us for environment preparation,
1,724 us for producer 0 import, and 9,107 / 14,885 / 7,401 us for resident tasks.
Enclosing process time was 141.996375 ms; execution was 127.566 ms and final Run
cleanup 2.783 ms. These single observations are not a measured improvement or a
calibrated estimate profile.

Local evidence, relative to this worktree:

- `_build/local-checks/attempts/run-3wfO1r`: fixed-HEAD incremental release build.
- `_build/local-checks/attempts/run-IvpXh6` and
  `_build/focused-evidence/focused-test-OdoPiW`: 31/31 selected tests.
- `_build/repro/resident-physical-bf062efd7.jsonl`: actual 100-row observation;
  digest `sha256:d2420ce502102cd8916face86e589175d06d08a93a14cd6b5505405d2e4dc52a`.
- `_build/repro/bf062efd7-native-artifacts.json`: binary and observation digests.

## Additional transition observations

Two bounded 1,000-row training-source diagnostics exposed an unresolved Native
transition. Artificial duration estimates are used only to request a particular
training candidate. They are not measured rates or paired acceptance evidence.
Both keep the existing registered case limits and independent expected CID.

1. Fresh DuckDB tasks 1 and 2 followed by resident task 3: the real planner chose
   that sequence, but execution rejected task 3 with
   `native strategy DuckDB task rejected: start-physical`. Before failure cleanup,
   three physical attempts had started and the environment held 2,147,483,648
   reserved execution bytes. Close returned that reservation; duplicate close
   left the accounting unchanged.
2. Local task 1 followed by resident tasks 2 and 3: task 2 completed after one
   actual import of producer 1. Task 3 then received the same rejection. Before
   close there were four physical attempts and two holdings; close returned all
   tracked capacities, and duplicate close left them unchanged.

The diagnostic currently collapses several physical issues into `start-physical`;
the exact underlying issue and whether the same transition fails through a
public Run remain unconfirmed. Do not infer a public Run defect or completed
handoff acceptance from these probe observations. No shared Owner, Ledger cleanup,
cancellation or bounded-expression accounting change is included here.

To reproduce the first transition, write the following nonsecret experiment
profile to a temporary file outside the checkout:

```json
{"preparationMilliseconds":"1","cleanupMilliseconds":"1","taskMilliseconds":["1000000","1000000","1"],"importMilliseconds":["1","1","1",null]}
```

```sh
node benchmarks/retained-results/native-case-probe.mjs \
  native-acquisition-full-validation-low-selectivity/narrow/1000 \
  --resident-policy=true --phase-observer=true --native-ms=1 \
  --native-task-ms=1,1,1000000 \
  --local-task-ms=1000000,1000000,1000000 \
  --resident-estimates=/absolute/path/to/temporary-profile.json
```

Saved raw observations are
`_build/repro/resident-prefix-2-bf062efd7.jsonl` and
`_build/repro/resident-local-prefix-1-bf062efd7.jsonl`. The first transition's raw
digest is `sha256:0b3f96706089395ac7a9c1a9750a412df04dd24fe745f89c4a04b3f29a20781b`;
the second is `sha256:beba79530f3a406e1a8537a76285f63872b1a74409a0f479fbab170c5242f3fc`.

## Remaining work and ownership

- G: identify the Native transition's precise rejection without relaxing limits,
  then obtain the required producer-import observations. If correction crosses
  shared Owner or accounting contracts, hand the fixed counterexample to A/H.
- G: align time coverage before admitting a measured resident profile. Existing
  enclosing task intervals include planner work; resident physical intervals
  exclude preparation/import and final Run cleanup. They cannot be compared as
  if they represented the same cost. Final cleanup also includes nonresident
  owners and acquisition release; it is not yet an isolated resident cleanup
  measurement.
- G: measure observer off/on burden and matched cold/warm full cycles. Clock-read
  observations do not bound callback/buffering overhead. Do not add overlapping
  intervals or count artificial training rates as performance.
- D/A retain cancellation/finalization and Model wire boundaries; H retains Effect
  value identity, recovery hooks and Ledger cleanup. G does not duplicate them.
- #412's real isolated-image mutation/restoration/final-consumer acceptance and
  Actions evidence reuse remain separate open obligations. #480's Hybrid boundary
  work does not remove public admission restrictions.
