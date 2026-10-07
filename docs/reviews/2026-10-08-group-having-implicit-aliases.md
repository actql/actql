# GROUP BY and HAVING: implicit SELECT aliases

This is a Frontend connection repair under the adopted alias rules, not a new
grouping, expression or execution contract. The initial branch used PR #929 at
`5e6d3d9dbb7478eac70708d09b83d2ef4d26372a` and main
`c54e157b5caa1ad981eb9393f64fd0815fb5a434`. Both #924 and #929 have since
merged. Normal integration adopts main
`f99ed793e3e2207ab45b6e9888d33453616fb29f`; there is no unmerged parent
dependency. Final target and PR base are main.

## Independent counterexamples

```sql
SELECT payload.score, COUNT(*) AS n
FROM objects GROUP BY payload.score
HAVING score > 10 ORDER BY score

SELECT payload.score, COUNT(*) AS n
FROM objects GROUP BY score
```

The implicit alias of a path is its last identifier; the implicit alias of member
access is its member name. Explicit and implicit SELECT aliases are visible to
GROUP BY and HAVING. The selected rules are recorded in `docs/spec/query-text.md`
and the [GoogleSQL query reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#implicit_aliases).
Aliases take precedence over same-named input columns in these clauses; qualified
input references retain their original ranges. This does not change WHERE or
SELECT-sibling scope.

The first independently authored complete ordinary Program checks before the
source is compiled. It derives the nullable property once, groups/counts, filters
the retained key, projects `score,n`, and sorts the public score. With scores
10,20,NULL,20,NULL, the independent expected rows are `[{"score":20,"n":2}]`.
Before repair, HAVING rejects the alias with `Expression.UnknownReference`;
GROUP BY rejects it with `UnknownColumn`. `run-a0tBM3` / `focused-test-sQBjXh`
records **0/2** with those specific reasons. The earlier initial red
`run-y8cKzf` has only an unwrap failure after the independent Program checks;
the test-only Show formatting failure `run-ygTOPw` is not a product result.

A second complete Program control keeps both the property key and the qualified
input score. Input rows `(score,payload.score)=(100,10),(0,20)` deliberately
select opposite rows: HAVING `score > 10` publishes score 20; HAVING
`colliding.score > 10` publishes score 10. WHERE `score > 10` also reads the
original input and publishes score 10. Expectations are authored from these
values, not from compiler or Result output.

## Repair and invariants

- Extract one private `projection_alias` rule from the existing SELECT naming
  helper. Preserve each authored NamePart; anonymous expressions gain no alias.
- Apply it to GROUP BY's alias table, HAVING resolution/materialization, hidden
  HAVING/ORDER aggregate arguments and their input-provenance comparison.
- Resolve implicit property aliases to retained evaluated grouping slots.
  Alias lookup does not expand a SELECT expression at each reference, restore
  an ungrouped receiver, or manufacture uniqueness or type evidence.
- Detect a second matching alias even if the first cannot resolve a slot.
  Qualified input paths, SELECT-sibling/WHERE scope, expression work/origins,
  common nullable-property/COUNT behavior, output order and private-slot removal
  remain existing owner obligations.
- No common checker, planner, capacity, runtime, SDK wire, grammar, contract,
  pin, historical client-wire fallback or compatibility path is changed.

## Focused checks

The final formatted implementation passes guard `run-PYH41o`:

| Selection in `src/query_program` on JS | Result | Evidence |
|---|---|---|
| `GROUP HAVING implicit aliases*` | 6/6 | `focused-test-KuQIgL` |
| `HAVING projection aliases*` | 6/6 | `focused-test-3fT3vz` |
| `HAVING hidden aggregate*` | 5/5 | `focused-test-AtXcLS` |
| `HAVING grouped subexpressions*` | 8/8 | `focused-test-C0x2XF` |
| `grouped implicit property names*` | 6/6 | `focused-test-inXbxC` |

The repository bounded/nonzero-test wrapper executes `moon test --target js`
with each listed explicit package/filter. Readonly
`node scripts/compilation-manifests.mjs` passes, retaining grammar
`sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8`
and barrier
`sha256:8e3203948952a96d5153e9b0300431d29f5c209ce113f14c7f7149d3abac4818`.
Changed-file formatting, JavaScript syntax and `git diff --check` pass.

## Separate remaining member-name boundary

`run-yb0LXU` is **5/6**, not a pass; `run-8gQjGW` isolates the failing source:

```sql
SELECT objects.payload.SCORE, COUNT(*) AS n
FROM objects GROUP BY score HAVING SCORE > 10 ORDER BY SCORE
```

When the declared object field is `score`, resolving the implicit grouping alias
to this input expression emits common `property.name="SCORE"`. Common
`expression_typing/signatures.mbt` requires exact object-field spelling and
rejects `UnknownField("SCORE")`; the Frontend has no schema-aware member-name
mapping here. This is distinct from case-insensitive SELECT-alias lookup.
The passing quoted controls retain the actual field `score` while looking up
the alias as `SCORE`. The failed probe and expected field correspondence remain
recorded; no common check is relaxed and this is not a new permanent language
restriction. A separate schema-aware Frontend member-resolution unit is still
needed before claiming complete adopted field-name behavior.

## Public cases and attribution

Sixteen normal and six exact-code refusal cases are registered in the ordinary
group-property corpus. `--group-having-implicit-aliases-only` selects those same
cases. Independent JSON controls, nullable receivers/fields and duplicate counts,
path/member and quoted aliases, hidden COUNT input, CTE/JOIN with ceiling 10,
empty typed output, input/alias collision and WHERE controls are covered.
Refusals include ambiguity, lost receivers/ranges and WHERE's lack of access to
new SELECT aliases. Existing public assertions check Named Result rows, ordered
Result.describe contracts, complete streams, no private fields, request
resend/attach/reread and refusal zero Run admission/provider I/O.

Normal five-package packed Local/HTTPS execution remains unverified at this
revision. Record the clean producer SHA, actual tarball digests and receipt
before calling those cases accepted. Parent #929's prior public success is
not proof of this implementation. Hosted CI, Wasm/native/full Core/full packed,
proofs/performance and the full Frontend objective remain incomplete. No manual
CI rerun, protection change or merge.


The pre-integration public attempt first terminated during process-group guard
inspection, before evidence/lock acquisition or any package steps. A subsequent
terminal attempt `run-ReeCLI` was refused by the shared heavy lock attributed to
`worktrees/actql-composed-model-observations/_build/local-checks/attempts/run-EOzIeY`.
No producer/consumer step started. The other owner's lock, worktree and output
are untouched. These are guard results, not product execution results.

During normal main integration, three public-corpus/runner files conflicted.
The resolution starts from main, preserves every grouped ORDER case, flag and
common implementation/diagnostic change, then adds this unit's independent
alias cases and selection flag. No existing expected Program, row, type, bound
or refusal is replaced to resolve the conflict.


## Main-integrated focused evidence

Normal merge `1dbd67fc6806406f0af3bbd66237cdcc04c15201` passes guard
`run-ofFx61`: implicit GROUP/HAVING aliases 6/6 (`focused-test-gHjrmP`),
HAVING projection slots 6/6 (`focused-test-f5wuNj`), hidden HAVING aggregates
5/5 (`focused-test-AJDJ1W`), grouped HAVING subexpressions 8/8
(`focused-test-eVn1y9`), newly integrated grouped ORDER subexpressions 8/8
(`focused-test-dMvBod`), grouped implicit naming 6/6 (`focused-test-avLbr6`),
and GROUP property keys 9/9 (`focused-test-59IkOQ`). Readonly manifest
freshness retains the same grammar/barrier CIDs. These are 48 focused tests,
not full Core or public execution evidence.

One additional receiver-provenance test then passes 1/1 in `run-SNeGnx` /
`focused-test-3gMi49`; no compiler implementation changes intervene. It projects
`(@wrapper).payload` without AS, while the input also has `payload`. HAVING
`payload.score + 1 > 12` reads the implicit output receiver; qualified
`objects.payload.score + 1 > 12` reads the original evaluated grouping key.
The independent public expectations deliberately differ: three groups versus
only bucket 21. The parameter is evaluated once, and common checking retains
its nullable closed-object contract. The same two cases are in the ordinary
public corpus. The final case file now has seven tests; this records the
separate executed selections rather than claiming a repeated combined run.
