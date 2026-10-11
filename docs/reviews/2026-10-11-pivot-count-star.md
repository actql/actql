# PIVOT COUNT(*) through the existing Count Owner

## Selected meaning and matched counterexample

The [GoogleSQL PIVOT rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator)
permit COUNT(*) and group unaggregated input columns other than the pivot axis.
COUNT(*) references no user value column, so every current non-axis column is
an implicit key. It counts matching rows even when those columns contain NULL.
This closes a documented source gap; it does not change the common Count law or
claim complete GoogleSQL PIVOT support.

At main `e686fca056b8b49be089105cfd9b95a071bc470d`, the complete source below
fails in parsing with `Expected identifier`:

```aql
(SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis
 UNION ALL SELECT CAST(NULL AS FLOAT64),'A'
 UNION ALL SELECT 1,'A')
|> PIVOT(COUNT(*) FOR axis IN('A'))
|> ORDER BY n NULLS LAST
```

Independent expected rows are (n=1,A=1),(n=NULL,A=2). The ordinary JSON control
uses matched rows, derives row_witness={literal:1}, pivots with index=[n],
value=row_witness, axis=axis and count, then explicitly selects/sorts n/A.
It passes the existing checker; `run-EjBt4p` is 1/2, with only source failing.
Replacing star by COUNT(n) is not equivalent: it consumes n and ignores its
NULLs, yielding the separate one-column A=1 control.

Preserved baseline:
`/private/tmp/actql-b-pivot-count-star-e686fca05-baseline.mbt`.
Independent complete Program, source, input and rows:
`/private/tmp/actql-b-pivot-count-star-independent-control.json`.
No wrong public execution is claimed from the parser failure.

## Frontend connection

PivotClause records an explicit count_star flag; ordinary column paths retain
their old meaning. Only COUNT accepts star. Lowering derives one private
nonnullable literal-expression witness per row and passes its evaluated field
to the existing pivot Count operation. The witness is not a current user column,
index, output field or expression receiver. Current non-axis columns retain
their implicit grouping role. Allocate against physical/current/bucket names,
so a legitimate name resembling the private prefix remains usable.

The first implementation probe `run-dWLKNr` is 1/2: the newly emitted witness
was a raw JSON atom rather than the existing expression shape {literal:1},
causing LocalConstructionFailure.Source. Correcting that construction yields
`run-pOMovX`, 2/2. No alternate encoder, execution Owner, aggregate approximation,
capacity exemption or consumer-side Program patch is introduced.

Scope remains one String-axis aggregate with static String buckets. This unit
does not add multiple aggregates, non-String axes, NULL buckets, DISTINCT
aggregate calls or the standard FROM-suffix form. Non-COUNT star is explicitly
refused. Empty global input yields zero per declared COUNT bucket; keyed empty
input has no rows. The existing common checker retains all grouping/type/NULL
and capacity responsibilities.

## API, grammar pins and independent identity vectors

The query grammar/rules change compiler grammar identity. Generate the public
syntax interface with the pinned compiler (`run-CC7YMh`) and check the selected
query_syntax package on its three supported targets (`run-KIZa5O`). wasm-gc is
not a supported package target and is skipped; no full API/Core campaign is
claimed. Generated mbti adds count_star Bool.

Use existing compilation-manifests, document-metadata, family and canonical
generators. Their read-only checks pass: ten documents, 1,412 requirements and
502 canonical identities. Workers then Node fixture read-only freshness checks
pass without generated changes. No freshness check is disabled or generated
file manually patched.

Grammar self CID changes from
`sha256:81c194e574cb92623e23bf9e81075a718e14111cdfcb0308507c4f6d0b6b0586`
to `sha256:179bf543f875423582fe4ae0d5154e80086c97feb120f84d530a8e3907bdc6b9`.
Values Unit, ResultPlan and Program identities are unchanged; the grammar-bound
invocation template, executable, compiled Plan and Run change. Preserve the
complete prior grammar/dependencies/Program/Run preimages in
`scripts/fixtures/pre-pivot-count-star-values-identities.json`. Its old Run
`sha256:0bf6c0cf5627553679b5bdf942fdd14f8f1f94f1d424d905b11f848339851094`
remains valid only under that recorded closure. New Run expectation is
`sha256:79bac43e6311950bd8ee195f40895acdb6835985e4c71624b329caeefc77880c`,
derived with independent hand-assembled inputs and sorted-JSON hashing, not
compiler/issuer/runtime output. Current full preimages are retained at
`/private/tmp/actql-b-pivot-count-star-current-run-preimages.json`.
No saved Run is silently interpreted under new pins.

## Limited checks and public obligations

`run-vthf4k` passes 19/19 focused syntax/lowering/PIVOT/helper tests.
Consuming Values materials `run-aTNZkK` passes 2/2. Initial targeted Node
`run-vbKsic` is 35/39, exposing four stale current identity/manifest fixtures.
After independent vectors and generated canonical fixtures are updated,
`run-YZfelu` passes vector 21/21 and manifest 6/6; its remaining old grammar-chain
assertion is corrected while preserving the predecessor, and `run-FyMhIt`
passes 1/1. Frontend profile 9/9 and spec-import 3/3 passed earlier and were not
repeated only for a new aggregate total. Pinned formatting and diff check pass.

Nine normal/five refusal additions use the same existing normal and
--pipe-pivot-only public consumer. They cover matched JSON/text NULL rows,
ordinary column-count contrast, empty global/keyed output, legitimate private
names, prefix/bucket order, range axis and DATA copying. Refusals cover non-COUNT
star, missing axis, private witness, displaced range and parameter bucket.
Existing Named Result/describe rows/types/nullability/column-order/hidden-name,
request reuse and zero admission/provider I/O checks are retained.
`run-BoQS3c` passes 40/40 fixture/inventory tests (4/36).

Selected registration is 40 per transport: 24 normal, 16 refusals. Full inventory
is 3,675: 2,314 normal, 1,311 refusals, 50 runtime failures; digest
`e0da0ec52a03a176e43aa408f6869d6f39af5fbe827d59ab351f1bca72269296`.
Registration, type checking and interface generation are not public execution.

At this commit normal exact clean-HEAD five-package Local/HTTPS acceptance is
pending. Full Core, all-target execution, full packed corpus and CI remain
unverified. This independent branch starts at the stated main; no unmerged
parent dependency. Final destination main. The broader frontend goal remains
incomplete.
