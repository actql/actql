# SQL grouped subexpressions: evaluated-key connection

Date: 2026-10-08. Owner: B. Stacked on the scalar Pipe aggregate PR #910,
which itself depends on #906. Final target is main; no PR merge performed.
Main `9dff38dfdc080254fa1b648957de1ce8ce37f72f` was normally merged before work.

## Defect and independent control

```sql
SELECT COUNT(*) + (pair.x + 1) AS n
FROM pair
GROUP BY x + 1
```

For the independent input `{x:7,y:9}`, the existing common Program expresses
Values -> derive key `x+1` -> group/count -> derive count+key -> select n.
Expected row is `{n:9}`. The complete independently authored JSON Program is
in `src/query_program/sql_grouped_subexpression_test.mbt`; ordinary checking
succeeds before the equivalent text fails at compile unwrap. Pre-fix evidence:
`run-kzDPeO`, `focused-test-mzKQZo`, 0/1. No generated Program was corrected
inside a test to manufacture success.

The same gap existed in JOIN's scoped SELECT branch, and in the evaluation of
a SELECT alias required by HAVING. JOIN's original `l.x` reference failed at
source byte 19 (`run-EpNTS6`, `focused-test-aJK93f`). The added HAVING case fails
before its connection (`run-Kx0IdE`, `focused-test-4949Un`, 0/1).

## Change and invariant

The existing Pipe key-subtree binding is shared in a private Frontend helper.
SQL retains the pre-group input resolver and connects both SELECT branches and
the existing HAVING projection cache. A subtree is replaced by an evaluated
key slot only when its receivers and property members have the same resolved
meaning. No original receiver or ungrouped input is restored. SELECT siblings
cannot read new aliases. Private references avoid authored names, cloning keeps
original source/work evidence and comparison work remains bounded.

Ordinary group/derive/select/sort and common property/type/NULL laws are reused.
No checker, execution owner, planner, Host, capacity ceiling, acquisition,
serialization or legacy wire fallback is added. The shared helper skips key
search when there are no grouping keys. This is not a claim that all HAVING,
analytic or aggregate signatures are implemented.

## Focused verification

`run-ogcXMr` completes these bounded JS/Node checks:

- New complete Program, receiver/collision, refusal, CTE/JOIN and work/origin
  controls: 5/5 (`focused-test-zYLh8x`).
- Existing SQL aggregate callers: 5/5 (`focused-test-JenFdp`).
- Existing grouped property keys: 9/9 (`focused-test-v74tu7`).
- Existing Pipe scalar aggregate callers: 4/4 (`focused-test-jqOCvO`).
- Existing HAVING projection callers: 6/6 (`focused-test-Q5pu7Y`).
- Independent grammar/Run and public-profile Node vectors: 13/13
  (`focused-test-tdtnhI`).
- Readonly compilation manifests, document metadata/imports, spec family and
  377 canonical identities match their generated inputs.

The actual Values Run-material caller also passes 1/1 in `run-5jEenB`,
`focused-test-micdmT`; fixture/runner syntax checks pass.

The unchanged EBNF hash is
`6f25704123fd2d1fd4ee3a7fd57d4d7d2502b76994743edbc6322de0e54641ca`.
The clarified normative rules hash is
`13238f8dccbc99f4244427ac8362ee093307ceff6151f6116638b44b1fb0c885`,
grammar CID `sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8`.
The independent full Values preimage is retained at
`_build/independent-evidence/sql-grouped-run-preimage.json`, yielding
`sha256:e5068efe3ea2216fc07cd3373f3ca0ba9af030ea9b7514aa33e75067d209e869`.
The containing Run's grammar dependency changes; Value/Unit/ResultPlan laws do
not. Parent grammar/Run vectors remain independently checked.

## Public acceptance status

The normal group corpus now registers nine positive cases and four preparation
refusals, including an independent JSON control, nullable keys/receivers,
duplicates, alias collisions, WHERE/HAVING/ORDER/LIMIT, JOIN, CTE, empty input
and repeated keys. The existing runner selects this same corpus with
`--sql-grouped-subexpression-only` without changing Programs or expectations.
Fresh clean-SHA five-package Local/HTTPS execution passed as recorded below. It is not established by the parser/checker tests.
Full Core, Wasm/native, full packed/proof/performance and required CI remain
unverified; no manual CI rerun is requested.

## Fresh packed evidence

Normal producer and the selected public consumer completed in `run-UEPJhp`,
exit 0, complete=true, locksReleased=true, at clean source
`fb75335a8fedb61dd94447f04796a1ab3a0eaa9a`.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-sql-grouped-fb75335a8-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-sql-grouped-fb75335a8-pack node scripts/test-packed-public-query.mjs --sql-grouped-subexpression-only
```

Embedded Local and HTTPS each pass nine normal cases and four preparation
refusals. Named rows, full Result.describe contracts, column order, NULLs,
multiplicity, sorting, stream completion and private-column absence are checked.
Existing owned-request resend/attach/reread and refusal Run-admission/provider-I/O
counts remain checked. No source/Program transformation occurs in the tests.
README Local/HTTPS startup succeeds; omitting the current generated wire asset
fails with ERR_MODULE_NOT_FOUND, without legacy rescue.

External evidence is `worktrees/.codex-scratch/public-query-evidence-hkJ6sK/summary.json`
and `010.stdout.log`: source SHA exactly fb75335a8, dirty=false, all ten commands
exit 0 with complete output, complete=true, no evidence errors. The successful
private install and Stores were automatically removed; logs and receipts remain.
Manifest: `/private/tmp/actql-b-sql-grouped-fb75335a8-pack/packed-client-packages.json`.

| Package | SHA-256 |
|---|---|
| client-wire | 2b338fd190176568aaa56695e89a14b8a2faa4cb0efc2acdbd8cf035f6a6653f |
| sdk | 5ce098629cca48ea851bdfdd01d71e2b19076535699902a691143b0f2b698869 |
| run-host-core | f0226a602d55ec4ddef34da8ccf22f4ed383b196859026ba2efdb608b96d90a3 |
| local-node | c84f67b9ccbfc6e08f42e118bb8dfbb24d166e80b53dc07198cba99462b6dad2 |
| node | b8732a1abfd7be7954ef172b65390747114517e6884ebe8e74b20070104ba18b |

Parent #906 is now merged. Parent #910's current
`78f3db8cb18a9c42e3f8c729214fb93c4b31a1aa` normally merges that main.
Aligning this branch with it creates `df0ce20eff73acde6df1010cde9d790de19d6765`;
its diff from packed fb75335a8 is empty for packages/src/adapters/spec/scripts
and normative query rules. This subsequent review-record update changes only
this document. The packed manifest is not relabeled as a later commit.
Required current-HEAD CI and non-JS/full campaigns remain unverified.
