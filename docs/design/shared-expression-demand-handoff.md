# Shared typed expression API handoff

This integration branch starts at lowering `7fe29ee` and exports only the
`expression_typing` implementation and its design guide from main `d80339a`.
It does not import `pipeline_check_context`, change shared contracts or implement
a second demand derivation. The seven exported files are byte-identical to main.

The original implementations are `41971a7` (indexed pending validations),
`41227eb` (typed topology), and `e836078` (source-relative conditional demands).
Those commits also touch unrelated main integration; consume this package-scoped
commit instead of cherry-picking that mixed sequence. This is an integration
export, not a change to main's expression semantics, and need not be applied
back onto main where the implementation already exists.

Use `node_form`, `child_count`, `child_at`, and `object_field_name_at` with the
exact `TypedExpression` retained by each lowered root. Node indices belong only
to that owner. `pending_validation_count` and `pending_validation_at` provide
indexed obligation access without copying the full list.

Use `derive_demands`, `demand_pointer`, and `demand_tests` under a cumulative
budget across roots. Charge the returned usage before proceeding to another
root. Rebase both occurrence and condition pointers to `/roots/i/source`.
An implicit ELSE has no source occurrence: preserve `None`, not an invented
pointer. Conditions refer to already evaluated values, not reevaluation.

Lowering owns the adapter and retirement of its duplicate conditional rules.
Its independent IF/CASE/coalesce/eager-boolean/literal tests should remain.
Do not infer execution permission from this API handoff. The ordered derive
row-kernel contract and outer expression-fragment registration are separate
main-owned deliveries and remain pending.
