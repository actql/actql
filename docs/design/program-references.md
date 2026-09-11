# Source-owned Program reference inventory

`program_references.prepare` combines one actual Program's static request slots
with every stage's operation/Effect Parameter inventory. Stage count, ordinal
and exact prepared source owner must all match. Equal-looking declarations from
another prepared owner, missing stages, repeated stages and reordered stages
cannot be assembled into an inventory. Input arrays are copied; the inventory
retains the request owner and each immutable stage-use owner.

The normative reference shape and coordinates are defined by
[Canonical identities](../spec/language.md#canonical-identities). Every local
index uses paths relative to local_body, while the Program index starts at the
original decoded source: `/stages/<index>/...`, not the Program descriptor
array. This ordinal is a source-array coordinate, not a semantic stage ID or
public step identity. Common Parameter occurrences retain normalized expression
subpaths for text notation; direct request holes retain their whole-value slot.
Binding paths use RFC 6901 escaping for both input and request field names.

Parameter and Binding indices remain separate. A Binding reference emits
`{name,path,type}`, where type is the annotation-free opaque declaration, never
a concrete Ref or a checked value. Used Binding declarations are sorted once by
name; repeated uses at different paths remain separate references. Parameter
indices reuse `parameter_references` for declaration lookup, duplicate-location
checks, canonical path/name sorting and used declarations/values. Empty local
maps/lists remain explicit. Local use does not import declarations used only by
another stage. Binding location uniqueness follows from the owned request-slot
enumeration and the one-to-one escaped source coordinates, not from caller
supplied paths.

## Cumulative limits

Preparation charges retained request preparation once and each retained stage
use preparation once. It then charges occurrence gathering, direct request
Parameter decoding, local indexing and Program indexing. Slot/reference caps
count unique admitted grammar occurrences across the entire Program, including
Binding holes, not a separate allowance per stage. Literal request fields do
not become expression slots; their traversal was already charged by the request
owner. Existing zero-reference expression slots still count as slots.

Pointer limits account for both inherited stage operation indices and rebuilt
operation/Effect indices, plus new local and Program Parameter/Binding paths.
This bounds retained pointer copies rather than charging only the last emitted
form. Newly decoded request Parameter text has one shared additional cap; prior
operation/selector syntax limits remain attached to their earlier admission.
Canonical emitters share the enclosing writer's byte/node/depth limits and do
not materialize a second JSON tree. These are explicit work/storage units, not
claims of a whole-heap limit or exact wall-clock cost.

## Declaration use

`check_declaration_usage` separately enforces the language's
[invocation declaration-use rule](../spec/language.md#parameters): every declared
Parameter and opaque binding has at least one occurrence across all stages.
One stage need not use every declaration. Defaults, metadata and nested
reference-shaped business data do not establish use. The namespaces remain
separate even when a Parameter and binding have the same name. Empty declaration
sets pass. This does not reject unreferenced local declarations during inventory
construction, which still supports local used-only identity projections.

The successful opaque `DeclarationUsage` retains the exact Inventory. Its
constructor cannot accept arbitrary occurrence lists or caller-asserted names.
The work cap includes retained inventory preparation once, followed by reference
and declaration visits and name units. Parameters are checked before bindings,
and each declaration set is visited in canonical name order; the first unused
declaration is returned with its admitted declaration object. Work exhaustion
does not return a partial success. This fixed diagnostic traversal order is an
implementation convention, not an additional language restriction.

## Bound Parameter projections

`bind_parameter_values` accepts a `DeclarationUsage` and exactly one admitted
`parameter_binding.BoundValues` from the same declaration owner. It prepares a
shared value-name index once and binds both the Program index and every stage
index atomically. Callers cannot omit a stage, supply different values by stage,
or pair equal-looking declarations from another owner. The opaque result retains
the usage proof and exact value set; its stage accessors return the corresponding
`parameter_references.BoundIndex`. Local values contain only local uses, while
the Program selection covers every declared Parameter after usage validation.

The cumulative work cap charges prior usage work once, shared value indexing
once, selected entries in each projection and one visit per stage (including
stages with no Parameter use). It does not reconstruct the complete binding map
for each stage. A late stage budget failure exposes no partial aggregate result.
Value admission's node/depth/text budgets remain attached to the original binding
operation; this projection does not re-admit or copy recursive values. Existing
typed-value emitters preserve decimal/duration identity rules and share writer
limits. These preimages are not Program/stage/Invocation envelopes.

Binding concrete opaque references, issuer evidence, Input/Effect consumer type
checks and pipeline validation against the same bound values remain separate.
In particular, attaching Parameter values here does not resolve operation guards
or prove that existing pipeline checks used those values.

## What this does not certify

The inventory closes composition of the currently admitted reference roles,
not complete Program admission. Input/Effect body grammar, Catalog/request type
compatibility, concrete bindings and all other
static/runtime obligations still require the final Program boundary. Invalid
source is not made valid because its references can be indexed. No Program,
stage or Invocation CID is issued here; their envelopes must bind this inventory
only after the corresponding admission checks. The test's unused Binding
declaration intentionally remains available but absent from used projections;
that fixture is reference-index evidence and fails `check_declaration_usage`,
not a claim of a valid executable Program. Passing declaration usage also does
not certify complete Input/Effect grammar or correct consumer types; the final
Program constructor still needs those independent checks and this usage result.
No lowerer, evaluator or SourceView acquisition is added.

Tests fix a two-stage combined operation/Effect/request inventory, repeated
Binding uses, escaped local/Program pointers, local used-only declarations,
annotation-free output, array-copy ownership, missing/reordered/foreign owners,
shared slot/reference/work/pointer caps and three-sink output boundaries.
