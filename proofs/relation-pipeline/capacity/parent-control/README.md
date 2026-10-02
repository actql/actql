# Native parent startup and the 256-byte premise

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

Run only this source-bound diagnostic with the pinned `MOON_HOME`:

```sh
node proofs/relation-pipeline/capacity/parent-control/run.mjs
```

The complete hosted capacity campaign runs it after restoring the child
observer/mutations. Its separate report and content-addressed executed binaries
are archived below `.artifacts/relation-pipeline/capacity/parent-control-probe`.
The final independent capacity audit rechecks the receipt. Local validation is
limited to touched Node tests and one native generated case; complete campaign
results belong to CI on the pushed SHA.
