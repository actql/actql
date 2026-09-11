# SourceView static request slots

`source_request_slots.collect` consumes a source-owned staged Program and opaque
Binding declarations from that exact Program. It enumerates all static request
fields on connector inputs across all stages, retaining stage/input/field
coordinates and the original immutable cursor. Parameter and Binding holes
resolve against their separate declaration namespaces even when names coincide.
No concrete values are read or substituted. A separately parsed, equal-looking
Binding owner is rejected.

## Value-role decision

The normative owner is [Connector SourceViews](../spec/language.md#sourceviews),
including the explicit static-request-value-slots rule. The earlier Parameter
section already required whole-value substitution and opaque nested business
data, but did not spell out the request slot boundary. It is now explicitly
each static request field: an exact singleton $param or $binding is a reference;
everything else is literal data. The literal key is not another quotation
operator in requests. This avoids interpreting an arbitrary nested business key
as executable syntax and permits a declared object/array to fill one complete
request role without becoming a recursive template.

Reference discovery therefore depends on authored source, not on whichever
Catalog schema happens to be selected. Letting a selected nested schema decide
whether a business object is a reference would change the Program's used-reference
projection with its environment. Under this decision, a nested reference-shaped
object is not an alternate spelling for a Host binding; a future nested-template
feature would need explicit source grammar, not an implicit recursive scan.

Sketch `87dc7144:src/actql-invocation-bindings.ts` recursively scans requests and
can interpret nested binding-shaped business data. That behavior is not carried
over: the clarified whole-value rule is authoritative. The embedded Program
request schema in actql-protocol-schemas remains a JSON object shape; role
interpretation, declaration resolution and contract-dependent type/coverage
checks are semantic checks, not a new JSON Schema type constraint. This changes
neither identity domains nor unrelated schema pins; source meaning now has an
explicit rule for the previously underspecified nested Binding case.

## Scope and limits

Connector/resource selectors must be present nonempty strings, and connector
inputs cannot also author a local carrier. Request must be an object when
present. Only actual source request fields become slots; local inputs and
Result/receipt imports do not. Empty/absent requests contribute no slots here;
this does not establish their admissibility under the resolved contract or
complete Input syntax. In particular, this collector does not replace schema
checks for explicit empty request or imply that a missing required role is valid.

Collection retains the original source order, not canonical reference ordering.
The reference-index stage must construct escaped normalized pointers and sort
by canonical path/name, then combine these occurrences with operation/Effect
uses. It must not mark declarations unused from this partial inventory alone.
Missing declarations and malformed immediate holes fail atomically. Literal
descendants are traversed iteratively only for resource accounting, never for
reference interpretation. Work includes Binding preparation once plus stage,
input and retained request data traversal; Parameter/source parsing budgets
remain the enclosing integration's responsibility. Slot limits are cumulative
across inputs/stages. These are work limits, not a whole-heap bound.

SourceView selection/completion, complete input-field grammar, Catalog membership,
request-schema assignability, required static/correlation role coverage, concrete
Ref admission and current Host authority remain separate. A resolved declaration
does not prove any of those properties or grant network access. This package
does not construct executable requests, run acquisitions or emit Program CIDs.
