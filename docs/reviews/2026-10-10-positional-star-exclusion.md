# Positional Pipe star exclusions

## Counterexamples and selected contract

The baseline is `01514868b2d08c338d183d8f660b6d55f9dfa6f1`, including
#1286's unchanged-star repair and main's projected WHERE connection.

```aql
SELECT 0 AS a
UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * EXCEPT (kept))
ORDER BY a
```

For independent x=1,2, the result is a=-2,-1,0. Baseline text lowering rejects
`UnsupportedProjection`; an independently authored ordinary JSON Program
passes the common checker. Saved guard `run-b3grXb` is 1/2. This is a frontend
refusal, not an executing Run's wrong-result observation.

The pinned GoogleSQL source is
`d82db99a923a46571f543a13899dc791a7b6f743`,
`references/googlesql/docs/query-syntax.md`, SELECT * EXCEPT: all matching
named columns are excluded, while unnamed columns cannot be excluded.
Existing `docs/spec/query-text.md` defines current-column case-insensitive
exclusion, retained column order and materialized Pipe scope.

A second independent case excludes both x AS v and -x AS `V`, retaining
anonymous x+10. The required result is a=0,11,12. The first partial repair
still rejects it (`run-Dtf81G`, 2/3): duplicate authored aliases had already
been replaced by distinct private physical slots.

A third scope counterexample adds AS old before the first SELECT and ORDER BY
kept after EXCEPT (kept). During implementation, `run-Qsp2eq` showed an
accepted Program sorting kept before the exclusion select. That is not the
post-projection Pipe scope. The repair must reject the removed receiver,
not change the expected order or silently regain an input range.

## Repair boundaries

- Walk backward through unqualified single stars with named exclusions to the
  earlier positional SELECT. REPLACE and qualified/mixed stars retain their
  existing handling; this is not a permanent restriction on their language.
- Retain a private physical-slot-to-authored-name mapping for duplicate
  aliases. The existing star helper excludes every matching authored name,
  retaining the original slots and order of all surviving values.
- Reject EXCEPT names that address anonymous/private slots, including quoted
  case variants. They do not become public aliases.
- Materialize these post-positional exclusion selects before ORDER. The
  removed input cannot supply a sort key through deferred SELECT. Initial
  SQL projection/ORDER handling is unchanged.
- Keep retained duplicate aliases ambiguous; after all their occurrences are
  excluded, subsequent references are unknown instead of stale ambiguity.

No new Program, checker, runtime owner, expression evaluator, acquisition,
capacity, wire or identity contract is introduced. Existing star/projection,
DISTINCT, sort, filter and set ordinal alignment perform the work.

## Authored expectations and verification

The independent JSON control derives negation once, selects kept and neg,
projects neg, aligns to a, appends zero and sorts a. It is not obtained from
compiler output. Nine new normal public cases cover that control, source
exclusion, quoted repeated star/filter/ordinal LIMIT, all duplicate aliases,
DISTINCT with duplicate input, analytic output, global aggregation, nullable
values and typed empty output. Six refusal cases address private names,
missing names, removed aliases, old ranges and retained duplicate aliases.
The existing packed consumer checks actual Result.describe type/nullability
and column order, exact rows/order, absence of private public fields, Source
acquisition and same-request reuse; invalid input must precede Run admission
and provider I/O. These fixtures participate in both normal and narrow runs.

Focused changed/caller guard `run-3deHFB` passes 23/23 JS tests and 47/47 Node
tests. The 7 changed-file tests check the common checker and exact
UnknownColumn, UnknownReference and AmbiguousColumn refusals. Formatting and
`git diff --check` pass. Earlier incomplete diagnostic runs are retained as
failures and are not acceptance evidence.

The authored inventory has 3,417 occurrences: 2,166 normal, 1,204 refusals,
47 execution-failure obligations; digest
`32686b5ae0ba52d2359b9f2544d7510f6997b7b9e3e77464c2acac30a23fd0f2`.
The selected set/CTE-JOIN public cohort has 134 cases per transport, 88 normal
and 46 refusals. Registration and checker success are not public execution.
Clean-source five-package Local/HTTPS acceptance is pending when this record
is authored. Record exact SHA, package digests and terminal receipts separately.

No full Core, Wasm/native, proof, performance, full packed or Cloud campaign
was run. Other owners' CTE, predicate, assert, Effect, Graph and execution
contracts remain untouched. The broader frontend implementation goal remains
active; this repair does not certify every frontend composition.
