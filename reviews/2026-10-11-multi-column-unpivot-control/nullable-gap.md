# UNPIVOT corresponding-component nullability: concrete common boundary

Source inspected at main `0f8b2b7ecb4d357f8e11254b60889241db5129e3`, adopted
by ordinary preparation merge `fbb0e84b348f6798da47856430f25cf95bb67b6b`.
This is a source-derived contract gap, not an executed checker rejection or a
new confirmed runtime defect. The equal-contract control remains a separate
unverified checker obligation. No product or common contract was changed.

The complete authored source is `source.sql`, with just one input row:

```json
{"id":1,"jan_amount":5,"jan_note":null,"feb_amount":null,"feb_note":"kept"}
```

Use the input declaration in `source-input.json`, with `max_items: 1` and
`jan_amount.nullable: false`; all other member contracts are unchanged.
`nullable-gap.control.program.json` is the complete ordinary Values control
for precisely that input and schema, without Frontend rewriting.

The selected positional rotation requires these ordered rows:

```json
[{"id":1,"amount":null,"note":"kept","month":"Feb"},
 {"id":1,"amount":5,"note":null,"month":"Jan"}]
```

The ordered output contracts are non-NULL Number `id`, nullable Number
`amount`, nullable String `note`, and non-NULL String `month` with independently
derived `max_utf8_bytes: 3`. Both rows survive EXCLUDE NULLS because each tuple
contains a non-NULL component. These expectations were authored from the input
and rotation rules, not from product output.

## Current refusal boundary

1. `expression_typing/signatures.mbt` constructs a non-NULL closed object;
   child nullability remains that of the checked field expression.
2. The Jan bundle therefore has a non-NULL Number component `amount`; the Feb
   bundle has a nullable Number component with the same name. Their `note`
   contracts are equal.
3. `relation_typing/unpivot.mbt::check_unpivot` compares the second selected
   bundle against the first with `value_contract.type_equal` and calls
   `IncompatibleColumn("private_feb")` when that comparison is false.
4. `value_contract/equality_steps.mbt::advance_type_equality` returns false
   when any compared child nullable bit differs.

The source-derived refusal points to stage 0, step 3,
`/stages/0/steps/3/unpivot/columns/1`. This path is a predicted location, not a
saved diagnostic. Executing the normal checker must confirm its actual result.

This agrees with the **current common specification**:
`docs/spec/language.md`, requirement
`reshaping.all-unpivot-columns-must-have-exactly-the-same-statically-proven-type`,
requires equal type and nullability. `docs/spec/query-text.md` already records
differing nullability as a common-profile gap. Do not label adherence to that
requirement an implementation bug or silently weaken `type_equal` globally.

The selected GoogleSQL reference
`d82db99a923a46571f543a13899dc791a7b6f743`,
`Resolver::ResolveUnpivotInClause`, compares corresponding annotated SQL value
types; its Number value type is not a per-column non-NULL guarantee. Thus the
standard-derived Frontend target and the exact ActQL admission contract must
be reconciled explicitly to close this input class.

## Required owner boundary

The proposed bounded common change is to admit corresponding contracts with
the same value shape while computing the sound nullable union for their output
(including recursive object components). It must retain type mismatches as
refusals, existing resource/work bounds, and an output contract accepting every
expanded input cell. Merely deleting the equality check would leave the first
column's narrower contract on the output and is unsound.

The common owner must decide and implement that contract change with the
normative requirement, checker/evaluator consumers and identities together.
The Frontend must not cast values, manufacture nullable evidence, or run a
second expansion path. This note does not assign a new implementation campaign
or widen String-label #1407's completed acceptance unit. The equal-contract
multi-column unit can proceed independently once its common control is proved;
the differing-nullability coverage remains explicitly incomplete until this
common boundary is resolved.
