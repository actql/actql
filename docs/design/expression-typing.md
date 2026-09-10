# Expression type checking

`expression_typing.check` accepts one opaque, admitted
[`expression_syntax.Expression`](expression-syntax.md), an explicit environment,
and limits. It checks the type rules of the current common Expression vocabulary,
including text-time and row-local vector forms. The authority remains the
[Language type relations](../spec/language.md#value-contracts),
[Expression contracts](../spec/language.md#expressions), and their machine laws.
It neither evaluates an expression nor checks a whole Program.
The [Relation operation checker](relation-typing.md) consumes these type proofs
for single-operation schema checking. `usage` reports consumed work, text bytes
and typed nodes so callers can preserve cumulative budgets across expressions.

## Environment and result

Ordinary, left and right scopes are separately supplied non-null object
`value_contract.Contract` values. Their fields are complete; field contracts can
themselves be nullable. An absent join scope is not an empty or ordinary scope,
and missing fields are never inferred. Each scope is indexed once. Parameters
come from admitted `parameter_binding.Declarations`, not `BoundValues`.
Missing declarations fail, but missing invocation bindings are outside this
boundary. A default does not narrow a nullable declaration or prove an actual
pattern. The result retains the immutable environment and original expression.

Success returns an opaque `TypedExpression` with a root contract and read-only
per-occurrence annotations in preorder. `node_at` avoids copying an annotation
array. Each annotation has its retained syntax cursor, contract, and role:
ordinary expression, IN literal list, IN element, or implicit CASE ELSE NULL.
The implicit ELSE uses its CASE body as its source location. These annotations
do not replace the syntax tree or create a second public expression AST.
Literal JSON remains opaque JSON; decimal-looking business objects are not
recognized as a magic typed-literal format. IN's immediate scalar/Parameter list
has its separate typed-array role, as specified by syntax admission.

Issue kinds identify missing scopes/names, type incompatibility, unresolved
evidence, forbidden constructor values, static options, and budget failure.
`Issue.source` is the cursor used internally in normalized syntax;
`Issue.location` is its original source handle, resolved through the syntax
sidecar. Consumers must use the latter for user-facing paths, spans and ranges.
They do not pretend to reconstruct original token bytes through source escapes
or YAML folding. Environment failures
are anchored at the checked expression's root. No partial typed result escapes.

Diagnostic selection follows the failing check: per-operand domain checks point
to that operand (for example TRUE in `1 + TRUE`); whole-expression checks such
as cast compatibility and property lookup point to the containing cast/property.
Alias expansion does not invent an authored `cast.value` path. Structured origins
have no text range; embedded text retains the original slot plus a scalar range.

## Local evidence and signatures

The checker uses the shared contract joins and key-comparability rules rather
than treating JSON as a supertype. A flat partial-type arena retains unresolved
NULL and empty-array item holes. Peer groups first compute a common recursive
shape, then supply that evidence only to unresolved positions. Fully resolved
contracts are cached; already typed peer contracts are not replaced by the
joined output contract. Conditional branches, CASE, coalesce, array and object
construction participate in recursive local evidence resolution.

Immediate fixed scalar signatures type direct NULL operands when the domain is
unique. Explicit casts supply the target for literal NULL. Overloaded operands
require independent evidence; `NULL + NULL` and `NULL IS DISTINCT FROM NULL`
do not guess a type. `len(coalesce(NULL,NULL))` is not repaired by propagating an
arbitrary expected string type into the compound child. Empty arrays retain
non-null roots and `max_items: 0`, including when their peer array is nullable.
An explicitly typed empty array supplies evidence. An unresolved result reports
`NullTypeUnresolved`, meaning this environment lacks evidence, not that a later
Program checker can never admit the source with proven append/ModelTask context.

All branches are type checked, including undemanded branches. Conditions require
booleans; casts follow the closed conversion table; arithmetic prohibits implicit
decimal/binary64 mixing. Decimal result precision and scale follow the shared
formulas. Ordinary ordered comparison excludes references; equality uses
`KeyComparable`, allowing different decimal precision/scale. Constructors reject
opaque JSON and hidden references recursively, without prohibiting reference
fields, comparisons or joins themselves. Property access requires a complete
object; subscript requires a typed array and number index and yields nullable
items. Vector dimensions must match for scoring; concatenation checks an exact,
finite, representable dimension sum without adding a safe-integer ceiling.
Dimensions accumulate as exact integers; only the final total must be
representable as binary64, not intermediate sums in argument order.

## Type proof is not complete static admission

`required_profiles` reports the additional text-time/VecA dependencies, not their
admission. `pending_validations` records per-occurrence profile admission,
pattern validation, and text-time Host-envelope work, including undemanded
branches. Returned lists are detached copies. A literal regex/timestamp pattern
is still pending; being available now is not evidence that a parser has checked
it. Pattern validation includes canonical pattern AST/CID, timestamp token
combinations, and capture/replacement consistency. LIKE pattern validation is
also recorded. Regex capture and replacement arguments are restricted to
literal or Parameter forms: capture literals are nonnegative integers and
replacement literals are strings. Fields and computed expressions fail with
`InvalidStaticOption`, even when constant. Parameter values are not substituted
here; non-nullness, integer range and consistency with the parsed pattern remain
pending bound validation. Regex flags are restricted to non-repeated `m` and
`s`, matching
the [language profile](../spec/language.md#text-time); pattern execution is not
delegated to a host regex.

The checker validates types and known structural options, but does not parse
regex/timestamp patterns, bind invocation patterns, authorize profiles, select
Host ceilings or construct resource envelopes. It does not issue a checked Plan,
even when its pending list is empty. Base-profile and Program admission, runtime
binding, reference authority, demand lowering and execution remain separate.

Negative/fractional indices, invalid conversion data, division by zero, and
negative substring lengths retain their evaluation-time domain checks. The
checker does not evaluate literals to reject an undemanded runtime failure.
Conservative result types do not replace later bound inference or Host proofs.
No evaluation, normalization rewrite, Parameter substitution, template expansion,
lowering, semantic identity/CID, or expected-type override is exposed here.

## Budgets and ownership

- `max_nodes` counts expression occurrences, including IN-list annotations and
  implicit ELSE. Opaque JSON descendants are not expression nodes.
- `max_depth` bounds expression edges, imported contract edges, evidence traversal
  depth and completed contract height; each root starts at zero. Cached children
  do not bypass completed-type height checks.
- `max_work` is cumulative across environment import, scheduling, type arena
  allocation, signature checking, peer merges, evidence propagation and completion.
  A lookup/visit and each reserved child count as work; this is an implementation
  admission budget, not a language operation count or a CPU-time promise.
- `max_text_bytes` cumulatively charges visited names and strings in UTF-8,
  including environment names, literal text, static text options and newly
  assembled object-contract names. Explicit item-contract admission preflights
  JSON nodes/keys and reserves the same conservative allowance for the reader;
  importing the resulting contract consumes the remaining shared budget.

Zero budgets are legal but need not admit an expression. Negative limits fail
before work. Entire supplied scopes and Parameter contract trees are included,
even when unused; defaults and metadata are already admitted and merely retained.
These limits bound this layer's admitted work, not total process memory or the
already owned source tree. Some cursor views copy immediate child arrays; type
assembly shares immutable children and uses indexed access for fields and
Parameter declarations. Peer merging is proportional to the compared structures;
the shared work limit also bounds repeated comparisons of large nested types.

All traversal uses explicit stacks. Constructor safety and completed contracts
are cached, preventing repeated full scans of nested constructor results. Scope
lookup reuses prepared maps; property lookup uses UTF-16 binary search. No mutable
type holes escape a successful check.

## Verification

[Fixed type vectors](../../portability/corpus/actql-expression-typing-v0.1.json)
contain explicit accepted contracts and rejection categories. The generator
copies those expectations into MoonBit tests; it does not obtain them from the
product checker or evaluator. `check:expression-typing` checks freshness and
generator behavior. Product tests separately execute the vectors on JS, Wasm and
native, together with nested evidence, profile obligations, runtime-domain
separation, depth 10,000, wide scopes and cumulative-budget regressions. This is
type-checking evidence, not evaluation or complete ActQL conformance.
