# Multi-column UNPIVOT: independent candidate control

Prepared from authored expectations, not executed. This is a candidate after
#1407, not another current acceptance campaign or a claim of checker support.
Fixed #1407 source `070078845b87ac5dc826777579099b36338f53fe` is unchanged.

The adopted GoogleSQL UNPIVOT contract rotates corresponding column positions
and excludes a multi-column row only when every rotated value is NULL. Source:
https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unpivot_operator

The complete source in `source.sql` binds `wide` from the declared `@rows`
input in `source-input.json`. The independently authored normal Program uses only
existing object construction, select, unpivot, property, conditional expression,
filter, sort and Named Result declarations. Each input set is an object with
the same role names (`amount`, `note`); component types remain distinct. The
bundle itself is non-NULL even when its fields are NULL, so EXCLUDE NULLS checks
the rotated fields rather than the object receiver. No stringification, casts,
new executor, implicit ordering or Result construction is proposed.

`independent-expectations.json` deliberately retains a partially NULL output
and a duplicate row, and separates the INCLUDE NULLS and empty-input cases.
It fixes the complete ordered type/nullability schema. The control encodes
EXCLUDE NULLS; INCLUDE NULLS would omit only the explicitly shown filter.

Source-inspected boundaries:

- `src/query_syntax/unpivot.mbt` currently starts the IN list by calling
  `self.name()`, and models one value output and one input column per occurrence.
  A parenthesized multi-column set cannot reach the existing single-column path.
  This is source evidence, not an executed parser diagnostic.
- `src/relation_typing/unpivot.mbt` admits checked values of any equal input
  contract; each rotated set can potentially share one closed object contract.
  `Construction::text` passes String values into the existing value builder.
- The selected external checkout was checked at exact
  `d82db99a923a46571f543a13899dc791a7b6f743`.
  `googlesql/analyzer/resolver_query.cc::ResolveUnpivotInClause` compares types
  by corresponding component position, allowing Number and String in different
  positions of one set. `googlesql/reference_impl/unpivot_op.cc` lines 108-130
  excludes a generated row only when every component is NULL. This confirms
  the independent partial-NULL example; it is source inspection, not a vendor
  execution or an ActQL test result.
- The object/property evaluation and exact contract, key evidence, expansion,
  retention and capacity checks remain common-owner responsibilities. Normal
  checker and actual execution of this control are still unverified.

Before implementation, prove the control on the ordinary checker/execution
path using the existing bounded guard. Preserve the exact authored rows/schema.
If any common contract fails, retain the rejection and hand off that boundary;
do not implement equivalent evaluation inside the Frontend. Parser, lowering
and public fixture changes belong in a separate branch after its dependency is
adopted, without modifying the current fixed #1407 worktree.

Numeric PIVOT was also inspected and not selected as a Frontend-only unit:
`src/relation_typing/pivot.mbt::check_pivot` requires a Text pivot column and
retains `Array[String]` values. Accepting numbers just in the parser would not
close the normal common Program path.
