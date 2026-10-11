# Input ranges shadow same-named columns

## Authority and actual counterexamples

The adopted Pipe decision in reviews/2026-09-30-pipe-r1-revised.md requires
selected GoogleSQL name-resolution semantics, rather than preserving an old
Frontend resolver. The fixed GoogleSQL reference is
d82db99a923a46571f543a13899dc791a7b6f743:

- [NameScope::AddNameTarget](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc#L223)
  retains an existing range when a same-scope column is added, and replaces a
  column when a range is added. This is input-scope precedence.
- [CopyNameScopeWithOverridingNames](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/name_scope.cc#L1106)
  builds a separate overriding scope for clause aliases. Do not confuse this
  with adding an ordinary current column next to a surviving input range.
- [ResolvePipeAs](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc#L2062)
  uses UpdateNameListForTableAlias, retaining actual value-table versus ordinary
  row kind. The official query reference documents ORDER output-alias override.

The reviewed inherited statement that a current column/value always wins over
a row range is incorrect for the selected input scope. This correction changes
that owned statement and its previously authored expectations; it is not a
product-output-based adjustment or a new fallback.

At c130cb46f9a451d7bf7327988fea66c43d57efed (#1356):

```sql
SELECT x AS row FROM pair AS x;
FROM pair |> AS x |> SELECT x AS row;
FROM objects |> AS payload |> SELECT (payload).score AS value;
```

For pair row {x:7,y:9}, the independent result is {row:{x:7,y:9}}, a nonnullable
closed object. For objects with score=90 and payload={score:10}, the result is
{value:90}, not the nested payload score. A NULL payload column also leaves
that row's score=90 available. Baseline run-wCPVWg passes only 1/3: the
independent object Program checks; both source obligations fail. Source tests
and fixed reference files are retained under /private/tmp with prefixes
actql-b-range-name-precedence-c130cb46f and actql-b-googlesql-name-scope-d82db99.
This baseline does not claim execution against a Google service.

## Limited implementation and owners

Keep the column-selector resolver for USING, ITEM KEY and other declared
selector positions. Add an expression-specific resolver that recognizes a
bare ordinary range as a row, instead of returning a same-named column slot.
Its value-table kind comes from existing object/scalar receiver metadata, not
spelling, rows or physical-slot heuristics. Snapshot copies retain that kind.
The expression layer then uses its existing bounded object form and property
binder. No evaluator, Source acquisition, Run owner, authorization or storage
format is added.

Normal SQL and scoped Pipe expression/direct-projection paths share this
rule. Parenthesized range properties resolve through the same admitted field
namespace. ORDER uses a separate evaluated output-alias namespace; its receiver
prefix overrides a matching input prefix. Reuse comparisons apply that same
prefix rule, rather than permitting syntax equality to restore a shadowed input.
Surviving ranges retain their immutable slots; SET/DROP matching the range name
remove that range according to the existing contract.

Latest main ae4f29be105e649c621ece7ed3b1584732625639 is merged normally at
7bf39c805e1c73e4b871455b8494df2418f538fc. Its managed-capacity reference and
Effect-current-poll changes are adopted unchanged. Main's new declarations and
CI configuration are retained. No additional history repair is authored here.

## Evidence and honest limits

- Original baseline 1/3 is preserved; current focused tests pass 58/58 on JS,
  including scope, value-table, GROUP/ORDER/analytic callers and the consuming
  Values Run fixture (run-SpWKCM).
- Independent vector/policy tests pass 76/76 in the same bounded invocation.
  Existing grammar/spec/canonical/Workers/Node freshness checks pass read-only.
- Ordinary packed registration includes seven new positive cases and two
  typed refusals. JSON control and source share independently written rows,
  type/nullability and column order. An inherited collision case is corrected
  from scalar output to its actual row object, with unchanged source input.
- Source-form routing stays explicit: FROM-headed Pipe uses aql-text; the
  existing SQL form and JSON machine input remain their declared formats.
- Public execution is recorded only after a normal five-package build from a
  clean fixed SHA and terminal Local/HTTPS receipts. Compiler success and
  registration counts are not public execution evidence.

The full registration is 3,755 authored cases: 2,370 normal, 1,335 refusals,
50 execution-failure cases. Its digest is
13db3a85afe879a8f100a0cec73beb37aec6d79c5710218ea6a2b70809c21e3e.
This unit does not execute that full corpus or all targets.

Grammar syntax and common expression/Program contracts are unchanged. Query
rules change the grammar manifest from
594cac2184f658e9e07993e1846fd0f8177295affaf213a498413757c180fa56 to
f4e99c7113e7860668679e09216235585b48093a6bf04c24e312aed4ad26565c.
The complete prior Values preimages remain in
scripts/fixtures/pre-range-name-precedence-values-identities.json. Independent
sorted JSON rehashing yields current Run
c9084dedac4c58e0c4d57fdd67c56777a36854f561b7918d652bb093d21cf220;
Unit/Program/ResultPlan/value identities remain unchanged. Old Runs retain their
original pins. Existing old-SHA successes are not new-HEAD or standards-conformance
successes.

The JOIN whole-row prototype is preserved separately on
audit/frontend-joined-row-range at 2fff853ea04ca01aca8179e02f842eeda2c36573:
its JSON/source/caller tests pass 17/17, but public execution remains unverified.
Adopt this precedence correction before completing that unit. Broader whole-row
expression reuse, specialized contexts and complete SQL STRUCT semantics need
separate evidence; this report does not certify them or redefine their target
semantics. The Frontend goal remains active.
