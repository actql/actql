# GROUP ORDER receiver scope: range shadowed by an output alias

## Fixed source and finding

This independent Frontend unit starts at published main
`1887855e9bf867ba9c3abb724dc52ebe4be3daa1`, tree
`2ee473058c247ff405427b70422b755caf5ec4c2`. The original helper and its
SHA-256 are retained in [source-baseline.json](source-baseline.json).
The baseline finding is established by source inspection, not an executed
compiler or public Run failure.

A representative source is:

```sql
SELECT score AS bucket,
  CASE WHEN score IS NULL THEN @nil
       WHEN score = 10 THEN @low ELSE @high END AS payload,
  COUNT(*) AS n
FROM objects AS payload
GROUP BY score
ORDER BY payload.score NULLS LAST
```

Input `score` values are `10,20,10,NULL`. The independent typed object
bindings are `low={score:30}`, `high={score:5}`, and `nil=NULL`.
The expected grouping counts and output order are:

```json
[{"bucket":20,"payload":{"score":5},"n":1},
 {"bucket":10,"payload":{"score":30},"n":2},
 {"bucket":null,"payload":null,"n":1}]
```

The input-only order is `10,20,NULL`, so resolving the wrong receiver changes
observable order. A separate `FROM objects AS original ... ORDER BY
original.score` control deliberately expects that opposite order. A
parenthesized `(payload).score` control and quoted case variants use the
output alias. The empty-input control keeps the complete nullable schema.

## Failure boundary and minimal correction

`query_order_grouped_expression.mbt::append_order_grouped_expression` passes
clause-specific source resolvers to the existing grouped-subtree matcher.
In the original `resolve_order_input`, only a one-part path checked SELECT
aliases. A two-part `payload.score` could resolve completely through the
original range before prefix lookup saw the nearer output alias. It therefore
appeared to have the same source slot as the GROUP key `score` and could
substitute that evaluated key for the output object's property.

The correction blocks whole original-range lookup when the receiver has a
SELECT output binding. Existing prefix resolution then proves an alias's
original source, or ordinary ORDER lowering reads its evaluated object slot.
It does not discard grouping keys, restore unavailable input, reevaluate the
CASE, implement property typing, change sorting, or introduce another Owner.
The independent complete MoonBit Programs require one CASE evaluation and one
ordinary alias-property ORDER derivation. Missing properties and a scalar
alias remain the common checker's responsibility; an unknown old range is
rejected by existing name resolution.

This applies the already adopted scope contract in
[query text](../../docs/spec/query-text.md), including ORDER aliases overriding
input row receivers. It introduces no new grammar or language contract.
The selected reference is GoogleSQL
`d82db99a923a46571f543a13899dc791a7b6f743`, particularly
`resolver_query.cc`'s post-group alias scope and
`name_scope.cc::CopyNameScopeWithOverridingNames`. The
[official ORDER BY rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause)
support alias precedence. This is not a blanket statement about GROUP BY
alias lookup or all GoogleSQL STRUCT behavior.

## Authored verification and acceptance

- Two MoonBit tests compare complete independently authored Programs, ordinary
  checker results, nullable object receivers, quoted members, and the
  nonshadowed input control. They have not been executed by B.
- Two Node tests pin the independent fixture and its normal/narrow registration.
  They have not been executed by B.
- The existing packed driver accepts `--group-order-range-alias-only`:
  **six normal and three refusal declarations per Local/HTTPS transport**.
  These are prepared declarations, not executed counts. They also remain in
  ordinary packed registration.
- Independent JSON and authored text use the ordinary Source/checker/Host path.
  Expected values, full ordered contracts, duplicate counts, and one Source
  acquisition are authored, never sampled from product output. The standard
  capacity and existing driver same-request, refusal-before-I/O, Result and
  cleanup assertions remain unchanged.
- Registration-only inventory enumeration updates the source pin; it does not
  execute parser, lowerer, compiler, Run, provider or public SDK.

The current unit does not change grammar or owned contract bodies. It should
not change the canonical grammar or values Run vector solely to follow an
observed product result. Historical vectors remain intact; subsequent normal
main integration adopts upstream's actual grammar/vector changes separately.

## Verification status and handoff

[prepared-checks.json](prepared-checks.json) contains bounded existing-wrapper
commands for Root's independent worktree. No shared Heavy window is reserved,
no new producer is started, and B does not retry the retained guard rejection.
Executed B evidence is limited to individual pinned formatting, Node syntax
checks, read-only freshness, registration data enumeration and whitespace.
Compile, nonzero runtime tests, pristine five-package public acceptance,
cross-target execution and CI remain unverified until actual receipts exist.
No feature is declared complete on parser or preparation evidence alone.

The queued DATA redesign is not implemented here. Existing DATA spelling in
these fixtures expresses current accepted inputs; it neither starts the new
binding design nor supplies a compatibility path for its future cutover.

## Normal main integration

The first normal merge adopts the published hex-integer main
`e3bbe9c34ae89100917eff26a21737648c1e1a01`, without modifying the stable
submitted branches for navigation offsets, LIMIT operands or grouped ROWS.
The original conflict exit is retained in [main-merge-conflicts.json](main-merge-conflicts.json);
only packed registration, the independent inventory pin and its assertions
conflicted. Both fixture groups remain registered. Upstream grammar, generated
pins and historical identity vectors are adopted unchanged.

The combined declaration inventory has 3,939 occurrences: 2,482 normal,
50 execution-failure and 1,407 refusal declarations. Its SHA-256 is
`cb50300ea06964af566fa4bdf26583db0ae83ca7108c9e03b70d74e9087e5b37`.
This is registration data enumeration, not execution or public success. The
original baseline and pre-integration inventory remain separate.
[integrated-static-commands.json](integrated-static-commands.json) records
three Node syntax checks, five read-only freshness checks and whitespace,
all exit zero. None compiles or executes the authored regression tests.
The selected producer/public commands remain prepared and unstarted.

Raw conflict-marker evidence made the initial staged whitespace check exit 2.
The original bytes are retained in escaped JSON with their SHA-256, rather than
leaving literal conflict-marker lines in tracked text. The failure record is
[staged-conflict-evidence-failure.json](staged-conflict-evidence-failure.json);
it is not reported as a pass. This evidence-only follow-up does not change the
product fix or independent oracle.

## Navigation main follow-up

After the initial Draft submission, #1468 reached main
`588319cd4bb292a414129f299bda8098cbc7657c`. This unit adopts that fixed
main by a second normal merge, without pushing to the submitted navigation
branch. Only the independent inventory and its assertions conflicted; original
bytes and the exit-1 merge receipt remain in
[navigation-main-merge-conflicts.json](navigation-main-merge-conflicts.json).
Upstream navigation semantics, grammar identities and historical preimages
are adopted without editing them.

The combined registered inventory now has 3,943 declarations (2,482 normal,
50 execution-failure, 1,411 refusal), digest
`bcde581e0ce5e516871bae343aec3c97adddf3f08731bd036c545ffd471f5c1a`.
The GROUP ORDER independent oracles are unchanged.
[navigation-integrated-static-commands.json](navigation-integrated-static-commands.json)
records three syntax checks, five read-only freshness checks and whitespace,
all exit zero on the merged working source. Runtime/public remain unexecuted.
