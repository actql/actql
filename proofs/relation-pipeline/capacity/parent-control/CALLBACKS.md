# Dynamic scalar callback allocation correspondence

The existing current-chain Native fixture observes the same eleven candidate
providers before candidate dispatch. The census follows each distinct callback
identity while borrowing the candidates on the C stack. An indexed GC layout
establishes requested header/payload bytes for reference-bearing callbacks;
a SCALAR descriptor alone does not establish payload size.

For each dynamic scalar callback the observer now records its allocation identity
and code pointer relative to the observer function. These are identity facts,
not measured payload bytes. Relative code addresses permit executable-symbol
matching without treating ASLR or an address as a size. The observer does not
retain pointers, change reference counts or interpose on allocation.

On darwin-arm64 and linux-x64, the independent consumer reads the archived
object and the actual executed executable. It runs `nm` and the platform
disassembler (`llvm-objdump` or GNU `objdump`) on those bytes and checks a
deliberately restricted pinned debug-code sequence:

1. A constant payload request immediately precedes `moonbit_malloc`.
2. The returned allocation receives the SCALAR header.
3. Matching ARM64 page/offset relocations, or an x64 PC-relative relocation,
   identify a callback function.
4. That function pointer is stored at payload offset zero.
5. The linked executable has the same constructor-relative allocation site,
   request, header store and callback target.
6. Each live code pointer resolves to exactly one such allocation site.

The supported sequence requests an 8-byte code-pointer-only payload, plus the
pinned 8-byte header. Unknown sequences, missing live identities, altered linked
requests and mismatched object/executable sites are rejected rather than assigned
16 bytes by callback count. Repeated allocation identities are rejected; distinct
allocations with the same code still count separately. The generated object,
selective object/executable disassembly, symbols and inspection-tool digests are
content-bound in the original local receipt. The final consumer independently
regenerates the code observations from the immutable archived bytes.

The x64 decoder requires the adjacent constant request, malloc call, returned
allocation alias, 32-bit zero, header store, RIP-relative code address and
zero-offset code store. Object relocation fields must lie inside the matching
variable-length instruction; the linked target is computed from the next
instruction and signed displacement. Unrecognized forms do not receive sizes.

Constructor selection uses exact encoded function names, excluding lifecycle
functions with similar suffixes. GNU debug functions have zero-size symbols;
disassembly uses a finite range ending at the next real function and excludes
basic-block labels from range boundaries. The decoder preserves the actual
constructor start across those labels. Object and executable must expose the
same scalar site set. There is no historical-layout or old-recipe runtime
fallback.

## Scope and remaining obligations

The new result is a finite point-in-time **requested allocation extent** for the
observed candidate identity union. It is separate from GC descriptor measurements,
the structural 44-callback bound and the conditional 2344-byte construction
component. It does not turn any of them into a whole-constructor lifetime upper.

Compilation, the pinned runtime header convention, linker/symbol/disassembly
interpretation and the inspection tools remain trust assumptions. The consumer
checks the actual object-to-executable allocation sites; this is tested generated
code correspondence, not a formal verification of the compiler or allocator.
Allocator rounding, fragmentation, transient allocations during construction,
borrowed configuration referents, callback execution, and overlapping parent,
preparation and producer-read allocations remain outside this point union.
The existing seven-phase cancel / stopped poll / cleanup false / cleanup error /
successful retry checks and four preparation-storage points remain mandatory.
Explicit fixture references used for observation do not establish last-owner GC
reclamation or Ledger generation retirement.

No Actions provenance, reuse authorization or CI savings is inferred. Main
original qualification, comparison on a compatible subsequent main, ordinary PR
reuse, relevant-input fresh execution and net acquisition-inclusive savings remain
unfinished separately.
