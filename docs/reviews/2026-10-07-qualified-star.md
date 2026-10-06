# Qualified Relation star connection

Owner: B. Base: `b98a50ff763d1367e344fdfa8aea380ec8749132`.

## Counterexample and selected semantics

The independently authored ordinary Program in
`src/query_program/qualified_star_test.mbt` projects `id,amount` from Values
and orders by `id`. The corresponding source:

```sql
SELECT o.* EXCEPT (customer_id, status)
FROM orders AS o
ORDER BY id
```

failed in the parser on the base (0/1, `run-08m07n` /
`focused-test-xk9zs4`). No public pre-fix execution was attempted.

The selected [GoogleSQL SELECT expression.* clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
permits a table alias and preserves its field order. This unit connects that
Relation-range case, including EXCEPT, through SQL/Pipe/CTE/JOIN/GROUP to the
existing Program. STRUCT-valued/arbitrary expression receivers, unqualified
JOIN star and direct Graph star retain explicit coverage gaps; they are not
redefined as Relation ranges or a complete-language restriction.

## Implementation boundary

The parser retains a named receiver as an ordinary Reference AST in the star
projection's expression field. Quotation and exact token positions are retained;
there is no rendered expression text, JSON selector injection or reparsing.
Lookahead and AST creation obey existing query work/expression-node bounds.

Expansion uses the existing named range and physical-slot scope. EXCEPT applies
to that range only. A missing receiver is refused even when the projection could
otherwise look like an identity star. Single JOINs requiring range expansion
use the existing shared-scope assembler; its ceilings, ports and joined NULL
contracts still come from the common Program/checker. GROUP ordinals count the
expanded list and validate every selected input value as a grouped value.

SELECT materialization ends its input range scope. A deferred query ORDER keeps
the required SELECT input snapshot until its physical projection is emitted;
afterward the old range is unavailable. SET/DROP/RENAME still retain an earlier
range's original value slots, and AS still replaces ranges with the current row.
There is no Graph compatibility layer, execution owner or invented type/order
evidence in this connection.

## Independent acceptance and identity

The fixed public fixture contains ten successes and eight preparation refusals.
It includes an authored JSON control, a complete range, hidden-input ordering,
quoted dot-containing aliases, the original positive values after SET negates
the current columns, replacement AS, nullable LEFT JOIN output, GROUP ordinal,
CTE scope and typed empty output. Independent rows include NULL and duplicate
Source rows. The ordinary harness verifies rows, complete schema/column order,
stream completion, one acquisition session and same-request/re-read identity.
Refusals require zero Run admission/provider I/O and cover missing/displaced
ranges (including ambiguous receiver aliases), post-projection access, ungrouped columns, unknown exclusions and
currently unsupported multi-part field receivers.

The grammar and query rules update the grammar-manifest self CID from
`sha256:3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a`
to `sha256:1e69c47a6aba9a6bc728c10d4edbeeb1e72964e0504d82d7f54fde65293de06a`.
The independent normative-preimage test retains the predecessor. Current complete
document imports, normative document references and canonical vectors were
updated by the existing metadata generators. Old pins/Runs are not relabeled.
The Program schema, expression contract and execution algebra are unchanged.

## Verification checkpoint

After implementation: focused JS passed 25/25 (`run-mxu8J0`), including parser,
star exclusions, GROUP ordinals, single-JOIN grouping and alias ORDER callers.
Public fixture/selector Node checks passed 11/11 (`run-64KKvS`). Independent
manifest checks passed 7/7 (`run-j4nxdZ`) after their metadata update.
Workers and Node fixture generators passed their read-only freshness checks;
they required no fixture source change for this parser/lowerer update.

The initial ten-success/seven-refusal corpus passed both transports from
`1d63df05c4ad939265cdb2fcfb2726dac15ae6cf` (`public-query-evidence-JYmN1c`).
The final ambiguity caller checks passed 5/5 (`run-OrskVU`). Its duplicate-alias
case is refused by the existing shared JOIN scope as `AmbiguousRelation` before
star expansion. Source-fixture Node checks passed 2/2 (`run-kFMg2t`).

Normal five-package acceptance from
`e8fa67edbd983eddcae17466168d900f2363dbe1` passed all ten successes and eight
preparation refusals in Embedded Local and HTTPS. Every authored case remains
in the ordinary corpus. The command was:

```sh
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-qualified-star-final-20261007-pack node scripts/test-packed-public-query.mjs --qualified-star-only
```

The private installation used the existing B download cache in offline mode.
It was removed automatically after preserving evidence under
`worktrees/.codex-scratch/public-query-evidence-74Vu88`. The producer manifest
and normal tarballs remain at the command's package path. The producer's clean
build-input and digest checks were not bypassed; the evidence recorder's
`dirty: true` reflects unrelated, preserved untracked `review-artifacts/`.

| Package | SHA-256 |
|---|---|
| client-wire | `27066b9ab7a1f4a3f15dec782b17ccdff5f04aca45ca2b3bf1496bb6bca329c3` |
| sdk | `d72e590dca3666fa0d2444492b2ec4559b056008a5b8575d4bc4ebe24159baa9` |
| run-host-core | `9fed7518e01544413254588b486f417e16692c98fb3db8b731d3230927da0948` |
| local-node | `1d6c37c23bfd6423ae748d32ea2f31c862d9f722e00f86ce6fe0d65a69e1a279` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

This report is a later documentation change, not another tested distribution.
Submitted-SHA CI and content review remain unverified.
Full Core, all targets, complete packed/Planner, performance and Cloud suites
are not part of the local checkpoint.

## Separate retained Planner fixture mismatch

The previous acceptance's unrelated Planner rejection was narrowed using
`review-artifacts/b-planner-requirement-20261007/probe.mjs` on source
`8d33048e9355c8564571d62f81cc466cc6e8283e` with the retained standard runtime
(package source `58c3db8aeabe77c60c479e5dee2d3c34cb012a94`). The original JSON
Program passes ordinary preparation. Its current normal requirement CID is
`sha256:184df559555d7c498749f497da6837ad5d30035784eb670181e7ad0a81490fe9`,
versus the fixture's `sha256:1eaca4154c1d97c24db2bbff2fd875ee9ebdcc929d7e103ad818129ebc050d48`.
The unsupported-native-predicate variant also differs:
`sha256:d4f6556b7c50ae0042cd7c47485600a16c1a6a02684a85b08e8f01cfcbf511e5`
versus `sha256:84feddd46622948d1375d8f3f0ac80e511aa83fa6f29914ca1878f95740b3fa9`.

The installed acquisition selector explicitly treats a foreign requirement CID
as missing estimate evidence before provider I/O. This establishes stale fixture
conditions consistent with the earlier public 422; it does not establish the
sole cause by a repaired public Planner run. No estimate, expectation, threshold
or Planner implementation was changed here. A separately owned fixture repair
must derive and pin the current requirement preimages, keep the foreign-evidence
negative case, and rerun the original 22 public cases. This is not a frontend
lowering refusal and does not block the independently verified star corpus.
