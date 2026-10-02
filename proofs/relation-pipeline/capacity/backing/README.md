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
instance is narrower: at most three schema columns. Four actual state Maps use
the default eight-slot constructor. Input/projection ordinal maps contain exactly
the independently expected width; binding ordinals and the unused DISTINCT
snapshot contain zero entries. All four tables still have capacity eight on
empty input and after cleanup. Their total current table-slot structure is 32;
allocating a replacement snapshot before dropping its old reference can add
eight slots. That 40-slot arithmetic model is not an observed allocator peak.

The scalar overlay reads actual Map capacity, length and same-type owner alias
relationships. Capacity is the real Map's table-capacity field, with its equality
to `entries.length()` depending on the pinned core constructor/growth invariant;
the observer does not independently expose its private FixedArray identity.
Three metadata Map owners are checked not to alias. Cross-type table identity,
replacement allocation overlap and GC disposal are not claimed verified. This
conditional source connection must not be upgraded into a physical byte union.
No separate test ledger replaces actual state observations.

The new `oversized-metadata-map` mutation changes the real constructor to
`Map([], capacity=16)` without changing the data result. The existing search,
typed shrinker and target replay must preserve its constructor-bound violation.
This is a violation of the stated table bound; it is not claimed to prove
exhaustion of the larger declared byte reservation. Existing resource mutations
remain. The core probe includes updates/clear at three keys and a seventh-key
growth to demonstrate why the no-grow premise cannot be omitted.

JS engine layouts, Map/Entry allocation bytes, wrapper/header bytes, retained prior buffers,
the complete simultaneous-backing census, the 256-byte parent allowance and
final reservation handoff remain incomplete. Slot observations cannot be
admitted as byte claims. The parent byte guarantee therefore remains conditional.

CI runs these additions through the existing capacity campaign and retains
receipts below `.artifacts/relation-pipeline/capacity/backing-core/`. For a local
change use the touched backing Node tests, `backing/check.mjs` for the Lean model,
and `core-probe.mjs js` for the four small core tests. The runner copies the
reviewed templates to `_build/array-backing-probe/`; run Moon formatting there,
not inside the source template directory. Generated files in the template
directory are rejected before execution or audit. Complete target and
pipeline campaigns belong to exact-SHA CI; no new handwritten operator
combinations, algorithm, reservation formula or runtime owner are introduced.
