# Conditional DISTINCT structure and serial custody

This is the intermediate completion unit agreed after #148. It derives selected
child **filled-container entry** bounds from an admitted input contract and
checks the real registered numeric/NULL serial route. It does not close the
child/base allocation-byte bounds, runtime management areas or parent `count *
256` allowance. The original allocation census in `relation-capacity` remains
unchanged; the census here lists both derived quantities and outstanding objects.

## Quantities and source connection

For one whole-row DISTINCT with admitted input row count `n` and schema width
`w > 0`, independent bounds are:

| Resource | Filled-entry upper bound | Actual source |
| --- | --- | --- |
| Input/output names and ordinal maps | `4w` | `bounded_binding_rows.mbt` preparation |
| Merge index buffers, including transfer overlap | `2n` | `StartSort`, `SortRows`, `bounded_index_sort.mbt` |
| Keep bitmap | `n` | `InitializeDistinctKeep`, `MarkDistinct` |
| Comparison terms | `w` | `PrepareDistinctTerms` |
| Output outer rows and inner cells | `n + nw` | `CommitOutputRow`, `FinishOutput` |
| Input roots | `n` | conservative allowance; DISTINCT skips logical retention |
| Six row-temporary containers | `6w` | snapshot, values, roots, output/checked/capture row |
| Scalar measurement frames | `5` | four numeric/NULL measurement cursors, conservatively bounded |

Their conservative sum is `nw + 5n + 11w + 5`. Output cardinality is bounded by
the admitted input count, not an observed number of survivors or measured peak.
NULL placement and duplicate rate do not increase this bound. Borrowed input
cells have a separate `nw` bound; they are not new child-owned payload storage.
Comparison/control records, Session/provider state, schema objects, Refs,
closures and empty containers remain in the allocation census. Their runtime
byte sizes and dynamic Array/Map backing capacities are not inferred from length.

The output's IEEE754 numeric **content** is at most `8nw` octets. This describes
64-bit numeric content, excluding NULL, tags and wrappers; it is not the physical
storage size of JS Number, admitted values, arrays or the whole child. UTF-8 name
content, scalar content, container entries and declared reservation bytes must
not be added as though they had the same physical representation.

For the current scalar/short-name domain, the independently derived workspace
entry requirement is `5w` for empty input and `max(5w + 2n, 6w + n)` otherwise.
Metadata contributes `4w`; sort adds `w + 2n`; output construction retains the
`n` bitmap and two `w` row arrays. A scalar input-measurement frame cannot exceed
the nonempty peaks. This is the existing `RowWorkspace` entry contract, separate
from `ExecutionCapacity`'s declared byte reservation. Generated runs use exactly
one DISTINCT occurrence; this is not acceptance of other value domains.
The capacity-only start overlay records `retained_bytes` and `execution_bytes`
from the exact registered provider passed to start. These are declared allowances, not measured
allocation bytes; the distinct observer separately records workspace entries.

## Sharing, retention and release

The existing allocation-union model composes finite child bounds by live
allocation identity. Shared references count once; independent copies have
different identities. The sum of child allowances is only a conservative bound,
not an assertion that every child allocation is simultaneously live. The current
parent deliberately retains its children until reverse cleanup, so a simple
maximum-child substitution is unjustified. Handoff can keep old output and new
child scratch alive together.

The proof-only source overlay reads actual workspace fields and owned arrays at
their production transitions. At receiving reads it compares real backing
identity; at completion it compares the output buffer with the transferred rows.
It stores only scalar counts and identity comparison results in logs. It adds no
object registry, owner, ledger, stored callback or persistent reference to an
observed buffer. Logging allocates observation strings; no heap peak is measured
or claimed. Original sources are restored byte-for-byte in `finally`.

Workspace release means releasing an entry reservation or transferring it to
output ownership. Clearing a field means dropping that reference. Neither means
GC/deallocation. Accepted output and upstream anchors can survive successful
Session cleanup. The existing harness verifies output cell/wire reads afterward;
it also verifies cleanup-before-terminal refusal, cancellation and repeated
cleanup through the real Session/adapter path. Existing chain false/error/retry,
allocation sharing/copy, Host/Store and backend tests remain authoritative for
their respective scopes; no such fixture is deleted or replaced by this probe.

The actual task owner retains scratch at `settle_task_execution` while not
disposed; `release_task_execution` requires disposal/settlement and consults the
installed retention acknowledgement. This source connection is not a proof of
every internal allocation's final Host reservation-to-holding transfer. That
boundary remains explicitly unproved here. No ordinary execution is rejected
because runtime byte sizing is unavailable.

The [installed scratch retirement correction](parent-control/CUSTODY.md) makes
that stop/cleanup distinction explicit at the existing task reservation owner.
Its finite source-free serial regression retains reservation through actual
child cleanup false/error/retry and preserves final cumulative work. It does not
close successful accepted-output last-holder or complete allocation-byte bounds.

## The 256-byte obligation remains open

