# Array and Map backing obligations after the structural pilot

The official core archive is independently fixed by `toolchain.json` and its
SHA-256. `core-profile.json` records source hashes compared byte-for-byte with
that verified archive. A compiler version string alone cannot substitute for
the installed core source. This is not a completed capacity certificate.

On native and the existing Wasm target, Array contains a fixed buffer and a visible
length. `capacity()` observes the former; `clear()` changes only the latter.
Unused reference slots remain reachable. On JS, Array is an engine Array and
`capacity()` returns its visible length. It does not reveal V8 backing capacity.

For admitted high-water length H and initial/reserved capacity I, ordinary push
growth has current buffer slots at most `max(I, max(8, 2H))` for H > 0, and I
for H = 0. I must come from the input/configuration contract; it cannot be
replaced with the measured capacity. The source doubles capacity,
but switches to the exact requirement when Int32 doubling wraps. A live-backing
bound must also establish the number of distinct retained buffers. One cannot
multiply current length by a per-element byte size, assume clear freed storage,
or assume all historical backings vanished. Repeated exact growth near Int32's
limit especially prevents an unjustified geometric-history argument.

`ArrayBacking.lean` proves the admitted single-push upper bound, two-buffer
growth overlap and preservation across clear, with an explicit Int32 fallback
lemma. The arithmetic model performs no allocation. The finite core probe
exercises real push, clear, a reserved empty Array and an explicitly created
ArrayView holder. That holder is part of the fixture operation; it is not an
observer inserted into production. It demonstrates why equal Array-wrapper
identity cannot establish stable backing identity across growth. Source hashes
and finite compiled observations do not prove the entire core implementation.

The existing registered-pipeline capacity runner invokes this probe on its
requested targets, then records `.capacity()` from the real DISTINCT state
using the existing source overlay. `pipeline.mjs` independently derives row and
column bounds from the oracle's input at the DISTINCT occurrence. The names
arrays are made with exact schema width; keep, comparison terms, received
indices, current output and row temporaries are bounded by their admitted
row/column high-water limits. Output inner capacities use the input-row upper
bound, not the measured survivor count. The scalar observer stores no Array,
ArrayView, or additional persistent holder.

These are bounds for each current container. They are deliberately not summed
as unique-allocation bytes: capture and accepted output can share an inner row,
an Array wrapper can reallocate, the nested merge retains another index buffer,
and previous buffers require a separate holder census. A scalar checkpoint
does not observe the transient allocation inside core growth. On JS the gate
checks visible lengths only; on native/Wasm it checks current fixed-buffer
slots. Both are separately bound to the requested target's execution receipt.
The audit also checks probe source, actual target facts, command, core profile,
archived binaries and logs. Whole native probe executions copied into JS/Wasm
slots are rejected at the existing audit entrypoint.

The builtin linked Map source is also pinned to the verified core archive.
`MapBacking.lean` proves no growth for an arbitrary finite admitted trace with
at most six distinct keys, including clear and updates. The concrete pipeline
instance is narrower: at most three short-name schema columns. Three actual
ordinal Maps use the default eight-slot constructor: input/projection contain
exactly the independent width and binding contains zero entries. The current
24-slot structure remains allocated on empty input and after cleanup.
Snapshot is now an empty `Array[(String, Value)]`; row sources are also an empty
Array in this pilot. Neither is passed to a Map-typed FFI reader. Active stepped
metadata, nonempty snapshots/caches or cursor handles are refused by the pilot.

The scalar overlay reads actual Map capacity, length and same-type owner alias
relationships. Capacity is the real Map's table-capacity field, with its equality
to `entries.length()` depending on the pinned core constructor/growth invariant;
the observer does not independently expose its private FixedArray identity.
Three metadata Map owners are checked not to alias. Those portable scalar
observations do not expose cross-type table identity; native descriptors below
add current-point correspondence. Replacement overlap and GC disposal remain
unverified in the production pipeline. This
conditional source connection must not be upgraded into a physical byte union.
No separate test ledger replaces actual state observations.

## Conditional native requested extents

`native-profile.json` separately pins the native object headers and runtime
sources to both official compiler archives. The admitted platforms are Darwin
arm64 and Linux x64, with eight-byte pointers. The probe's C stub borrows a real
Map, reads its compiler-generated GC layout descriptor, locates the actual
reference-array table, and visits its distinct current Entry pointers. It stores
no object pointer, allocates nothing and never adjusts reference counts. The
reader checks descriptor shape and offsets; it does not cast an invented Map
struct or treat the public capacity counter as a backing identity.

Native child-state overlays now pass the actual input, binding and projection
Maps to that reader with all three FFI arguments explicitly borrowed.
They emit decimal owner/table identity tokens and requested extents at the
existing observation points. Admission checks distinct simultaneous identities,
independent key/slot counts and input-derived extent bounds. Tokens are not
global allocation generations and are never used to infer survival between
observations; reused addresses after release must not be conflated.
The portable overlay emits no native descriptor. The real registered pipeline
campaign and its independent receipts must validate these observations on CI.

The C descriptor reader is allocation-free. Its JSON formatting wrapper creates
only an observer String; formatting/log storage is instrumentation, outside the
measured production Map leaves. No Map pointer or holding reference survives
the synchronous borrowed observation. Temporary source files are exclusively
owned by one runner, checked before reuse/removal and restored with the package
overlay. The audit independently reconstructs their exact source hashes.

