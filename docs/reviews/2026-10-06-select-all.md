# Explicit SELECT ALL: ordinary duplicate-preserving projection

The baseline is main `dfff4587118b077e76e6da8153e2827a9839e14b`.
SQL and Pipe SELECT already lower an omitted quantifier to the ordinary
projection, but reject an explicit ALL token before producing a Program.
This change consumes that optional token and retains `Select(_, false)`.
It does not change common projection, identity, ordering, capacity or execution.

## Reference and independent expectations

[GoogleSQL SELECT ALL](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_all)
preserves duplicates and is the default SELECT behavior. The pinned reference
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`,
`googlesql/parser/googlesql.tm::pipe_select`, uses the same `select_clause`
and `opt_all_or_distinct` as ordinary SELECT. This is selected reference
language coverage, not a live differential test or universal deployment claim.

The complete expected Program in `src/query_program/select_all_test.mbt` is
authored independently. It preserves the predicate, select list, ascending
NULLS FIRST order, count 2 and offset 1, with no distinct step. Separate
checker cases cover source-free SELECT, star, CTE, subquery, UNION ALL,
aggregate output, repeated Pipe projections and quoted ALL identifiers.
Aggregate-call modifiers are outside this connection.

The public fixtures use amounts `[2,1,1,null,-100]` and exclude the last row
using `id > 0`. Ordered ordinary output is `[null,1,1,2]`; count 3/offset 1
returns `[1,1,2]`. DISTINCT instead returns `[null,1,2]`. A separately authored
JSON Program is a control, and an alias collision verifies output alias order
and the declared nullable/non-nullable column sequence. Empty input retains
the nullable numeric schema. Combined/repeated quantifiers and a dropped Pipe
column are refusal cases. Existing acceptance checks Named Result rows,
`describe()` contracts, one acquisition, rereading/reattaching and same-request
resubmission without another acquisition. Refusals check zero Run admission
and zero provider I/O.

## Verification and identity

The pre-repair single Program test executed and failed at parsing ALL:
`_build/local-checks/attempts/run-70UlQp` (0/1). The failed process is terminal.
An earlier helper syntax error did not execute tests and is not this evidence.

After repair, focused JS tests passed 28/28 and targeted Node tests passed
11/11 under `_build/local-checks/attempts/run-3qBi46`. The command selections
are the three SELECT ALL files, query parser callers, source-free lowering,
the fixed Values Run vector, and the independent grammar/Run/manifest/packed
registration Node files. `compilation-manifests.mjs`,
`update-document-metadata.mjs`, `check-actql-spec-family.mjs` and
`check-canonical-json.mjs` passed read-only; 370 canonical identities match.
Unrelated formatter-only output was verified against formatting HEAD, backed
up and removed. No unrelated product changes are included.

The grammar manifest changes from
`sha256:33b5a9ea6214ae40f224b7f105632b933b6394dbd6d3f337cbdae20c9c1608ed`
to `sha256:83dada5a89e2b221799c9b5c8aadc712aac474c5bb7ce70f2516c17b628d25c6`.
The unchanged Values fixture's Run CID changes from
`sha256:cd459a94b139de3909f0b0376bdfb42fe2885fe9d7959fe67d2d0bd75ce18176`
to `sha256:8fd97e9490289353f6048215faf2a9b50226b69caff3a217b572c10d32cdb8ec`
because its compilation identity includes the grammar. The independent
preimage assembler supplies this vector; no product issuer output is copied.
Historical grammar and Run vectors remain intact. The common expression law,
Program schema, operation registry, Unit and Result Plan are unchanged.

The fixtures are registered in the ordinary packed campaign. Its optional
`--select-all-only` selection runs the same SDK/standard Host boundary over
Embedded Local and HTTPS and excludes unrelated campaigns. Exact source SHA,
normal five-package manifest/digests, receipt and execution results belong in
the PR after that run. The focused checks above are pre-commit implementation
evidence, not exact committed-SHA packed evidence or CI success.

Full Core, Wasm/native execution, all packed cases and performance are not
locally re-run. SELECT ALL support does not complete the entire Frontend.
REPLACE has a separate public-function and common execution-lowering gap;
inspection found `ExpressionNotImplemented` and no repair is included here.
