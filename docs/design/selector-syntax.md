# Restricted Effect selector syntax

`selector_syntax.admit` decodes one Effect `where` element through the common
Expression syntax boundary, then checks the closed `SelectorPredicate` grammar
from [Predicates](../spec/language.md#predicates). It accepts text, structure,
and mixed expression notation without widening the position's allowed nodes.

Predicate nodes are eq/neq/lt/lte/gt/gte/in/not_in/like/contains/between,
is_null/not_null, and/or/not. Their operands are field, literal or unbound
$param nodes only. Boolean fields as complete predicates, truth tests,
is_distinct_from, arithmetic, functions, casts, property/subscript access and
join-field nodes are not added to this subset. Common decoding still enforces
arity, field names, literal-null comparisons, IN templates and LIKE's static
pattern shape before the restricted traversal.

Literal payloads are opaque. Business objects containing meta, $param or
expression-looking fields do not become syntax. Membership-list Parameter
holes retain the common decoder's explicit exception and occurrence paths.
The returned opaque Selector retains its complete normalized Expression, source
origins and unbound Parameter occurrences. It can use the common source emitter;
it is not a separately writable boolean flag or an executable predicate.

The fixed Sketch reference `87dc7144`, `src/actql-effects.ts::selectorPredicate`,
uses the same predicate set after binding and allows only field/literal
operands there. This source boundary also accepts $param because the normative
source grammar explicitly includes ParamRef, before binding. The reference's
separate legacy field/op/value path and singleton filter shorthand are not
introduced into this element-level API.

The implementation is iterative. max_work covers common syntax node work and
the restricted traversal's visited nodes and retained edges; the common node
allowance is capped by remaining total capacity before decoding. Other syntax
limits retain their meanings. Rejection preserves the common location sidecar,
including the original containing slot and decoded scalar range for mixed text.
Tests cover every admitted tag, forbidden root/operand forms, fixed normalized
source, exact work caps, opaque data, IN holes and depth 10,000.

This does not check the containing Effect's closed body or where-array shape,
target schema, comparison types, binding values, static pattern validity,
authority, execution support or runtime matching. Those remain required before
an executable Effect can be issued. Its immediate use is source normalization
and reference discovery for the complete stage semantic projection, without
mistaking Effect conditions for general computation roots in a Fragment.
