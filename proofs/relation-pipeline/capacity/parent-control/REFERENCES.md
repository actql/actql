# Primitive Ref allocation and observer correspondence

The current parent source declares `used : Ref[Int64]`, three `Ref[Bool]`
controls and `cleanup_index : Ref[Int]`. The existing source census rejects
changed declarations, and the Native observer reports their actual distinct
identities. Scalar GC descriptors do not establish these payload extents.

The Linux x64 final consumer additionally inspects the immutable generated
parent object and actual executed binary. It checks all five typed constructor
calls, initializers, returned aliases and distinct private frame slots. Those
slots may not be replaced, even by a partial overlapping write, before the
actual C observer call. Four Ref roles must reach their exact System V argument
registers; cleanup-index must reach the first stack argument without replacement.
Only the reviewed conditional skip of an `incref` call is admitted. Frame escape,
unknown control flow, an external jump into the custody region or changed call
count/type rejects correspondence.
Frame checks include partial-register writes and copies into memory, as well
as frame-derived addresses using a non-frame base with a frame index. Before
construction, only the reviewed frame setup (mov rbp,rsp) is exempted.

The actual linked Int64, Bool and Int constructors must retain the reviewed
allocation/return sequences: one constant malloc request, SCALAR header, a
single correctly sized argument store and return of that same allocation.
These are not sizes inferred from a Ref count or zero GC descriptor. The
consumer independently regenerates finite function disassembly and symbol facts
from the archived bytes, with inspection-tool identities bound in the receipt.

The finite component is 16 requested bytes for Int64 and 12 for each of four
Int/Bool Refs, totaling 64. Header bytes use the already admitted pinned Native
runtime convention. This is generated allocation-request correspondence, not
payload measurement or allocator footprint. The existing 80-byte conditional
Ref allowance and retained-core envelope remain unchanged.

The original synchronous observer stays outside product callbacks. Its recorded
identities are linked to the already checked source capture roles. Existing
seven-phase observations still require the same captures and pending input,
completed-output and metadata custody through cancel, stopped poll, cleanup
false/error and successful retry. This additional decoder does not run a second
owner or infer last-owner reclamation from clearing state.

Trust assumptions include the pinned compiler, System V ABI, inspected malloc
header convention, object/linker/symbol interpretation and GNU inspection tools.
The restricted frame checks are not a general machine-code verifier or arbitrary
alias analysis. Other platforms explicitly retain an unresolved status for this
additional component. There is no old-layout or old-receipt compatibility path.

Borrowed referents, construction transients, allocator rounding/fragmentation,
whole-parent overlap and Ledger generation/retirement remain unresolved. No
Actions original, reuse eligibility or net CI saving follows from this local
finite component.

## Ordered callback capture correspondence

The Linux x64 final consumer also derives the six construction-point allocations
from the object and actual linked parent function: the lifted start environment
and the advance, cancel, stopped, cleanup and child-work callbacks. A restricted
straight-line decoder relates private frame sources to the System V observer
arguments, checks each constant request/header and pointer/scalar store, then
checks the callback argument order at the existing parent-owner handoff.
Actual borrowed capture facts must match those roles at each offset. Sorting
identities alone cannot establish this: swapping terminal/cancelled or
family/measurement would preserve the identity set while changing the role.

The existing binary/object and tool identities and byte-exact regenerated
observations remain mandatory. The extra symbol facts come from the same actual
executable symbol read; the original symbol/disassembly logs and receipts are
not rewritten. Missing/partial/duplicate stores, aliases, unknown instructions,
control-flow entry and changed observer/handoff arguments reject admission.
This is a reviewed finite construction-point check, not a general compiler,
alias or lifetime proof. It depends on the pinned compiler/runtime, System V
callee-saved registers, indexed-header convention and existing owner's retaining
handoff. Other targets, callback body semantics, shared referents, transient
allocations, allocator overhead and whole-parent physical lifetime upper bounds
remain separate obligations. No Actions or reuse authority is created.

## Darwin ARM64 primitive Ref correspondence

The same five existing parent Ref roles also have a restricted Darwin ARM64
code path. The actual object and linked executable must agree on five ordered
typed helper calls, zero/negative-one initializers, returned `x0` aliases and
unique aligned private `x29` custody slots. The real observer must receive those
same slots in `x2` through `x6`. Both frame-pointer and stack-pointer stores are
translated into the same frame coordinates, so full, partial and SP-alias writes
cannot silently replace a Ref. Frame escape, partial frame-register changes,
unknown instructions/calls, external branch entry and a changed conditional
incref branch reject the finite correspondence.

The executed Int64, Bool and Int helper bodies must have the reviewed constant
allocation requests, scalar header, typed payload stores and return of that same
allocation. Their requested extents are 16, 12, 12, 12 and 12 bytes, totaling 64.
These are allocation-request facts; the 80-byte conditional Ref component is
unchanged. No scalar GC descriptor is used as a payload-size measurement.

The collector archives the actual object and independently regenerates scoped
symbols, relocatable object disassembly and linked executable disassembly at
final admission. Tool identities and executed binary/object digests remain bound.
The trust boundary includes the pinned compiler/runtime, Darwin ARM64 ABI and
LLVM/Mach-O inspection. The finite admitted calls include the existing provider
Owner handoff and callback retirement, not arbitrary foreign code. The private
slot check does not prove callback bodies, arbitrary aliasing or whole lifetime.

Ordered callback capture correspondence remains explicitly unresolved on Darwin
ARM64; only the existing Linux x64 decoder establishes that separate component.
Physical allocation footprint, payload/referent overlap, allocator effects,
Ledger generations, last-owner/GC reclamation and whole-parent upper bounds also
remain unresolved. A historical original reinspection retains its historical
source identity; it cannot replace a new submitted-SHA execution.
