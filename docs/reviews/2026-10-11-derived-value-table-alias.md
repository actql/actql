# Derived aliases preserve the actual output table kind

## Fixed reference and actual baseline

The fixed [GoogleSQL UpdateNameListForTableAlias](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc#L1174)
renames the receiver of a single value table while keeping its value-table kind.
For an ordinary row it flattens prior ranges and installs a range over the
current output. ResolveTableSubquery applies this to an explicit alias. This
matches the adopted existing Pipe AS behavior, not a new table/STRUCT algebra.
See the [official value-table profile](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#value_tables).

At fixed parent #1353 bcd0fb5ce617be52d2efb6d3aab0d2bfba16d157:

```sql
SELECT chosen AS value
FROM (FROM UNNEST([1,2]) AS element) AS chosen
```

Independent rows are [{value:1},{value:2}], number/nonnullable, column value.
The independently authored existing Values Program already checks. Baseline
run-Owv3qq is 1/2: the source lowering unwrap fails. Refined run-z9tZHy is 1/2
and identifies Expression.UnknownReference. No wrong public rows or conversion
to an object were executed/proved by those probes. Keep exact source/Program,
rows and type at /private/tmp/actql-b-derived-value-table-alias-independent-control.json
and baseline test at /private/tmp/actql-b-derived-value-table-alias-bcd0fb5ce-baseline.mbt.

## Connection and ownership

When a named derived query still has a row/value scope, append the existing AS
operation to that query's AST and retain the resulting private scope. The
outer table consumes that exact output rather than trying to reconstruct a
value table from projected row fields. AS dispatch uses the actual checked
output kind: a single scalar remains a scalar, an object remains its original
whole nullable object, an offset/additional-column table is an ordinary row.
It replaces old receiver names before retention. Projected SELECT/set outputs
continue using the normal projected-producer path. No guessed alias, data
sampling, string rewriting, executor, storage wire or new type system is added.

Ordinary SET range snapshots still reference the current replacement after a
new alias; old names remain inaccessible. The source NamePart is retained in
the existing Alias operation. Its placement changes internal AST shape only
where scope must survive; closed outputs keep the existing outer source alias.
No CTE capture/predicate, physical planner/provider, remote protocol or common
Owner file is changed.

## Independent checks and local failure classification

- run-gaAq2p: 14/15. Product scalar/alias/PIVOT caller checks pass; one newly
  introduced parent AST assertion expected the source alias to remain outside
  the now-required scope binding. Correct that assertion to verify the actual
  inner AS and retain the ordinary projected alias contrast.
- run-gOVrOR: 19/20. The new bare ordinary row expression (`SELECT chosen` with
  OFFSET) is also not yet connected. Preserve that separate B/frontend gap at
  /private/tmp/actql-b-ordinary-row-receiver-followup.json. Qualified columns and
  star are the existing ordinary-row contrast; this unit does not claim a
  whole-row STRUCT constructor or silently mark that separate gap fixed.
- run-f5kX2o: 20/20 for scalar/object/NULL receiver kind, old-name/property/star
  refusals, offset row columns/star and existing UNNEST/optional-alias callers.
- run-IM9OgC: 6/6 includes full independent seed/ARRAY/UNNEST/projection Program
  equivalence. Keep /private/tmp/actql-b-derived-value-table-alias-independent-program.json.
- run-kISAwm: selected query_syntax public interface compilation and existing
  normative generators. JS/Wasm/native interfaces, unsupported wasm-gc skipped.
- run-iIhfMc: current/historical identity and authored fixture/accounting 70/70.
  Whole-corpus accounting is not unrelated runtime execution.

The public composition cohort adds matched scalar and object JSON/source controls,
NULL/duplicate scalar values, quoted aliases, empty/NULL arrays, whole nullable
objects, property nullability, object star, empty object input and offset row
columns/star. Internal id stays nonnullable inside each non-NULL object; the
outside property id is nullable because its receiver can be NULL. Refuse removed
scalar receiver, scalar star, invalid scalar property and duplicate range names
before Run admission/provider I/O. Existing consumer checks Named rows/describe,
full type/column order, repeated request/attach/reread and no additional I/O.

## Pins and remaining gate

Syntax grammar digest remains unchanged. Source rules change grammar self CID
from baaa80c2d0c6053f42eb44fc476fd99ec29e42fcfd2035233c6f8e2c12dea26b to
683c36d56e7d45ac12cb3cd72f361b6ebe2656ce4b2d05b3ddc4be3270d4f0fd.
Values Unit/ResultPlan/Program remain unchanged. Freeze the full old closure in
scripts/fixtures/pre-derived-value-table-alias-values-identities.json; old Run
b82a41c233577845b9eaf4c491671994c70305a4a7c707f6fc4f3354a2362d8b retains
its old rules. Current expectation a24a0a7291b21746a3fc9d6d642c2be5d1aabf9d9166fa6230e5383e6254f654
comes from independent preimages and sorted-JSON hashing. Keep current full
preimages and derivation script at /private/tmp/actql-b-derived-value-table-alias-current-run-preimages.json
and /private/tmp/actql-b-derived-value-table-alias-independent-vectors.mjs.

Stacked dependency #1353 (audit/frontend-optional-derived-alias), fixed parent
bcd0fb5ce617be52d2efb6d3aab0d2bfba16d157. Keep base until it reaches main;
final target is main, no merge into the dependency branch. Normal clean-HEAD
five-package producer and existing --query-composition-only Local/HTTPS remain
pending at document creation: full selected 54 normal/28 refusals, including
11 new normal/four exact typed refusals. Record exact SHA, actual digests,
terminal receipt and Named Result evidence in the PR.

No full Core/all-target runtime/proof/performance/all-packed campaign is claimed.
Shared no-op JSON task-emission issue #1350 and the separately observed ordinary
whole-row expression remain open completion obligations. Local success does not
establish public execution or CI. No merge or new unsupported language law.

Final preparation run-wSjkFQ checks the consuming Values Run identity 2/2 and
read-only compilation manifest, document metadata, spec family, canonical,
Workers and Node freshness. Pre-submission main remains eefdda1a85c4e033d6dcefcc774095949cc97262;
parent #1353 remains open at bcd0fb5ce617be52d2efb6d3aab0d2bfba16d157.

## First public gate: independent object schema default omission

Fixed initial source 6f6056d06c85142d9c5130f51ced07650c6e4f71 normally packs all
five packages and passes actual digests. Guard run-lK13qT reaches the five new
scalar cases successfully on both transports; it fails at the object JSON
control's describe comparison. The normalized closed-object contract includes
additional_properties=false, which the newly authored expected contract omitted.
No source-generated object case/later/refusal/inventory success is claimed for
this failed run. Original receipt/logs retained at
/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-2WIyK5.

Declare the existing closed-object constraint explicitly in the hand-authored
contract used by both parameter declarations and expected describe. The same
existing value-contract normalization default applies; do not remove closure
checking or infer a type from rows. Preserve object NULL/field NULL, inside id
nonnullable/outside property nullable, all rows, column order and case coverage.
This is a new expected-schema default omission, not a change to product meaning.
