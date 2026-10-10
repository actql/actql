# UNPIVOT output-name collisions and positional scope

## Requirement and fixed baseline

The selected [GoogleSQL UNPIVOT rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unpivot_operator)
allow a generated value/name column to reuse a retained input name. SELECT star
may retain duplicate result names; a named reference remains ambiguous. This
also follows the adopted profile's retained-column order and positional set
occurrence rules. The official clause was consulted on 2026-10-11 JST. The
repository's fixed GoogleSQL URL could not be retrieved during this check;
no reference execution or whole-standard conformance is claimed.

Baseline `e01d92d5f87c066f6c9086b2386b24c4cf0f0db9` normally merges parent
#1328 (`7b63489b93c791f4a887f8e9371c8da3a601608a`) and main
`40033a854b4eb8e30f2f5db734a181051f5d1868`. Resolve against the actual Git
parents, not a subsequently moving origin/main ref. Diff against that main
parent retains only #1328's eight files. Six overlapping files were resolved by
retaining both UNNEST/UNPIVOT code and independently authored fixtures; the
data-only inventory is rebuilt from registration. Main CI settings, new common
contracts, generated pins and historical vectors are retained. Integration
guards `run-eoqx6h` JS 13/13 and `run-kuKN3C` Node 57/57 pass. These checks
are not new-SHA public acceptance.

This source fails with DuplicateOutput:

```aql
SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d
UNION ALL (
  FROM t |> SELECT x AS kept,y AS extra,-y
  |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept))
  |> SELECT *
)
ORDER BY a,b,c,d
```

For (x,y)=(1,10),(2,20), independent rows are
(0,0,0,'anchor'),(10,-10,1,'kept'),(20,-20,2,'kept'). The retained extra and
the newly expanded extra deliberately have different values. A name-column
collision also fails: retain 'user' AS extra, then UNPIVOT value FOR extra.
Neither value may overwrite or replace the other.

The complete independent JSON control retains extra/neg, unpivots kept into a
fresh expanded slot, selects a/b/c/d, appends the anchor and sorts. It passes
the checker. `run-Gabrhm` is 1/3: both source forms fail specifically with
DuplicateOutput, while JSON passes. Preserved tests:
`/private/tmp/actql-b-unpivot-name-collision-e01d92d5f-baseline.mbt`.
Independent Program, input, expected rows and reference readout:
`/private/tmp/actql-b-positional-unpivot-name-collision-next-candidate.json`.
This is compiler/checker evidence, not a demonstrated wrong published Run.

## Repair and regression separation

Reuse `privatize_positional_duplicate_columns` after UNPIVOT creates its fresh
scope. Copy separately evaluated occurrences into distinct physical fields,
record their authored names and retain ordinal export. The common UNPIVOT
operation still constructs labels and expanded values. No expression is
reevaluated; bare/qualified references and SET/RENAME targets remain ambiguous.

The basic repair passes 3/3 (`run-rDfJ9f`). Expanded `run-EOuxY4` is 31/32:
a positive loop stops on its first qualified-star query. Splitting that loop
without changing sources or expectations yields 7/8 (`run-Ghdd99`), proving
that DISTINCT, DROP and ordinal ORDER pass separately while the row-range
star still loses the earlier positional projection role.

Permit positional role discovery through a qualified star of an explicit
whole-row AS range, traversing existing scope-preserving operations. Stop at
displacement/projection barriers. The ordinary lowerer still resolves the actual
star, fields and ranges; this does not infer object fields or fabricate presence.
After that connection, `run-amnuA2` passes 8/8. Add an immutable range star
after SET and exact displaced/projected-away-range refusals.

Final focused JS `run-oYPC7a` passes 51/51 including ordinary UNPIVOT,
qualified stars and positional RENAME/DROP/DISTINCT/tail callers. The immediately
preceding command `run-kLZBZF` used a nonexistent test filename and executed no
tests; it is a command-selection failure, not a product failure or a pass.
The corrected command preserves the bounded nonzero-test wrapper.
Targeted Node `run-9ULRf9` passes 58/58 (22 fixture, 36 inventory).
Pinned formatting and `git diff --check` pass. Final guards are complete,
exit zero and release locks.

## Independent public obligations and remaining evidence

Nine normal cases cover the JSON control, value/name collisions, qualified star,
an immutable star after current SET, complete-row DISTINCT, DROP of all matching
authored occurrences, nullable retained values and typed empty output. Six
preparation refusals cover bare/qualified ambiguity, SET/RENAME targets,
displaced range and private duplicate names. The existing consumer checks
Named Result values/multiplicity, describe types/nullability/column order,
explicit order, internal-column absence, one Source acquisition, same-request
Run reuse and zero admission/provider I/O for preparation refusals.

The public Source's amount contract is nullable, so the independent public JSON
control declares y nullable. Particular non-NULL rows do not narrow that type.
Source, Program, values and schemas are authored independently, not generated
from the compiler or patched for execution.

Full registered inventory is 3,644: 2,296 normal, 1,300 refusals, 48 execution
failures; digest
`289455febd9b9b1f606bc757630514a5b3f8a6d8f80f362dcbe3436f28e59602`.
Selected registration is 317 per transport: 191 normal and 126 refusals.
Registration is not execution evidence.

This unit depends on unmerged #1328. Maintain that parent until it reaches main;
final destination is main, never the dependency branch. This repair changes no
common contract/owner/capacity rule; incoming main contract changes above are
separate. At this commit exact clean-HEAD normal five-package packed Local/HTTPS
execution is pending. Full Core, Wasm/native, the full packed corpus and CI
remain unverified. The broader frontend goal remains incomplete.
