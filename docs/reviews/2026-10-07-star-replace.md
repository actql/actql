# SELECT star REPLACE connection

Owner: B. Parent: qualified range star PR #673, fixed head
`5ea9f0530de89bffee201a9253983a82cf31ba3a`, on main
`b98a50ff763d1367e344fdfa8aea380ec8749132`. Keep that unmerged dependency;
merge destination is main after the parent lands.

## Counterexample and contract

The complete independent Program in `star_replace_test.mbt` passes the normal
checker and atomically projects `x <- y, y <- x`, followed by ORDER BY the
new x. The corresponding source failed in the parser (0/1, `run-i84XMw`):

```sql
SELECT * REPLACE (y AS x, x AS y) FROM t ORDER BY x
```

For inputs `[{x:1,y:20},{x:2,y:10}]`, independent expected rows are
`[{x:10,y:2},{x:20,y:1}]`. Sequential updates or input-x ordering give different
results. This implements the adopted
[GoogleSQL star REPLACE](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_replace)
clause, distinct from STRING REPLACE.

Targets resolve within the retained star after EXCEPT. Names/column positions
stay fixed, values and their checked types/nullability can change, and all
expressions see one SELECT input snapshot. Duplicate/missing/excluded targets
and displaced ranges are refused. ORDER aliases use evaluated output slots;
qualified inputs keep their own snapshot meaning where that scope is available.

## Existing-owner connection

Star values use the same scalar/aggregate/analytic projection parser as ordinary
SELECT. Their ASTs preserve source ownership/spans and bounded query/expression
accounting. Expansion creates ordinary projections; it neither evaluates a value
nor installs a new execution or admission owner. Generated retained-column
references have empty source spans, not fabricated authored token locations.

GROUP uses the expanded input snapshot for ordinal/alias resolution and keeps
the expanded SELECT list for HAVING and final projection. Analytic outputs use
the same existing analytic slot mapping. Single JOINs requiring expansion use
the established shared-scope assembler. Type, key, order and capacity evidence
remain common-checker facts attached to actual values/slots.

The query AST interface adds StarReplacement records and a pure star-column
projection helper. `moon info` generated its interface for JS/Wasm/Native; no
machine Program type/schema or wire format changes in this unit. The grammar
manifest changes from the parent's `1e69c47a...` to `57b2c75f...`; independent
normative preimages preserve parent identities. Existing generators refresh
complete document imports and canonical fixtures, without relabeling old Runs.

## Verification checkpoint

- Focused JS: 25/25 (`run-NbzWoq`), covering swap, original-input expressions,
  GROUP/HAVING, aggregates, analytic values, JOIN/CTE and existing star/ORDER
  callers. Wrong target/name refusals assert specific existing issue kinds.
- Source fixture/selector/profile Node: 11/11 (`run-hASZ0g`).
- The authored public corpus has 13 successes and 8 preparation refusals,
  including independent JSON, NULL/duplicates, swaps/arithmetic, alias versus
  qualified-input ORDER, EXCEPT with an added column, GROUP ordinal/HAVING,
  aggregate/analytic output, preserved old range values, CTE, LEFT JOIN type
  refinement and typed empty Result. The usual harness checks full schema/order,
  admission/I/O, one acquisition and same-request/re-read behavior.

Final manifest and independent-preimage Node checks passed 7/7 (`run-m2OzHC`).
Normal five packages built from `639741be35e651b13a1769230b6117a361923866`
passed all 13 successes and 8 preparation refusals in Embedded Local and HTTPS:

```sh
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-star-replace-20261007-pack node scripts/test-packed-public-query.mjs --star-replace-only
```

Both transports compare full Result.describe contracts, column order and rows,
including empty output, NULL/duplicates and changed nullability. Existing checks
require stream completion, one acquisition session, stable same-request identity,
reattach/re-read without further acquisition, and zero admission/provider I/O on
refusal. No case, expectation or ceiling was removed or relaxed. Receipt/command
logs remain under `worktrees/.codex-scratch/public-query-evidence-uTnXdQ`.
The producer used normal prepack and manifest/digest verification, without runtime
overlays. `review-artifacts/` remains untracked evidence, not a changed build input.

| Package | SHA-256 |
|---|---|
| client-wire | `27066b9ab7a1f4a3f15dec782b17ccdff5f04aca45ca2b3bf1496bb6bca329c3` |
| sdk | `d72e590dca3666fa0d2444492b2ec4559b056008a5b8575d4bc4ebe24159baa9` |
| run-host-core | `4a95dfc72c5b15917456449da947f3db96d50b975740048fdd0bfc449d2873cf` |
| local-node | `745620ba5db56cd1de77936536ff1568a9e32e2f1697e7ad1574dcce46b1082e` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

This later report-only change is not another tested distribution. Submitted-SHA
CI and content review remain pending.
No whole-Core, full packed, performance, Cloud or Wasm/Native execution campaign
is claimed. Interface generation is not backend execution evidence.

## Separate type gap

[STRUCT contract gap](2026-10-07-struct-contract-gap.md) records the ordered,
possibly anonymous/duplicate-field STRUCT representation still missing from
the common contract. It is not approximated by an object mapping in this PR.
# Subsequent main integration

Main `e3c85c7b7b7a98e94ebe919764e05225f83d8dd9` includes #673. The branch
merged that main normally, preserving its closed Graph Program schema and
retained SDK diagnostic contracts. The PR can now target main; no parent
branch merge is used as completion. Conflict resolution preserved both
published grammar histories and regenerated imports/fixtures from the
combined source. Independent canonical calculation gives the integrated
grammar manifest `sha256:ebd855090f5f4695042910f4f0471a460929aeb4e26de36609b965b6c4623922`.

Focused post-merge checks: `star_replace_test.mbt` JS 3/3 and Node fixture/
manifest tests 9/9 passed (`focused-test-orJveL`, `focused-test-NF24iY`). No
packed or full-Core verification was added merely because main was merged.
The earlier packed success remains evidence for its recorded source SHA;
integrated-HEAD packed execution and required CI remain unverified.
