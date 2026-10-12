# Preserve the requested capture boundary for a JOIN-chain right Source

Starting from the submitted Values-bound repair, normally adopt current main
`9ad0802cc694361a9df7cea500e062c287fb4d58` as merge
`b8d158d91f275dda68c6f74bca88cd1a30b5faa2`. Submitted parent PRs remain separate;
this unit does not change their original evidence or claim they were merged.

The original failing case is
`with_expansion_public_fixture_test.mbt:414`, named
`WITH captured expansion reuses resolved common Result input order`.
Keep its original Source Catalog, parameter declarations, query, JOIN ceiling
4, two-Stage/one-Source capture and complete projected field expectations.

On the adopted source, the failure is a real common order refusal, not a generic
missing public Result. `run-MvGHmG` and `run-l1KwBT` each execute 0/1: pipeline
`UnresolvedOrder`, source path `stages[0].steps[9]`. The main Sort lacks its
original retained right input order. The chain binder explicitly forced
`capture=false` for every right input, losing Context's requested capture Result.

Remove that one override. The existing binder still resolves the Source,
constructs its requested capture boundary, shares it and obtains publication
order from the common Result owner. Correlated UNNEST remains an operation on
the current row; no independent Source capture is fabricated for it. The direct
two-Source single-JOIN exception, Source Request, provider/driver, predicate,
limit, common order rules and resource owners are unchanged.

The first diagnostic patch attached to an identical text in a different local
typing control: `run-AlhuZZ` still failed the original selected case with an
unwrap. It did not establish its typed cause. The corrected diagnostic did.
An initial single-JOIN boundary probe (`run-DQucg5`) failed identically and was
reverted. The actual branch is the chain path with preserved input scope.
Keep every original failure; do not present either probe as a successful fix.

`run-BKiMes` is the first 1/1 original-case pass. After the final narrow override
removal, `run-CPQCv5` passes 35/35 across expansion, the three original unresolved
order refusals, Source member checks, LIST_FILES and direct-JOIN callers. Those
are working-source results; the final clean SHA receives its own receipt.

The test now reports original typed causes instead of panicking at an unwrap;
all success assertions remain unchanged. No expected Program or row was derived
from product output. New installed E2E scenarios: **0**. This closes one original
assigned failure, not all WITH or public Host acceptance. No full Core, package
campaign, provider, Hosted CI or target runtime is started.

Reproduce with the pinned toolchain, existing 60-second non-Heavy guard and
5-second TERM grace:

```sh
node reviews/2026-10-13-frontend-core-checkpoint/prepared-checks.mjs \
  src/query_program/with_expansion_public_fixture_test.mbt \
  src/query_program/with_binding_static_order_gap_test.mbt \
  src/query_program/source_member_test.mbt \
  src/query_program/file_listing_test.mbt \
  src/source_frontend/pipe_join_input_test.mbt
```
