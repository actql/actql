# Native parent allocation census, retained core and the 256-byte premise

This diagnostic connects one existing generated `filter → distinct` pipeline
to the real registered serial-chain constructor. It inspects its owned roots
at startup under the pinned 64-bit native debug profile. It is finite
implementation correspondence, not a complete parent upper bound or a proof
of production-wide refinement. It introduces no product API or runtime owner.

## Independently derived component sizes

The header is eight bytes in the pinned runtime. The source field layout and
native GC descriptors give these requested object extents:

| Source group | Extent / lower bound |
| --- | ---: |
| Three pointer Refs, two Int Refs, four Bool Refs, one Int64 Ref | 136 |
| `ManagedProviderExecution` record, six reference fields | 56 |
| Initial `reported_work = Ok(0L)` | 16 |
| Advance, cancel, stopped, cleanup, child-work-issue closures | 96 + 40 + 24 + 64 + 24 = 248 |
| Children Array owner and initial one-reference backing | 24 + 16 = 40 |
| `start_next` environment, 12 references and two Int fields | 120 |
| Included startup lower bound | **616** |

The Ref scalar payloads are conservative minimum widths, not presumed allocator
rounding. Code pointers occupy pointer-width fields but are not GC references.
The environment has a 112-byte payload. Its references at byte offsets
`0,8,16,24,32,40,48,56,64,80,88,96` must match the actual used, pending,
position, current, previous, children, family, numeric, measurement, execution,
inputs and sequence roots; the captured count at offset 104 must also match.
Equal byte labels do not establish this connection. The borrowed configuration
objects and the transitive first-child state are excluded from this parent
subtotal because existing owners account for them. New parent objects are not
removed from the original allocation inventory to make the formula fit.

The synchronous C reader checks physical distinctness of these included roots,
callback objects, the environment, reported-work record and container backing.
They must be dynamic objects. It holds pointers only on the C stack for this
call, without incrementing RC, storing pointers, or adding a later holder.
The output string and temporary observation helper are instrumentation; their
bytes are outside this source-parent subtotal. The ten product Refs and the
environment are already required by the existing callbacks. Inspection of the
preserved uninstrumented native AOT chain confirms those allocations; the
probe does not pass `start_next` as an extra argument or wrap it in a new closure.
That inspection is supporting source/compiler evidence, not an additional
automatically verified refinement theorem.

## Consequence and product boundary

`selected_relation_provider.mbt::bounded_relation_chain_capacity` adds
`count * 256` to the sum of child capacities, with overflow rejection, and takes
the maximum of that amount and the base execution capacity. For two children,
the parent component is 512. The observed source-bound startup already needs
at least 616 under this native layout. Consequently the standalone premise
`parentBytes ≤ count * 256` used by the conditional chain model is unsupported
and contradicted for this inspected two-child startup.

This does **not** establish that the entire product reservation is exceeded:
child and base reservations can have slack, and the driver composes further
import/retention reservations. The concrete consuming boundary is
`driver/managed_dispatch.mbt::prepare_local_managed_dispatch`, which adds base
retained/execution/import capacity and supplies the common Site reservation.
No regular execution is rejected by this diagnostic. No product reservation
coefficient is changed or replaced by a renamed accounting fee.

The capacity evidence gate continues to reject unconditional allocation-byte
guarantees. It additionally requires this actual native startup receipt on
native-containing campaigns. The parent probe's target, fixture, compiler,
runtime profile, exact observer overlay, archived log, input, execution receipt
and executed binary hashes are checked independently. Internally valid native
evidence cannot be admitted in a requested JS/Wasm slot. Relabeled facts alone
and missing binary archives are rejected. Existing structural model proofs and
all existing capacity mutations/corpus/three-target checks remain required.

## Remaining upper-bound work

`allocations.json` preserves seven source roles: retained parent core, selected
step contexts, selected inputs, internal binding/read edges, provider selection,
poll/return temporaries, and retirement/output custody. The checker binds record
field types, the ten Ref declarations, reported-work variants and all eleven
provider constructors to actual source. All eleven provider candidates are
constructed before the acceptance loop; the returned provider alone is not a
complete constructor footprint. These objects remain in the census even when
their byte/lifetime bounds are unresolved.

### Input-derived retained-core component

For an admitted Int32 step count `n ≥ 2`, let
`C(n) = max(1, max(8, 2*n))`, the existing grow-at-full backing ceiling. The
conditional retained-core envelope is **680 + 16*C(n)** requested bytes:

| Source group, including replacement overlap | Upper component |
| --- | ---: |
| Ten single-field Refs, payload at most eight bytes each | 160 |
| Parent execution record | 56 |
| Five immutable callbacks | 248 |
| `start_next` environment | 120 |
| Two simultaneous reported-work records | 32 |
| Two children Array owners | 48 |
| Two backing headers | 16 |
| Two backing payloads, each at most `C(n)` pointer slots | `16*C(n)` |

