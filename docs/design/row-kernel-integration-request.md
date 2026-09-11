# Ordered derive: shared contract integration request

Status: proposal only. This document neither registers a wire form nor grants
execution support. No specification, schema or pin is changed here.

Ownership: lowering proposes and consumes; main/integration finalizes and changes
the shared schemas, registry, laws and pins. Approval of this proposal does not
transfer that ownership to the lowering branch.

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

### Existing contracts and the precise gap

The stage contracts already define `schemas.derive_binding`, version
`actql-derive-binding/0.1`, pinned as
`sha256:b6a35f38e753f19ffd9f4c3265ff4865f85415a3b194bdbf280115227a03ac34`.
This is evidence: it binds the AoA node, input/output contracts, limits,
source mode, input passthrough and failure scope. Its binding entries contain
`name`, `checked_expression_cid` and `context_contract_cid`. Reuse it; do not
replace it with an independent lowering-owned evidence family.

The expression contract already defines typed expression nodes and their
evaluation laws. What is missing is the executable ordered-binding container,
per-occurrence value-version reference mapping, and its registered capability.
Expression-fragment root admission must explicitly cover `/bindings/i/expr`;
ordinary expression-node validity alone does not establish that admission.

One existing mismatch requires main's decision: `derive_binding.bindings` has
unconditional `minItems: 1`, whereas the language admits empty snapshot maps.
Proposed fix: allow zero entries for `snapshot_map`, require at least one for
`ordered_array`. Do not delete the no-op node or silently exempt its evidence.
This changes the evidence schema/pin, not the unchanged map node representation.

### Proposed executable form (not registered)

Prefer an explicitly negotiated ordered-parameter alternative of `REL.derive`,
with the ordinary single Relation input, rather than inventing a new opcode.
The illustrative parameter body is:

```text
{
  row_kernel_contract_cid: <main-registered extension contract CID>,
  bindings: [
    {name: "old", expr: {op: "field", body: "amount"}},
    {name: "amount", expr: {op: "add", body: [
      {op: "field", body: "amount"}, {op: "literal", body: 1}
    ]}},
    {name: "total", expr: {op: "add", body: [
      {op: "field", body: "old"}, {op: "field", body: "amount"}
    ]}}
  ],
  references: [
    {at: "/bindings/0/expr", target: {input_field: "amount"}},
    {at: "/bindings/1/expr/body/0", target: {input_field: "amount"}},
    {at: "/bindings/2/expr/body/0", target: {prior_slot: 0}},
    {at: "/bindings/2/expr/body/1", target: {prior_slot: 1}}
  ]
}
```

The names above are proposed wire fields, not accepted syntax. Main must register
the exact parameter alternative and capability before emission. The extension
depends on the existing Relation operation contract, expression schema/laws,
Value Contracts, derive evidence and applicable capacity/limits contracts.
Reuse the enclosing checked context's pins; do not introduce independently
negotiated copies. Older adapters lacking this exact capability cannot execute
the alternative. Existing `REL.derive` map `exprs` parameters stay unchanged.

Keep `field` expression nodes unchanged. The reference table resolves their
occurrences to checked value versions, rather than adding expression opcodes.
Each entry points to exactly one field-expression node, relative to this body.
Every field occurrence has exactly one entry, including repeated references;
there are no entries into literal payloads or structural strings. Store entries
in binding order then normative expression traversal order. Missing, duplicate,
extraneous or dangling entries fail admission. Target is an exclusive sum of
`input_field` and `prior_slot`, not two optional fields.

For binding i, `prior_slot: j` requires `0 <= j < i`; its name and contract must
match that exact slot and the checked reference. `input_field` must match the
checked original field and type. A previous slot of that name takes precedence;
an otherwise available input remains accessible before a future shadow. The
executor must not re-resolve names differently from this admitted mapping.

### Checked context, demand and evaluation

Existing `context_contract_cid` evidence must resolve the input schema, visible
prior-slot value versions and checked types for that binding. The checked
expression evidence must bind its result type and demand obligations. The node,
contexts, input/output contracts and limits must belong to the same checked
consumer; independent valid hashes are insufficient. Main should extend the
existing evidence owner only where its current referenced context lacks these
facts, rather than duplicating inference in this proposed parameter body.

- Snapshot maps use only input references and canonical UTF-16 binding-name
  order. Ordered arrays use authored order, unique normalized slot names and
  exact prior-slot references. Their forms are not interchangeable.
- Admit the complete required input before shadowing. Preserve admitted unknown
  fields of open inputs. A shadow replaces the value and type without coercing
  it to the old type; untouched input fields remain in the logical output.
- Evaluate logical row, then binding, then expression children in their specified
  order. Each authored RHS remains demanded even if later dropped. IF/CASE and
  coalesce retain their existing lazy demand; AND/OR remain eager.
- Retain the shared row frame until all demanded slots succeed. Report the first
  failure at that row/binding/expression, with no partial successful operation
  output. Diagnostics map back to source separately from semantic identity.
- Key/order/policy proofs are consumed from checked evidence, never inferred
  afresh by this executor. Replacement cannot silently retain an obsolete proof.

### Resource enforcement

