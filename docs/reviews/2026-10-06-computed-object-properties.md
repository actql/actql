# Computed typed-object receivers in query text

This unit connects a missing Frontend input path to the existing common typed
property expression. It does not change evaluation, value identity, storage,
Model capture, cancellation, Effect ownership or Host ceilings.

## Existing contract and counterexample

The [common typed-access contract](../spec/language.md#typed-access) already
admits property access on any complete typed-object expression, including a
COALESCE receiver. NULL propagation and absent-property rejection are checker
responsibilities. The selected [GoogleSQL field-access operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator)
also accepts an expression receiver with highest-precedence field access.
This unit connects closed typed objects; it does not claim JSON field access,
array subscripts or the whole external type profile.

At main `64046e37a1cadb2148edeab7cbf85b96d125b518`, an independently authored
Values/derive/property/coalesce/select/sort Program passes the normal checker,
but its equivalent source is rejected by the query parser:

```sql
SELECT id, COALESCE(payload, other).score AS score
FROM objects ORDER BY id
```

The failing pre-change test is `computed object properties match an independent
checked Program`, recorded in local guard `run-GZaG4g`: 0/1. This establishes
a parser gap, not an executed public-Run failure. The initial post-change
comparison `run-RN7E1G` exposed an author fixture's private-slot layout error:
the second selected expression uses existing slot `aql_query_expr_1`, followed
by the public `score` mapping. That expectation was corrected using the
existing projection-ordinal rule; values, predicate, order and types did not
change. The first JOIN test also named an unregistered `orders` input instead
of its declared `pair` input; only that test name and key reference changed.

## Connection and preserved boundaries

- Parse postfix properties after calls, parameters, groups and CASE. Ordinary
  qualified paths retain the existing Reference/prefix resolution rules.
- Emit the existing `property` expression with its authored name and resolved
  receiver. Infer no type or existence evidence in the Frontend.
- Traverse receiver references when collecting JOIN inputs and deciding whether
  a SELECT slot may be reused by ORDER. Textual equality alone is insufficient:
  output aliases and qualified input receivers retain their distinct meaning.
- Derive implicit output names from the final static member. Duplicate outputs
  remain a refusal. Pipe range snapshots and removed ranges remain distinct.
- Apply the existing node/work ceilings and actual AST depth to postfix chains.
  Computing child depth also bounds left-deep source trees that previously
  escaped the recursive Pratt-frame depth check; no ceiling is raised.

The source AST adds `Property`; its compiler-generated package interface is
regenerated. No serialized Program grammar, common contract body or canonical
identity pin changes. Existing expression contracts already encode this form.

## Independent acceptance obligations

`scripts/fixtures/computed-object-property-source-input.mjs` contains a complete
JSON control and source cases, with authored rows and ordered column contracts.
The real Source contains unsorted rows, duplicate id=2 and an excluded id=0.
COALESCE falls back for a NULL receiver, but does not replace a NULL member of
a non-NULL object. Result.describe must retain that nullable member contract,
nested closed-object contracts and declared column order, including empty input.

The alias-collision source selects the original computed score and replaces
`payload` with `other`. ORDER on the computed unqualified receiver must produce
ids `1,3,4,2,2`; explicit `objects.payload` must produce `2,2,3,1,4`.
The shared-source self-JOIN retains four id=2 pairs. CASE, quoted member names,
typed parameters and Pipe SET snapshots have separate controls. Lazy CASE
must not demand its failing branch; a demanded receiver failure must publish
no Result. Missing properties, scalar receivers, removed ranges, sibling alias
access and duplicate leaf names must reject before Run admission and Source I/O.

At clean revision `68c145b06cee27898527fc0bb060d6826be13e70`, guard
`run-m68nsk` passed JS syntax 92/92, expression lowering 14/14, property
callers 75/75 and Node fixtures 11/11. Normal five-package prepack succeeded.
Packed Local passed the first eight controls, then rejected the lazy CASE
fixture before Run admission. The normal built bridge retained a parameter
declaration rejection: those two CASE fixtures inherited unrelated declarations
from the DATA corpus. Only their authored declaration/value sets were narrowed
to the referenced names. CASE branches, types, values, source rows, expected
rows, ordering and installed limits did not change. This initial Local result
does not establish HTTPS or acceptance at a later revision.

The corpus is registered in the ordinary packed driver and has a focused
`--computed-object-property-only` selection. Existing public acceptance checks
Named Result rows, descriptions, attach, same-request resubmission and lookup,
and ensures no additional Source acquisition. Runtime support and CI are
reported for their actual revision separately from this authored test plan.