The bound is derived before execution from source/ABI premises and input count,
not from the largest observed value. The scalar GC class does not encode an
allocation request size: the Ref payload ceiling remains an explicit pinned
source/ABI premise, rather than a claimed scalar-size measurement. The old/new
overlap limits are also explicit premises. Existing array growth reasoning is
reused; finite callback snapshots do not prove every transient overlap.

`NativeParentCore.lean` checks the conditional sum and backing-overlap rule.
Its retained-owner witness is a model example, not physical GC evidence. The
runner executes the pinned Lean checker, archives its source-bound model receipt
and log separately from the native execution receipt, and requires both at the
evidence admission boundary.

The native borrowed phase reader observes the actual parent before/after
advance, cancel and cleanup callbacks. It verifies capture identities and
indexed GC layouts, current children owner/backing identity, backing slots and
terminal/reclaimed flags without storing a MoonBit pointer or increasing RC.
The current finite case exercises normal handoff, premature cleanup, terminal
advance and repeated successful cleanup. It does not exercise cancellation of
the parent, failure or pending/error cleanup retry. Child cancellation already
present in the harness must not be relabeled as parent cancellation evidence.
Current phase identities establish point-in-time sharing only, not allocation
epochs or a complete lifetime union across possible address reuse.

The implementation correspondence is deliberately incomplete for the whole
parent. In particular, the driver keeps its provider handle after cleanup, so
immutable parent callbacks and Refs can remain reachable. Cleanup success does
not establish physical destruction or correct retirement of their reservation.
That custody/retirement correspondence remains a separate unresolved role.

The 616 subtotal is a lower bound, not the measured maximum reused as an upper
bound. A replacement sizing rule still needs a source-derived upper bound for
all parent and uncovered edge allocations, including children backing growth,
old/new overlap, temporary constructor callbacks, changed reported-work records,
new input/binding/read wrappers, pending cleanup and accepted-output custody.
It must compose with independently justified child bounds and integer checks.
Child `Value`/control layouts, complete lifetime unions, portable runtime
management areas and the original 256-byte parent premise are not discharged
by the selected Map/Array extents or this diagnostic. Physical allocator arenas,
fragmentation, collector buffers and process RSS remain outside the agreed
allocation accounting boundary. Cleanup success is not physical GC evidence.

Run only this source-bound diagnostic with the pinned `MOON_HOME` and pinned
Lean executable on `PATH`:

```sh
node proofs/relation-pipeline/capacity/parent-control/run.mjs
```

The complete hosted capacity campaign runs it after restoring the child
observer/mutations. Its separate report and content-addressed executed binaries
are archived below `.artifacts/relation-pipeline/capacity/parent-control-probe`.
Before spawning it, the capacity campaign saves its observations/receipts and
calls the executor's terminal `closeExecutor()`. This checks ownership, physical
file identity and exact fixture bytes before removing only that fixture. Matching
bytes from another process do not confer ownership. The exit hook is a fallback,
not a parent-to-child handoff. Closing retains every archived fixture and receipt.
The isolated lifecycle regression uses the real executor/finish boundary and
live parent/child processes with a mocked Moon transport; it also detects an
omitted close. Full real capacity-campaign-to-parent-probe execution remains the
hosted CI integration check. #190's per-workspace `createExecutor().close` is the
same terminal boundary; its default executor must expose `closeExecutor` when
that executor version is integrated.
The final independent capacity audit rechecks the receipt. Local validation is
limited to touched Node tests and one native generated case; complete campaign
results belong to CI on the pushed SHA.

## Output completion and scratch retirement

Output acceptance and provider scratch release are independent acknowledgements.
The common completion boundary preserves the execution reservation when the
installed scratch-release condition is false, even after output retention has
moved to a holding. An execution without an installed condition retains the
existing synchronous completion behavior. The Local output commit tries the existing provider cleanup once before
common completion; false/error keeps the provider and its reservation for
explicit retry. The existing cleanup path retires scratch after confirmation; no new owner or ledger is used.

The custody diagnostic reuses the typed `distinct → filter` corpus entry and
registered Local driver. Its success mode defers the commit-time cleanup attempt
once with an exact audited overlay, runs all three children, finalizes an
accepted Int payload through the real completion/ledger boundary, checks the
scratch reservation before explicit cleanup, then closes the output and verifies
cleanup and repeated cleanup without Compute restart or work loss. The Int
payload verifies completion accounting, not physical Relation output backing,
last-consumer retention, or GC destruction. Those correspondence obligations
remain open, together with complete child/runtime and parent byte bounds.

The admission gate requires normal cancellation, pending false/error/retry
cleanup, and successful completion receipts for each requested target. JS
mutations separately remove the installed release condition and bypass the
successful completion guard. Each must fail specifically for premature scratch
credit; a compilation failure or missing record is not mutation detection.
Normal finite correspondence on Wasm/native remains separate from JS mutation
coverage. Successful cleanup is not evidence that an allocation disappeared.