Use the admitted limits referenced by `limits_cid`, preserving their units and
scope; the extension must not invent substitute static capacity proofs.

| Scope | Runtime enforcement point |
| --- | --- |
| Input rows, nested values, bytes and depth | Before admitting input, including overwritten or unread required values |
| Expression roots and temporary values | Before allocating/traversing the relevant node/value under existing root limits |
| Retained output | Charge the full logical derive row, including passthrough fields, before subsequent select |
| Live values | Account for retained input, active slots, expression temporaries and pending output; release only when no longer live |
| Total work | One cumulative counter across rows, bindings and expression traversal, including variable-size value work |

Check additions for overflow. Do not allocate an unbounded collection and check
afterward. Shared immutable storage may reduce physical live allocation but must
not reduce a logical output-size charge. Slots never reset cumulative budgets;
later projection cannot excuse excess derive output. Failure returns no partial
fragment result, never a truncated prefix. Main must name the existing measure
for each scope or explicitly define a missing measure before registering it.

### Canonical identity and compatibility

Canonicalize using the existing value rules. Authored binding order, expression
bodies and occurrence targets participate in the executable node identity;
source locations do not. Preserve literal data, reference multiplicity and
empty map nodes. Never sort ordered bindings by name.

Keep the hash dependency graph acyclic: admitted expression/context/limit
contracts and the extension pin feed the executable node; `derive_binding`
then references that node CID. Do not put that evidence's self-CID back into the
node it identifies. Main must finalize any further enclosing fragment references
under the existing graph rules.

Unchanged map executable preimages remain unchanged. A revised evidence schema
or registry pin can still affect enclosing artifacts: main must inventory those
dependent identities and preserve old evidence separately. No guessed CID,
placeholder pin or automatic saved-plan rewrite is permitted here.

### Independent acceptance vectors for main's contract suite

These expected outcomes are specified independently, not obtained from the
lowerer. Exact wire bytes and CIDs are to be fixed by main after registration.

| Vector | Expected outcome |
| --- | --- |
| Above body with input `{amount: 10, extra: "kept"}` | `{amount: 11, extra: "kept", old: 10, total: 21}` |
| Map `{a: x, b: a}` with input `{x: 1}` | Static missing-input reference; `b` cannot read map sibling `a` |
| Map `{b: x + 2, a: x + 1}` with input `{x: 1}` | Binding order `a,b`; retain `x`, add `a=2,b=3` |
| Empty map with admitted input | Unchanged rows/schema/order, retained no-op node and input/budget checks |
| Ordered empty bindings | Reject array form, not a no-op |
| Self reference without input, forward-only reference, duplicate normalized slot name | Static rejection |
| Read input before its later shadow | Exact input target, never forward slot |
| Reference to current/future slot, altered type/context, missing or extra occurrence | Artifact admission rejection |
| Literal object containing `input_field`, `prior_slot` or `$param` keys | Opaque data, no reference-table entries inside it |
| Rows `{a:1,b:0}`, `{a:0,b:1}`; slots `x=1/a`, `y=1/b` | Failure row 0, slot 1, not row 1, slot 0 |
| Unused slot `1/0` then select another field | Fail; select cannot remove its demand |
| `if(true,7,1/0)`; eager `and(false,(1/0 > 0))` | First returns 7; second fails |
| Invalid input field that a slot overwrites | Reject input before evaluating shadow |
| Exact budget versus one unit over, including nested retained data | Success versus atomic budget failure; no per-slot reset |
| Same nodes after failed execution | Fresh invocation unaffected by prior values or counters |
| Adapter lacks row-kernel capability | Unsupported execution, no fallback decomposition |

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

### Additional values-node parameter contract lookup

Integration response: main inspected `2e8f0a0` and accepted ownership of this
missing binding. Main will provide the closed params schema, registration and
dependency pins, schema type-contract representation, bound-cell/literal rules,
independent canonical vectors (empty/duplicate/ordered rows, decimal and nested
data), and semantic row-to-contract validation beyond JSON Schema. Track this
as an independent small contract alongside ordered derive. Lowering must not
emit it as a registered/conformant executable node before that delivery.

The `REL.values` mapping exists in Language and its zero-input/relation-output
signature exists in `actql-aoa.json.target_registry_requirements`. This must not
be described as an entirely missing operator contract. However, searches of the
lowering base, local main, and the inspected AoA sources have not located its
exact executable parameter schema (including how row contracts and bound cells
are represented). Source `values.schema/rows` syntax is not by itself authority
to copy those fields into an AoA node. Main/integration should identify the
existing parameter owner or finalize that binding before wire emission here.
This request does not propose a fallback opcode or external-source rewrite.

Values capture and the private four-operation execution tests can proceed using
the checked cells. Full values-node wire and whole-pipeline contract conformance
remain unproven until this binding is identified. Schema/registry/pin changes
continue to belong to main/integration, not this branch.

Checked expression lowering, exact typed references, immutable parameter
association, pure scalar evaluation and independent resource/failure tests can
proceed. We do not label a locally invented array-node representation a validated
AoA fragment or silently fall back to Host row rewriting while the contract is
unresolved. Final four-operation fragment completion remains open.