Declared field order matters. Entry's `prev` at offset zero is followed by
padding before `next` at eight, then `psl` at 16, `hash` at 20, `key` at 24 and
`value` at 32. Tail padding yields a 40-byte payload; the object header adds
eight bytes. Summing field widths without internal padding gives the wrong
bound. Map has a 40-byte payload too. Its eight-pointer table requests 72 bytes
including its header. Thus the conditional current Map leaf extent is
`120 + 48 * keys`; the admitted three-key bound is 264 bytes.

`NativeMapExtent.lean` proves the arithmetic upper bound and conditional
three-map total `360 + 96 * width`. Snapshot Array storage is accounted for
separately; the obsolete snapshot-Map replacement theorem is removed. These are source/ABI-dependent requested
extents. The core probe confirms finite instances, distinct actual table
identities, retained identity after clear, and two explicitly held replacement
objects. Its deliberate holder is test behavior, not an observer holder.

This is not yet the native pipeline's complete live allocation union. Borrowed
key Strings/transitive values, allocator bookkeeping/arenas, collector buffers,
other state objects and reservation custody remain obligations. JS and Wasm
must not receive this native byte evidence; the independent core and child-state audits check
native runtime provenance and rejects target substitution. The unconditional
capacity-claim gate remains closed, including the parent 256-byte allowance.

## Selected native Array storage and same-point identity union

The two name Arrays, completed sort-index Array, empty tuple snapshot and
empty row-source Array are observed through
monomorphic borrowed native calls on the actual child fields. Their owner is
`Array { buf, len }`: pointer at offset zero, Int at eight, pointer-aligned
payload 16, header eight, hence 24 bytes. The pinned runtime requests a buffer
header of eight plus `4 * slots` for Int and `8 * slots` for references. Names'
String referents are not included. Tuple and BindingRowSource referents are
not included: independent zero-entry/zero-capacity checks limit those two
arrays to empty storage. No nonempty tuple/enum byte claim follows.

These formulas come from declared fields and pinned runtime allocation code.
The core fixture checks actual descriptors, shared static empty buffers,
different owners, growth to a fresh backing, a deliberately retained old view,
and clear retaining the grown buffer. It is finite correspondence on the native
ABI; the observed values are not used as a maximum or as the upper-bound input.

At each existing child checkpoint, admission checks the real backing capacity
against the independently derived schema/high-water bound. It deduplicates the
simultaneously observed owner/backing identity tokens, rejects inconsistent
facts about aliases, and counts copies separately. Static empty buffer storage
is counted once and reported separately from dynamic requested extents. Neither
empty visible length nor cleanup success implies that backing storage vanished.
No identity is unioned across polls, and the observer stores no production
pointer or new holding reference beyond the borrowed call. JSON strings/logs
are instrumentation allocations, outside these selected production leaves.

`NativeArrayExtent.lean` proves the slot-to-storage implication and an arbitrary
finite identity union bounded by the sum of supplied per-allocation ceilings.
The same identity contributes once. The correspondence gate supplies the
selected five Array facts (including the optional completed index); this is not yet the
complete allocation or holder census. In-progress merge buffers, Value row
buffers, all control objects, assignment overlap between checkpoints, final
reservation custody and the 256-byte allowance remain unfinished. JS/Wasm
reject these native descriptors; their existing portable correspondence remains
required. Common changes include the native overlay, descriptor admission,
probe, typed model consumers and audit requirements; no unchanged-common claim
is made for this extension.

The new `oversized-metadata-map` mutation changes the real constructor to
`Map([], capacity=16)` without changing the data result. The existing search,
typed shrinker and target replay must preserve its constructor-bound violation.
This is a violation of the stated table bound; it is not claimed to prove
exhaustion of the larger declared byte reservation. Existing resource mutations
remain. The core probe includes updates/clear at three keys and a seventh-key
growth to demonstrate why the no-grow premise cannot be omitted.

JS/Wasm engine layouts, remaining runtime object bytes, retained prior buffers,
the complete simultaneous-backing census, the 256-byte parent allowance and
final reservation handoff remain incomplete. Slot observations cannot be
admitted as byte claims. The parent byte guarantee therefore remains conditional.

CI runs these additions through the existing capacity campaign and retains
receipts below `.artifacts/relation-pipeline/capacity/backing-core/`. For a local
change use the touched backing Node tests, `backing/check.mjs` for the Lean model,
and `core-probe.mjs js` for the four small core tests. Native layout changes use
`core-probe.mjs native` for six small tests, rather than the full campaign.
The runner copies the
reviewed templates to `_build/array-backing-probe/`; run Moon formatting there,
not inside the source template directory. Generated files in the template
directory are rejected before execution or audit. Complete target and
pipeline campaigns belong to exact-SHA CI; no new handwritten operator
combinations, algorithm, reservation formula or runtime owner are introduced.

## Metadata cursor responsibility

The typed source census binds the current state fields, tuple snapshot and
RowNameCharge/RowMetadataLookup representations. This is source structure, not
an allocator census. Both cursor records borrow their schema/name and retain
the existing RowWorkspace. Their one-slot reserve/release is logical work
space accounting, not an ABI conversion for the record or its referents.

`row_metadata_custody_wbtest.mbt` cancels the real bounded owner with both cursor
handles retained and injects one delayed child cleanup. The false result leaves
the same handles open, scratch held and cleanup pending; retry closes them and
the child exactly once. Existing metadata-phase cancellation tests remain.
This lifecycle fixture does not promote the DISTINCT pilot into a general
metadata capacity bound. #677's chain preparation and callback-capture census
are a separate unfinished boundary.
