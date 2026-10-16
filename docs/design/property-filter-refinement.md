# Non-null property evidence after a filter

The existing Relation Filter owner can strengthen the type of an original
checked Object property path when a strict comparison on that path must be
true for a row to survive. Property evaluation propagates a NULL receiver, and
a strict equality or ordering comparison cannot be true with a NULL operand.
Consequently every Object receiver and the leaf on that same direct path are
non-null in the surviving rows. This is type evidence; it supplies no values,
keys, references, permissions, Source authority or Model success observation.

The proof consumes the existing typed expression topology. Conjunction requires
both operands to be true. The implementation conservatively derives no such
proof from OR, NOT, CASE, null-safe comparison, computed receivers or an outcome
string alone. It does not introduce a parser, constant folding, expression
reevaluation or a second runtime predicate. Every syntactic branch still goes
through ordinary expression checking before evidence is considered.

Only the original declared Object path is rebuilt. All field names, sibling
contracts, scalar parameters and row-presence guarantees survive. A later
assignment or projection uses its own checked output contract and cannot revive
this proof for a replacement value. Scalar-only filters retain their existing
conservative schema. Traversal, copied field names and constructed type nodes
consume the same bounded Relation typing account.

This closes the existing INFER property obligation for programs such as the
README query: testing `risk.value.level = 'high'` proves the original `value`
object non-null, so its other originally non-null output properties remain
non-null on that path. It does not interpret the spelling `ok` as evidence or
substitute a constant for an evaluated Model output. Static compilation and
Effect shape checks remain distinct from an installed Model, approval, apply,
recovery and cleanup.
