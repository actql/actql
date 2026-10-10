# Positional Pipe star replacements

## Counterexample and adopted contract

Baseline `027dcfcc743f3e79710918b86964f1deef9b7b85` rejects this text with
`UnsupportedProjection`:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x
  |> SELECT * REPLACE (kept + 10 AS kept)
)
ORDER BY a, b
```

For x=1,2, independently expected rows are (a,b)=(0,0),(11,-1),(12,-2).
An authored JSON Program deriving negation, replacing only kept, aligning the
ordinal columns, appending zero and sorting passes the common checker.
Baseline guard `run-jEpOTp` is 1/2. This establishes frontend refusal, not a
wrong-result observation from an executing Run.

The reference is GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
`references/googlesql/docs/query-syntax.md`, SELECT * REPLACE. Replacements
address named columns and preserve column names and order, while allowing
value and type changes. Unnamed columns cannot be replacement targets.
Existing `docs/spec/query-text.md` supplies simultaneous replacement and
current Pipe column scope. No new language meaning is selected here.

## Repair

- Walk through unqualified single stars containing REPLACE to retain the
  earlier positional SELECT's anonymous roles.
- Pass the existing physical-slot-to-authored-name metadata to star expansion
  and replacement target matching. Duplicate authored names remain ambiguous;
  retaining duplicates does not make their physical names public.
- Check authored replacement expressions against the current projection's
  scope before expansion. Reject anonymous private receivers, removed input
  names, old ranges and duplicate replacement targets with existing errors.
- Keep object-star member names separate from row-slot metadata. Reuse the
  existing bounded expression budget and star/projection machinery.

The common checker owns replacement types and nullability. Existing derive,
projection, filter, DISTINCT, sort and set alignment implement execution.
No acquisition, owner, capacity, wire, identity or common evaluation contract
is changed, and no Program is patched by the acceptance application.

## Independent obligations and evidence

Ten new normal public cases cover the authored JSON control, source scalar
replacement, quoted repeated-star/filter/ordinal LIMIT, simultaneous swaps,
EXCEPT/REPLACE composition, retained duplicate aliases, DISTINCT duplicates,
nullable retained values, a number-to-string replacement and typed empty
output. Eight refusals cover private slots, duplicate targets/receivers,
excluded targets and old ranges. Both normal and narrow packed registrations
include these obligations.

The consumer compares Named Result rows, exact order, Result.describe column
order/type/nullability, private-field absence, Source read counts and request
reuse. Preparation refusals must precede Run admission and provider I/O.
Rows and JSON controls are independently authored, not compiler-generated.

Final affected-caller guard `run-Z2yoBY` passes 24/24 JS and 48/48 Node tests,
including the changed seven tests and exclusion, ordinary replacement,
replacement ORDER and computed object-star callers. Its terminal summary has
complete output, zero exit, released locks and complete caller output.
Formatting and `git diff --check` pass. Earlier failed/incomplete diagnostics
remain distinct from successful verification.

The selected public cohort has 152 cases per transport: 98 normal and 54
refusals. The full authored inventory has 3,435 occurrences: 2,176 normal,
1,212 refusals and 47 execution-failure obligations, digest
`601134f329a4b427bf1236c33419d4fe607425566c690edf87150fcc927b8897`.
This is fixture registration evidence, not full-corpus execution.

The initial exact-SHA five-package execution at
`53d45bbe5d242c02b8dddcc6138a17e11451b66f` ends with failure:
`run-XWqv03`, receipt `public-query-evidence-vAbEVO`. Eight new replacement
cases pass on both transports, but value-type stops at schema comparison and
the remaining inventory is incomplete. Both children terminate; captured
output is complete, locks are released and disposable installations removed.

The fixture omitted the checked string extent. Existing
`expression_typing/signatures.mbt` derives a literal's UTF-8 bound, and
`docs/spec/language.md` defines complete checked contracts and string extents.
Independently, ASCII anchor has six bytes and changed has seven; the common
append contract's upper_join retains max_utf8_bytes=7
(`value_contract/relations.mbt`). Correct that authored contract and assert
both byte lengths without using a product normalization function. Expected
rows, types, nullability, order, acquisition limits and product code are
unchanged. Final Node guard `run-S5mZfG` passes 48/48 after this fixture-only
correction. A fresh exact-SHA public rerun remains pending; record its SHA,
actual tarball digests and terminal receipts in the PR. Previous exclusion
acceptance is evidence only for its own SHA.

No full Core, Wasm/native, proof, performance, full packed or Cloud campaign
was run. Qualified/mixed stars and anonymous analytic replacement composition
are outside this repair's verified scope, not permanent language restrictions.
Other owners' CTE, predicate, assert, Effect and execution work is unchanged.
The wider frontend goal remains active.
