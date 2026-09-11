# Ordered derive: shared contract integration request

Status: proposal only. This document neither registers a wire form nor grants
execution support. No specification, schema or pin is changed here.

## Existing requirement

[Derive](../spec/language.md#derive) requires one row-major evaluation scope:
map form evaluates canonical-name-ordered bindings against the original input;
array form evaluates authored slots against exact input or prior-slot versions.
Unused expressions still execute. Expanding array slots into separate full-row
Relation steps is not equivalent when it changes first-failure row/slot order.

The specification says ordered bindings require a pinned shared row-kernel
extension, with roots at `/bindings/i/expr`, input references represented as
`{input_field: name}`, and previous values as `{prior_slot: i}`. The ordinary
Relation is the sole graph input; map-form AoA representation stays unchanged.

The current `relation_typing` public API supplies all resolved reference targets,
ordered bindings, source form, input/output schemas and typed expressions needed
to construct this. `docs/design/relation-typing.md` explicitly does not claim
a complete row-binding wire contract or permission to execute. Searches of this
branch, current main's machine contracts and the AoA package sources did not
locate the registered row-kernel wire schema and its pin.

## Requested integration unit

The integration owner should provide or approve one minimal shared contract
covering these existing semantics, rather than a new operator or alternate IR:

1. Identify the registered AoA operation and exact parameter field containing
   ordered bindings. Keep the existing map representation unchanged. Specify
   required capability negotiation so an older adapter cannot misread it.
2. Define the closed row-binding envelope: source form, ordered binding names
   and expression roots, per-occurrence input/prior-slot references, checked
   input/retained-output contracts and types, demand records, and failure scope.
3. Bind that envelope to the precise checked consumer and source schema. Preserve
   repeated references, alias/slot identity, and original expression locations
   without adding diagnostic locations to semantic identity unless prescribed.
4. Specify cumulative work/live-value/retained-output measurement scopes and
   their relationship to the existing capacity evidence. No per-slot reset,
   implicit truncation or early projection may erase evaluation obligations.
5. Supply the exact schema/law body, current 0.1 identifier, pin and independent
   vectors. Ordinary empty-map and array-shadow examples must be covered, with
   a row-0/later-slot failure competing against row-1/earlier-slot failure.

The specification already decides row semantics; this request is for its shared
wire/capability binding, not permission to redefine those semantics. Any part
already registered elsewhere should be referenced rather than recreated.

## Work that proceeds without this decision

Checked expression lowering, exact typed references, immutable parameter
association, pure scalar evaluation and independent resource/failure tests can
proceed. We do not label a locally invented array-node representation a validated
AoA fragment or silently fall back to Host row rewriting while the contract is
unresolved. Final four-operation fragment completion remains open.
