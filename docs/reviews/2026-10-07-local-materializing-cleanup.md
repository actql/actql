# Incremental retained-input cleanup

## Scope

This unit connects the current materializing retained-input path to the existing
incremental import reclamation owner. It adds no scheduler, ledger, synchronous
Compute fallback, stored-data conversion or compatibility alias.

`advance_local_materializing_cleanup` retains the same provider until its stop
and cleanup succeed, then retires import/copy roots in bounded reference slices.
The common scratch witness is read-only. Pending cleanup and errors keep the
reservation; retries do not start Compute or import again. Accepted descendant
rows are not mutated. A poll can observe one provider stop step in addition to
its requested reference-retirement slice; this is not a GC or wall-clock bound.

Node and Native Local dispatch reuse the installed cleanup hook. On Node, a Store
close error retains both the physical Store and the execution owner. If physical
release has already succeeded, its observer still reaches the Site owner so a
lost acknowledgement cannot strand a released holding.

Managed preparation and all three built-in drivers now use the existing
`ExecutionLifecycleOperations` directly. The duplicate
`ManagedExecutionOperations` type and `managed_execution_lifecycle` conversion
are removed, not aliased. This is a MoonBit source API removal; lifecycle fields,
completion checks, wire identity and reservation formulas are unchanged.

## Checks executed during preparation

These receipts describe dirty source at parent
`b6ad6043b1043e1105530b05b953a03de8c91e84`, not clean submitted-HEAD execution.
The implementation was subsequently committed as
`e3aac76118752da4b0caa8186992446cfe6d4ba7` and main
`e5d2be0276f5c79f874ab7b5aa173eb9a5f87902` was normally merged without conflicts.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 1 \
  src/query_integration/local_materializing_provider_work_wbtest.mbt \
  src/query_integration/local_materializing_cleanup_wbtest.mbt \
  src/query_integration/local_materializing_wbtest.mbt \
  src/query_integration/local_dispatch_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  adapters/local-node/strategy-bundle.test.mjs \
  adapters/local-node/retained-output.test.mjs \
  adapters/local-node/managed-output-custody.test.mjs
```

- JS: 11/11, receipts `run-o5ofqm` / `focused-test-wjsPxQ`.
- Node: 30/30, receipts `run-Hi1lB2` / `focused-test-2MRZIg`.
- The materializing work fixture derives 15 filter steps, 7 select steps,
  one handoff, and 28 + 31 ASCII completion-port steps. Literal 82/81 limits
  retain typed `Candidate(Execution(InputLimit))` rejection across quanta
  1, 7 and 256.
- Interrupted unverified imports retain reservations through sliced retirement;
  stopped-provider cleanup error/pending/retry retains the same owner. The source
  producer remains usable, no task result is published, and final retained and
  reserved amounts are checked.
- Node tests cover physical Store close failures before and after release, Site
  holdings, full capacity reuse and cleanup retries without extra Compute/import.

The affected Native caller compiled with the matching target (132 tasks,
`run-P221or`), but Native behavior was not executed. Common API generation and
affected consuming packages compiled. The Local Node runtime (167 tasks,
`run-oyMKi5`) and Host ABI (2 tasks, `run-sS8lLp`) built; their existing package
generators and consistency checks passed. Runtime bundles remain untracked.
These build receipts also precede the latest main merge.

## Failed attempts retained

The first broad Node selection timed out at 120 seconds (`run-VtCwjU`). A focused
case exposed a fixture passing its synthetic task to the real `strategyHostTask`
owner before Compute. Correct fixture task accessors were added; no production
identity validation was relaxed. Earlier failing receipts remain separate.

The Node selection then caught the post-release close-acknowledgement case:
returning an error without cleanup authority stranded the Site holding. The
existing physical cleanup observer now accompanies that error; the final 30/30
selection confirms zero holding and capacity reuse. No failure was relabeled as
successful execution.

## Remaining validation and work

Integrated public real-Store Host acceptance, generated-artifact freshness after
the latest main merge, and submitted-HEAD CI have not yet been established.
Wasm/Native execution, full Core, full proof, packed/HTTPS and performance were
not run. Draft preparation is not shipping readiness.

Managed publication buffers, actual snapshot-reload cancellation acceptance,
availability/Carrier walks, other scratch and Native physical-byte correspondence
remain separate boundaries. This PR does not claim all obsolete API removal or
completion of the full retained Local goal.

## Subsequent main integration

Main `ae1f273bc1174e50598d86ab932daa0bc28c5f4d` was normally merged after the
published Draft became unmergeable against newer main. The actual merge had no
content conflicts. Current Graph syntax, Table/Values identity fixture changes,
Native release observation and pipeline CI configuration were preserved.
The Local materializing and Node cleanup implementation had no incoming overlap.
This integration is not a new runtime or public-Host execution receipt; the
existing preparation evidence remains tied to its original source.
