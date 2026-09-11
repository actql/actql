# Capacity witness wire admission

`capacity_witness.admit` checks the common wire representation of
`actql-bound-witness/0.1` from the pinned protocol schema and the language's
[resolved-limit rules](../spec/language.md#resolved-limits). It returns an opaque
`WireWitness`: an integrity-checked **claim**, not an authenticated source fact,
validated law application, resolved limit or runnable Plan evidence.

The reader checks all five closed source forms and their exact role pairing,
all nine units, nonnegative safe-integer values (positive for author guards),
registered governing law names and all seven closed derivation operations.
Optional clamp input is absent or a CID, never null. Source strings follow the
schema, including the `$` prefix on author paths; existence of that path or
subject in its actual source is not established here.

Dependencies and minimum input references have canonical, ascending, unique CID
spelling. Repeated add operands remain distinct occurrences, although their CID
appears once in the dependency set. Every source and derivation reference must
appear in that set. Additional declared dependencies are retained for later
closure/application validation, not silently dropped or treated as verified.
The referenced bodies are not resolved by this reader.

The expected witness CID must equal both the claimed identity and the hash of
the canonical preimage with only the root `witness_cid` excluded. Hashing the
complete reconstructed wire form must also match the original bytes. This
rejects whitespace, alternate number spellings, normalization repairs and
different member order; it does not repair signed artifacts. The emitter uses
the shared UTF-16 comparator, not the platform's default string ordering.

Bytes, nodes and depth are bounded before admission. The emitter traverses only
the checked closed shape: its object/array nesting is fixed and cannot contain
an arbitrary recursive value. Hashing does not construct a full output string
or byte array. Parsing and the owned cursor do still allocate input structures;
these limits are not a total heap limit. Returned reference arrays are detached.

`capacity_host_witness.admit_wire` consumes this common result and rebuilds the
Host witness from its exact admitted policy field. Comparing the rebuilt CID
checks the complete field/unit/law/value/source/dependency application. A
self-consistent wire claim with the wrong unit passes integrity admission but
fails this Host-source boundary. Existing direct Host byte admission and wire
identities remain supported unchanged.

Fixed test cases use independently computed Node SHA-256 identities for all
source/derivation combinations and all units. Negative fixtures have correct
self-CIDs but invalid shape, roles, values, dependencies or law names. All 14
Host applications also traverse the new common-to-Host boundary.

Non-Host source validation, proof/body identity, arithmetic reference closure,
enforced-limit dependencies, operation-specific applicability and complete
consumer discharge remain required. `WireWitness` is intentionally not accepted
as pipeline proof. Fixed Sketch `src/actql-bounds.ts` is reference material;
its optional dependency-map validation and global witness cache are not trust
mechanisms in this implementation.