`generated_sequence_capacity` uses 256 per selected node/container ceiling;
`bounded_relation_chain_capacity` additionally uses `child_count * 256` for
parent/edge control. Neither allocates a corresponding 256-byte buffer. The
existing ledger admits declared conservative allowances; it is not an allocator
measurement or a formal proof of a runtime byte bound. The chain-specific Ref,
closure, array growth and edge-wrapper sizing derivation is still missing.
The fixed value is unchanged and is not renamed into a convenient logical fee.

The [native parent startup diagnostic](parent-control/README.md) independently
binds actual captures and requested object extents for one existing two-child
registered pipeline. Its included startup lower bound is 616 bytes, already
above the separate 512-byte parent component under the pinned native layout.
This contradicts that standalone component premise, not the total reservation:
child/base slack and complete parent/edge upper bounds must still be examined.
Native-containing capacity campaigns and their final audits require its
separate source-bound receipt; portable-only runs cannot reuse it as portable
layout evidence. Unconditional allocation-byte claims remain rejected.

The structural claim gate rejects unconditional allocation-byte claims and
omitted runtime premises. It sits at evidence issuance/admission, not normal
product admission. A complete byte claim will require independently supported
representation bounds, coverage and the parent allowance before this gate can
admit it. A structural proof alone cannot supply those facts.

## Evidence and reproduction

* Lean: eight model propositions, independent consumer signatures and axiom
  audit, including reuse of the existing allocation-union model. The implication
  from entries to allocation bytes explicitly requires a representation bound.
  The first-occurrence list specification derives output cardinality from input
  length; correspondence of its equality to production remains a finite check.
* Finite correspondence: generated input/schema bounds, concrete empty/NULL/
  duplicate/nonduplicate predicates, actual adapter cancellation/cleanup and
  independently derived workspace one-short/exact/one-extra boundaries.
* Mutation evidence: real underreservation, premature bitmap release, duplicate
  index release and an unaccounted independent handoff copy. Fresh exploration
  and local-minimum shrinking run on JS; each minimized mutation and restored
  success is separately replayed on JS/Wasm/native. Anchors retain the same
  DISTINCT occurrence, resource transition and, for copying, exact checked edge.
* Audit: target, program, observed profile, source overlay, input/log receipt and
  content-addressed executed binaries are independently checked. Intact native
  evidence substituted into JS/Wasm slots and unconditional-byte claims fail at
  the actual audit entrypoint.

```
node --test proofs/relation-pipeline/capacity.test.mjs
node proofs/relation-pipeline/capacity/check.mjs
node proofs/relation-pipeline/capacity/run.mjs all
node proofs/relation-pipeline/capacity/audit.mjs
node proofs/relation-pipeline/capacity/audit-target-regression.mjs
node scripts/local-checks.mjs run pipeline-evidence
```

Use the repository MoonBit pin and existing Lean pin. Run one heavy gate at a
time, without editing its worktree. Common changes are the harness's retained
read/early-cleanup checks, source inventory coverage and CI capacity steps; they
are additional review work. No generator, shrinker, independent semantic oracle,
production owner, ledger, product algorithm or reservation formula is replaced.
#149 is reused only through its official integrated revision
`12dcd5e079e895ad0abf285cbd7c3dc45fa93c5b`; its orchestration is unchanged.

## Contiguous restored-capacity replays

The five capacity mutations keep their existing search, same-resource local
minimum and mutated JS/Wasm/native replays. Only after every minimum is verified,
the runner installs restored instrumentation once and independently executes each
minimum on each target. These remain fifteen fresh healthy executions with
separate input, observation, log and receipt identities. The unchanged semantic,
structural and backing checks run for every observation. No execution evidence
is cached; only target-separated incremental builds under unchanged source can
persist. This does not alter the separate ordinary mutation workspace runner.

The source-restoration `finally` and completed-report boundary remain after both
blocks. A failed mutated or healthy phase cannot write a completed campaign.
The complete CI still runs final normal verification and independent audits.
Downstream child verification must remain after restoration, durable campaign
persistence and explicit closure of the campaign's own fixture; batching does
not authorize sharing a live fixture or moving custody/native child probes into
the mutation or restored block.

Each mutation's `durationMs` remains the wall span from the first mutated probe
through its healthy replay completion. With separate blocks that span includes
intervening work for other mutations and must not be summed as action cost.
`activeDurationMs` sums only that mutation's mutated and healthy blocks, excluding
the shared restored-source installation and gaps. Existing `searchMs`, `shrinkMs`,
`replayMs` and `restoredMs` retain their individual phase meanings. These timers
include build, execution, hashing and I/O; they are not compiler-only timings.
Use completed exact-source hosted action/step durations for total cost and keep
runner/source/load differences explicit when comparing samples.

`capacity-orchestration.test.mjs` exercises the actual CLI with instrumented
boundaries, including all five input associations, three targets, failure
propagation and independent mutations of the scheduling logic. Those synthetic
checks do not replace real compiler, model, oracle, source/binary binding or
custody evidence from the complete hosted campaign.
