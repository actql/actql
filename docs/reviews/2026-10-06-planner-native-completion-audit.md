# Planner selection, Native resident acceptance and measured improvement

Owner: G. Audited main: `dfff4587118b077e76e6da8153e2827a9839e14b`.
This closes the assigned two delivery units for the existing bounded benchmark:
actual selection/ownership/measurement first, then one matched latency
improvement. It does not complete the full performance matrix or incremental
CI. This audit reruns no benchmark, build, product test or external service.

## Integrated work and immutable evidence

| Unit | Integration / original evidence |
| --- | --- |
| Selection, ownership and timing | [#458](https://github.com/actql/actql/pull/458), submitted/tested source `c9f6879dafba57baef42a40adfd9b75e02741aa7`; explicit Native/Node Host conditions, actual acquisition/Compute choices, resident preparation/import and formal Node request cancellation |
| Concrete implementation improvement | [#507](https://github.com/actql/actql/pull/507), submitted `2cdcb514beac98805e1f808c156895d4552b2c76`, merged `d093bcedf8b64b5d7b3e8fdecc988310c51bff90`; compiled source `58ec55085f78b22eef890a99778bf05f5749c2f3` |
| Authenticated policy through actual dispatch | [#546](https://github.com/actql/actql/pull/546), merged `7faa3113730c43ab92197f55bee3438977cf8c62`; five invalid responses cannot dispatch or change the ledger, valid response executes and closes the actual owners |
| Ordinary registered resident offer | [#557](https://github.com/actql/actql/pull/557), tested source `6c2e38f160a8e5e7dc440a4a9da17cf3b56eb15a`, merged `26aae16ac72985d0b0a11e32483d446e936490bc`; real release/default/calibrated acceptance |

The three later integration commits are ancestors of audited main. A Git
comparison from #557's merge through audited main finds no changes in
`benchmarks/retained-results`, `scripts/test-native-direct-pair.mjs`,
`src/cmd/native_retained_case_probe`, `src/physical_strategy_example`,
`src/connectors/duckdb/standard_host`, `src/physical_host` or
`src/physical_strategy`. This identifies the retained connections; it does not
turn prior acceptance into a new-main test run or establish unchanged behavior
of every transitive dependency.

## Requirement audit

| Required behavior | Actual evidence and boundary |
| --- | --- |
| Explicit Host; no row-count Host routing | `equivalent-matrix-runner.mjs` derives its Native choice only from explicit `productProfile`; `managed-configuration.mjs` offers resident uniformly, without case-name/size selection. Historical mixed-Host measurements are not directly comparable. |
| Actual acquisition and Compute candidates before I/O | Existing acquisition selection and pre-task explanations bind registration, selected position, strategy revision, capability, resident profile, estimates and selected bounds. Native offers one acquisition candidate. The bounded Node fixture compares two real Native/Broad acquisition candidates over the same requirement; Broad completes its residual. |
| Two real Compute implementations; independent output | Local, fresh DuckDB and resident DuckDB are executed by the ten-setting Native 100-row case. Independent stage cardinalities, typed rows and result CID remain product admission obligations. |
| Feasibility, unknown cost and current authority | A cheaper resident assessment loses at the actual attempt cap. Unknown import durations defer offline ranking and enter no Compute. Node uses the actual `HostPreferred` reason with unknown durations. Five invalid external-policy responses fail before dispatch; no reason is invented from expected selection. |
| Resident environment/import attempts and retention | `native-owner-observations.mjs` checks each task's actual attempt delta as Compute plus new environment/import counters. Resident deltas `[3,1,1]` and mixed transitions are tested. Sealed payload bytes, charged holding and selected retention upper bound are separate; live resident reservations cannot disappear early. This is finite counter/owner correspondence, not proof of opaque allocation identities. |
| Stop, cancellation and cleanup | Native `stopped-between-tasks` starts no later task and closes retained resources. The separate Node case issues real request cancellation after acknowledged task-1 completion, observes process stop/exit and preserves the accepted Store holding until explicit close. Neither is promoted to all active-Compute cancellation or public Run `Cancelled`. Duplicate close changes neither consumed counters nor released reservations. |
| Real phase timing and measurement load | Native phase boundaries and task/environment/import/release intervals come from actual execution; nested intervals are not summed. Planner/observer work and elapsed time are retained. Four prescribed Node off/on/on/off observations show +110.160146 ms median execution-plus-cleanup difference; they establish no causal Native overhead bound and are not subtracted from the Native improvement. |
| Release/calibrated gate after changing the default | At #557's clean source, selected fresh JS/Native release artifacts passed four real Owner tests, uncalibrated direct pair, 12 training runs plus one held-out selection, calibrated direct pair and seven equivalent pairs. Actual held-out ordinary selection is Local/Local/Local. Unchanged warm/cold upper thresholds are 10/100 ms; observed upper differences are -4.733/-104.120 ms. |
| One diagnosed and improved latency | #507 connects the existing bounded batch drain at the installed byte ceiling and `min(64,max_chunk_rows)`, preserving per-row admission/work, backpressure, canonical identity, seal durability and owner obligations. The original Compute diagnosis, failed/withdrawn candidates and all matched samples remain. |

## Read-only verification of originals

The protected #557 acceptance manifest is
`_build/repro/native-resident-default-6c2e38f16/acceptance.json` in G's retained
benchmark worktree. Its referenced Native binary, calibration, seven-pair series
and two original supervisor receipt digests were recomputed and matched:

- Native binary: `b276ca6895cc1912a74a93cea3662418a79abf1a817478cf0a5d6ded23af8283`.
- Calibration: `334f014f4fa451fd2ed2ba4dc5edb36cb9164637e8326a510043afc2a453e158`.
- Seven-pair series: `9b34d81aec6d1a11cba1d4f633f63da3a38cef39dab10be6ec3a194b8db41810`.
- Build receipt `run-xvkPJc`: two passed, completed release preparation steps.
- Acceptance receipt `run-NYE42I`: five passed, completed steps, including four
  real-boundary tests with no failures/skips/cancellations/todo cases.

The original 21-pair record is
`_build/repro/native-batches-58ec55085/comparison-e6039c0ad.json`, digest
`65421e2a4755fc926acb3488f2e14a9a37e172d4f7733c8a1ed2cd5852f1ce32`.
Both archived executable digests match that record. Recalculation with the
existing paired assessor reproduces every recorded interval, including complete
parent time **-40.771 ms**, 95% interval **[-65.688,-17.866] ms**, about 10.45%.
Every pair retains identical task holdings/usages, candidate/choice/explanation
and acquisition evidence, consumed accounting and explicit resident selection.
Two admitted prelaunches and all 21 alternating pairs remain present.

Source preparation (202.221 ms), application preparation, transfer/import,
Compute/identity, holding, cleanup and complete parent cycle remain recorded.
Cleanup and application preparation differences are indeterminate. Fresh
processes and warm within-process resident reuse are distinguished; OS-cache
coldness and causal CPU attribution remain uncontrolled. No favorable interval
is substituted for the whole process cycle and no sample was added or removed.

## Completion and separate work

The bounded planner/resident connection and one measured implementation
improvement are complete on their accepted, fixed-source evidence. Original
commands and artifact provenance remain in the linked delivery records. The
user integrated these units; their automatic Actions runs stopped on payment/
spending-limit checks before execution. This audit claims no hosted success.

Automatic Native/Node or Local/Cloud placement, dynamic Hybrid (#480), the full
27-case matrix, Native HTTP/mTLS transport, unconditional physical heap/GC bounds,
and #412's actual isolated image/13 mutations/restoration/final consumer remain
separate unfinished work. Incremental-CI main comparison, ordinary PR reuse and
overhead-inclusive net runner savings are likewise not closed by runtime gains.
