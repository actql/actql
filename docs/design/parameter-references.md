# Canonical Parameter reference indexing

`parameter_references` constructs the Parameter-reference portion of the
[stage and Program semantic envelopes](../spec/language.md#local-approval) from
admitted expression occurrences and an admitted declaration owner. It does not
discover all Program slots or create a completed semantic Program owner.

## Source correspondence and projection

Each supplied slot is an opaque result from
[normalized expression occurrence discovery](expression-syntax.md#text-provenance-and-locations).
The Expression's retained root origin must belong to the supplied source arena
and be a descendant of its selected root, not merely have an equal-looking path.
The source prefix relative to that root is followed by the normalized expression
node path. Thus two Parameters in a single expression-text scalar get distinct
structural positions. A stage body root gives local paths; a document root retains
its stage prefix. Diagnostic text ranges remain available through the retained
Expression, but are not substituted for these semantic pointers.

Names resolve to the supplied immutable declaration set. Each reference is exactly
`{name, path, type}`; `type` uses the
[annotation-free declaration emitter](parameter-binding.md#semantic-declaration-projection),
not an expanded checked type or a bound value. RFC 6901 escaping maps `~` to `~0`
and `/` to `~1`; indices use decimal spelling. The empty key has pointer `/`,
distinct from an empty pointer, which the envelope reference schema does not admit.
Records sort by path then name in UTF-16 order. Duplicate locations reject even
when their names agree. Repeated names at distinct locations remain distinct.

`emit_used_declarations` emits each referenced declaration once in UTF-16 name
order. Unreferenced declarations are absent from this projection, not rejected:
a local stage may use only some whole-Program declarations. Whole-Program unused
declaration rejection belongs to complete slot discovery. An empty supplied slot
list yields explicit `[]` references and `{}` used declarations; it is not proof
that the Program contains no references.

The result retains the exact source, declarations and occurrence owners and copies
the supplied slot-handle array. Indexed accessors expose immutable handles only.
This prevents later array edits from replacing the indexed source occurrences.

## Limits and remaining composition

`max_slots` and `max_references` bound collection size; `max_pointer_units` bounds
the sum of emitted pointer UTF-16 units after escaping, including repeated paths.
Equality is accepted, negative limits reject, and failures return no partial index.
Pointer construction charges before appending each fragment. Sorting is bounded
by those collection/text limits; it is not charged as a separate comparison count.
Source and normalized paths are materialized iteratively from already admitted
trees, whose node/depth limits still apply. These are not aggregate process-memory
quotas or a replacement for shared Program-wide work accounting.

The text, measurement and hash Writers share the reference/declaration emitters
and their independent byte/node/depth limits. Defaults can appear in the output;
this is an internal identity-preimage API, not a public explain response.

The [local pipeline collector](pipeline-parameters.md) now derives operation
slots from one checked pipeline and shares work across discovery and indexing.
Enclosing grammar-slot selection must still cover inputs, operations, Results,
effects and opaque binding references, preserving literal opacity. The caller
must also bind the declaration owner to that Program, check complete usage, and
construct the closed stage/root envelopes. Supplying a valid subset here does not
prove completeness, Invocation consistency, capacity applicability or permission
to execute. The older Sketch reference resolver's `$.field[index]` paths and
generic recursive discovery are not the current reference contract.

Tests cover local/root coordinates, repeated text references, exact owner and
subtree rejection, unknown names, duplicate locations, opaque literal data,
annotation-free types, canonical sorting and escaping, exact pointer limits,
deep expressions and a fixed independently hashed UTF-8 preimage on all targets.
