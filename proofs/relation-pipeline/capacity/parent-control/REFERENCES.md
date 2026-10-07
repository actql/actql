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
