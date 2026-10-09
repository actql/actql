# Post-JOIN Pipe DISTINCT connection

Status: implementation, focused tests and exact-source packed acceptance complete;
submitted HEAD CI is not established. This is a local Frontend connection repair, not completion of the
whole SQL/Pipe profile. Base: `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.

## Existing requirement and defect

The adopted [query text contract](../spec/query-text.md) defines Pipe DISTINCT
over the complete current visible row, preserving surviving range bindings.
This differs from projecting first and then comparing only the projected values.
The pinned reference is
[GoogleSQL's DISTINCT pipe operator](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#distinct_pipe_operator).

On the base, both of these parsed queries fail compilation:

```sql
FROM t AS l
|> JOIN t AS r ON l.x = r.x MAX_OUTPUT_ROWS 10
|> DISTINCT
|> SELECT l.x AS x, r.y AS y
|> ORDER BY x

FROM t AS l
|> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10
|> DISTINCT
|> SELECT l.x AS x, rr.k AS k
|> ORDER BY x, k
```

`join_requires_group_scope()` did not recognize the standalone Pipe DISTINCT
operation, so these single JOIN queries reached the projection-only specialization.
The existing shared JOIN compiler and `compile_steps()` already implement the
required evaluated slots, current-row DISTINCT and subsequent range resolution.
Recognizing this operation selects that existing route. No new execution owner,
predicate rewrite, limit change, law/schema pin or compatibility route is added.

## Independent controls

`join_pipe_distinct_test.mbt` contains a complete independently authored Program
and compares it with the lowered INNER JOIN source after normal common checking.
It fixes the JOIN key, explicit ceiling, shared producer, four compared JOIN slots,
sort key and public column order. Additional checks cover CROSS JOIN and the
specific UnknownReference refusal after projection removes a range.

Seven additional successful cases in the existing packed Pipe DISTINCT corpus
include two independently authored JSON controls, alongside two typed refusal cases.
The added cases remain registered in the ordinary packed corpus.

For source rows `(id, amount) = (3,30), (1,NULL), (2,20), (3,30), (4,20)`:

| Input | Independently expected ordered amount rows |
|---|---|
| Self INNER JOIN on id, full-row DISTINCT, then projection | `20, 20, 30, NULL` |
| Same JOIN, projection first, then DISTINCT | `20, 30, NULL` |
| CROSS JOIN with keys `1,1,2`, full-row DISTINCT, then projection | `20,20,20,20,30,30,NULL,NULL` |
| Typed empty source | Empty result retaining the nullable number schema |

The explicit JOIN ceilings are 20 and 15 respectively. Quoted surviving ranges
use the same expected values. Ambiguous bare JOIN columns and projected-away
ranges must refuse preparation. Existing public assertions check Result.describe,
public fields and column order, ordered rows, one shared Source acquisition,
same-request reattachment without new acquisition, and no Run/provider I/O on
preparation refusal. No test patches the lowered Program.

## Focused local evidence

Worktree: `/Users/t14i/workspace/20260822/worktrees/actql-frontend-qualify-group-aggregate-slots`.
Tests use the pinned Node 22.22.0 and MoonBit `0.10.12+1634b282e` with the existing
bounded, nonzero-test wrappers.

- Before repair: 0/2 JS tests, exit 2. The independently authored Program checked;
  actual query compilation failed. Evidence: `_build/local-checks/attempts/run-HmWp4t`
  and `_build/focused-evidence/focused-test-Ezn4oq`.
- Initial repair: 2/2 JS tests, exit 0. Evidence: `run-X7SIdN` / `focused-test-bw42yW`.
- Expanded changed-boundary and caller checks: 29/29 JS tests, exit 0.
  Evidence: `run-CXfNTw` / `focused-test-8AhAu7`.
- Authored fixture/registration checks: 4/4 Node tests, exit 0.
  Evidence: `run-2nYuB5` / `focused-test-hQTjDJ`.

Commands for the expanded checks:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_pipe_distinct_test.mbt \
  src/query_program/pipe_distinct_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/join_distinct_order_test.mbt \
  src/query_program/join_chain_test.mbt \
  src/query_program/pipe_join_ranges_test.mbt \
  src/query_program/pipe_join_input_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/pipe-distinct-source-input.test.mjs
```

## Clean-source public acceptance

Packed source: `eae059a9ed8a0cd497b839c169cde9d2670fb50b`. The source was clean
before and after normal prepack. This report's subsequent evidence-only commit
is separate from that tested revision; its success is not relabeled as execution
of a later HEAD.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-join-pipe-distinct-eae059a9e-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-pipe-distinct-eae059a9e-pack \
  node scripts/test-packed-public-query.mjs --pipe-distinct-only
```

These commands ran under the existing serialized `runLocalCheck` guard with a
1200-second total deadline. Complete local evidence is
`_build/local-checks/attempts/run-BXKiiC`; the preserved public receipt is
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-n5mHtz`.
The receipt reports `passed`, `complete: true`, clean source and ten completed
commands with exit 0 and complete stdout/stderr. Its temporary installation,
Store and TLS material were removed by the existing successful-run cleanup;
original logs and receipt remain. This is local evidence, not a CI run.

Embedded Local and HTTPS each passed all 20 positive cases and all 10 refusal
cases in the selected corpus. Seven older refusals retain the existing accepted
input-error-class check; the two new JOIN refusals explicitly require
`ClientProgramInvalidInput`, and the existing closed value-table refusal requires
`ClientProgramImplementationLimit`. Refusal tests preserve zero Run admission and
zero Source I/O. Successful cases preserve exact rows, ordered schema and
nullability, no hidden public fields, one shared acquisition and same-Run resend
without additional acceptance/acquisition. Both independent JSON controls and
their unmodified text counterparts reached Named Result.

All five tarballs were produced normally, installed outside the repository and
independently matched to the source manifest and the receipt:

| Package | SHA-256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `063f0aff2ef8cbd3c0e280e6198d043fc5812be3b85c29bcfa3b86a03440bac5` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Not established: submitted HEAD CI, Wasm/native execution, the full ordinary
packed corpus or broader SQL conformance. No full Core campaign, manual CI rerun
or merge has been performed for this repair. No unmerged dependency is required.
