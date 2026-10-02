# Multi-root Relation strategy selection

## Problem and boundary

The [independent machine Program](../../spec/frontend/fixtures/data-set-strategy/repro-program.json)
has two Values roots followed by append, one evaluated ordering slot, sort,
projection and LIMIT. Its independently required Named Result is
`nodes = [{"id":1}]`, with one nonnullable number column `id`.

At main baseline `16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a`,
`physical_strategy.carrier_segment_prefix_end` returns at its stage-0 guard
before reaching the existing multi-root Relation checks. The Program remains
one task, for which installed dispatch has no usable strategy revision.
The public execution failure is `Dispatch(NoStrategy)`; publication's later
`StrategyNotComplete` is secondary. This also occurs with machine input,
independently of frontend DATA lowering.

The fix admits a source-free, Relation-only shape with multiple zero-input
Values roots to the existing selected-provider and per-input checks. It does
not authorize segmentation solely by counting roots. Every occurrence still
needs its registered selected capability, typed retained Relation ports and
checked predecessor schema. Single-root linear pipelines, unsupported
selected aggregates, external acquisition, Carrier fusion rules and task
limits retain their existing boundaries.

Only the shape selection in `src/physical_strategy/carrier_tasks.mbt` changes.
No provider, Run-start owner, alternate executor, capacity bypass or Graph
compatibility adapter is added. Definition and law identifiers do not change.
Programs that now select different physical tasks have different derived Plan
and task identities; no historical identity expectation is replaced by product
output. B owns this reproduction and its source reacceptance. It is separate
from the Property Graph unification and snapshot work in #164.

## Executed evidence

At source `ae826a1fa32708b211fc29399399a334794168c2`, normal prepack followed
by installation outside the checkout passed:

- The independent JSON Program through Embedded Local and HTTPS, from ordinary
  admission/checking to Named Result. Rows and actual `Result.describe()`
  column order/type/nullability equal the authored expectation. No internal
  sort field is exposed.
- Attach, Result reread and same-request resubmit do not accept another Run
  or acquire again. This source-free Program performs no source acquisition.
- The existing README quickstart through Local/HTTPS, plus packed dependency
  and deliberately missing generated-asset checks.

| Package | Tarball SHA-256 |
| --- | --- |
| client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| sdk | `9fd8d7c7019eafcd1401fa1804108644f13875b2197bb3d3e012abbb5428143e` |
| run-host-core | `d95c875c5a5372de4534cd77ce1f3cbb1b04c973a1b1699b0efd4ea8ff5f1f7d` |
| local-node | `065f0266dac46bcfbfc6401032ced7c11eae65120929ec7f55c1affc7e768973` |
| node | `5ee3b433edde987b6007f337aafe71af71c565135a16cae3de1debdebc4f1d67` |

The subsequent commit adds only stronger tests and this record. The focused
tests pass 4/4 on each of JS, Wasm and native. They cover exact selected task
outputs and input counts, maximum-task refusal, an unregistered distinct-count
profile remaining fused, and existing prefix/linear/shared-JOIN behavior.
Restoring the baseline selection makes the new positive regression fail
(`1 != 7` tasks), establishing that it detects the original boundary.

Formatting, JavaScript syntax and diff whitespace checks pass. Full local
Core/Client/spec jobs are not repeated; final-SHA CI is separate evidence.
This does not prove new Property Graph unification, public snapshot, or INFER
execution. The temporary public ordered-DATA refusal in #174 remains until
this fix is adopted there and the authored source is separately accepted.

## Reproduce

Use the pinned toolchain for normal prepack:

```sh
node scripts/test-packed-public-query.mjs --data-set-strategy-only
```

The external installed application requires no MoonBit toolchain. The driver
retains source SHA, digests and command logs and reclaims its own installation
after evidence is saved. Use `--keep-artifacts` only for failure investigation.

Focused tests:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/run_publication_host/client_data_set_task_wbtest.mbt \
  src/run_publication_host/client_pipe_result_compilation_wbtest.mbt
```

Use `--target wasm` or `--target native` for the same four obligations.
