# SQL names and result field labels

A SQL output has an evaluated value slot and an optional language name. A
returned relation also needs a String label for each visible field. These are
separate roles: assigning a label does not supply an alias, a new input value,
permission, currentness evidence or a relationship proof.

The Common frontend retains the optional original `NamePart` beside the same
evaluated slot. Explicit aliases and genuine implicit names (a simple column or
property path) retain their original meaning. A parenthesized or otherwise
computed expression does not gain a language name merely because its value
needs a physical slot. Existing column matching, duplicate-name, type, key,
NULL and ordering rules still apply.

## Result labels

An anonymous visible output uses `f<zero-based final output index>_`. All real
explicit and implicit output names are reserved before labels are assigned.
The label gains trailing underscores until it is unique under the existing
column-name matching rule. Output order and ordinal references do not change.
For example, `SELECT 1, 2 AS f0_` returns fields `f0__` and `f0_`; only the second
field has the authored SQL name `f0_`.

This is an ActQL presentation convention, not a GoogleSQL guarantee about
exact labels. Labels are assigned after SQL name resolution. They cannot be
used to recover an anonymous column through a CTE, star expansion, later Pipe
operation, member access or `BY NAME` matching. An actually authored `f0_`
continues to be an ordinary name. No prefix is reserved as an anonymity test.

A returned whole-row Object applies the same convention to the original
captured row's ordered visible fields. The ordinal belongs to that row, not an
outer SELECT, current set output or hidden compiler companions. Thus
`WITH t AS (SELECT 1, 2 AS n) SELECT t AS row FROM t` returns the row DATA keys
`f0_` and `n`, while neither `t.f0_` nor `(t).f0_` becomes a legal reference to
the anonymous value. The original `t.n` remains named.

## Private compiler views

The public value contract and Object schema retain their existing layout. A
bounded private compiler view records the optional SQL names and nested views
of the same original expression and slots. The view can share immutable row
snapshots and type-join links. It contains no observed provider row, cached
validation result, current grant or runtime permission.

Member binding consults this original view before falling back to an Object
DATA key. Parentheses, supported row-preserving wrappers, arrays and aggregate
or navigation results retain the appropriate view of their original value.
Generic Object typing cannot promote an anonymous field into a SQL member.
An authored Object with a real `f0_` field remains distinct.

Computed receiver stars retain the actual generated Projection occurrences
and original receiver. They may share one evaluated receiver, but must not
replace an equal authored sibling expression before that sibling's namespace
validation. Expanded anonymous values remain present in the returned data.
Exclusion and replacement continue to address genuinely named fields.

Immutable snapshots preserve an earlier row/range meaning across supported
edits. A newly evaluated or renamed output receives the view of its actual
source slot. Metadata is never selected merely because an old input and a new
output share a String spelling. The existing value lowerer still determines
whether grouped values, old ranges and scalar operands are available.

## Group, window and set boundaries

Pipe AGGREGATE keys preserve explicit aliases and genuine implicit names.
A standalone unnamed computation contributes its value at the actual visible
aggregate output position with no SQL name. Its evaluated grouping slot stays
private. GROUP AND ORDER BY and suffix shorthand select that evaluated slot;
they do not turn its storage label into an authored key. Group comparability,
repeated keys, duplicate aliases and existing SQL GROUP BY grammar are unchanged.

Window and aggregate binding checks original arguments, filters, partition and
order expressions before evaluated-slot reuse. The resulting view follows the
actual output slot, including private-to-public projection. Anonymous analytic
staging does not depend on whether a later operation leaves a terminal SELECT.
Named duplicate handling retains its separate positional-set rule.

Set namespace views follow the same matched vectors as the value operands.
Strict and INNER ON projection preserve original optional names and nested
views while retaining the actual output spelling and physical slot. ORDER and
window binding resolve the original name to that slot; they do not reconstruct
an identity pair from a logical name. Subset alignment does not manufacture a
missing sibling or expose a generated companion as an authored column.

PIVOT validates its authored argument and axis through the same optional-name
scope. Untouched implicit physical index fields remain in the result, including
their anonymous role. Reading an index by its private spelling is not an
alternative to the original language lookup.

## Construction and lifetime

These views are compiler DATA under the existing Request. Fixed retained Scope
fields and conditional records, payload-bearing variants, callbacks, vectors,
Strings and Program material have separate construction quantities. Borrowed
name/schema backing stays with its original owner; sharing does not remove the
new references or the tag/storage of an allocated wrapper.

The original parsed Query, publication, Environment, catalog and capacity
carrier remain bound through pre-call quotation and growth. Conditional
geometry is derived from the same bounded parser constructors and complete
original schema/publication, without inspecting runtime rows or reparsing a
caller-supplied claim. Construction begins only after the existing Request has
admitted the simultaneous original, replacement and failed-child overlap.
A failed grow or compilation retains the original failure and cleanup owner;
a view, quote or returned label is never a release acknowledgement.

A shared type-join DAG can visit the same terminal repeatedly. DFS scratch and
surviving metadata are separate quantities. For one output field, the merge
accumulator retains each distinct incoming original view link at most once:
new joins append that original on the right, and a later repeat is found on the
accumulator's left spine before allocation. With D distinct nonempty incoming
original links, at most D minus one new Joined records survive, together with
their actual optional wrappers and old/new overlap. Traversal still spends the
original bounded Work; visit count does not become a survivor multiplier.
Different originals and opaque member/element paths are not identified by
structural or schema equality. The scan allocates no registry or work stack.

Receiver-field workspace likewise belongs to its selected constructor. A
normal SELECT with no computed receiver returns before making a physical-field
copy. The Request's conditional quote does not fund an eager field-width copy
on that ordinary path. Array/Map controls and old/new backing use the existing
shared collection recipe, while record variants use the central preparation
representation law, including the scalar tag of a payload-bearing Some.
