# Multi-column UNPIVOT: prepared connection boundaries

Status: authored preparation on `b7fa92700cced13ad296b7920e4bb63f8ab48ced`.
No tests, compilation, generator or public consumer were executed. The source
patch is incomplete and is not installed in the working source. This is a
separate future unit; it adds no completion condition to String-label PR #1407.

| Boundary | Source evidence | Next obligation |
|---|---|---|
| Parser | `query_syntax/unpivot.mbt` reads one output name and one input name per occurrence | Retain positional tuples, enforce arity, deep-copy AST lists |
| Name scope | `query_program/compile.mbt` checks selected names against current visible/private columns | Apply the same existing checks to every tuple component |
| Object construction | `expression_typing/signatures.mbt`, `object` branch, creates a non-NULL Product whose children retain their contracts | Use evaluated input fields; do not manufacture component non-nullability |
| Common expansion | `relation_typing/unpivot.mbt::check_unpivot` compares recursive input contracts | Prove the independently authored equal-object control in the normal checker first |
| Nullability | `value_contract/equality_steps.mbt` compares nullable bits recursively | Preserve the existing exact common-contract requirement; record differing-nullability coverage as a common-profile gap, without casts or fabricated evidence |
| EXCLUDE NULLS | A constructed object is non-NULL even if every component is NULL | Filter the emitted component values with OR of IS NOT NULL; testing the bundle receiver is incorrect |
| Output projection | Generated bundle/name slots are internal | Expose kept columns, positional value columns, then name column; hide every internal slot |
| Result/order | Control contains explicit sort and explicit Named Result | Do not add either implicitly |

The selected GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`.
`ResolveUnpivotInClause` compares corresponding value positions;
`GetLabelForUnpivotInColumnList` joins omitted tuple labels with `_`;
`reference_impl/unpivot_op.cc` excludes a row only when all components are NULL.
These are inspected source rules, not a vendor execution result.

The independent input deliberately has `(5,NULL)` and `(NULL,'kept')`, plus
an identical duplicate input and an all-NULL tuple. Expected EXCLUDE/INCLUDE
outputs have four/six rows respectively; an empty input has the same four
ordered column contracts. Those expectations were authored independently and
must remain separate from actual rows and schema receipts.

Prepared tests are outside `src`; they are not registered CI coverage.
`common-control.prepared_test.mbt` is intended for `query_program` using its
existing test helpers. `parser.prepared_test.mbt` is intended for `query_syntax`
after the grouped AST is implemented. The incomplete patch references a missing
multi-column lowerer and requires generated API/grammar metadata and independent
identity-vector updates. Do not publish it as a completed implementation.

#1407 author 070, coordinator integration 82f, integration 956, and any later
multi-column source/package cohort remain different evidence identities. The
Root-owned producer/public campaign must not be joined or restarted by B.
