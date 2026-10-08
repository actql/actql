# Pipe grouping-key aliases: preserve expressions, rename grouped output

This unit follows the adopted GoogleSQL Pipe profile, including grouping-item
aliases with optional AS. Reference checkout:
`d82db99a923a46571f543a13899dc791a7b6f743`, `docs/pipe-syntax.md`, AGGREGATE.
It is stacked on #901's grouping-only connection. The initial integration
`7675917feb22e5afcc9e7ca738b3234f8e33b5a6` normally merged main
`043c67bc94d2c3143b040884fac6147e80852695` over #901's
`8fc287b0606e73ba8c3e0f2d5f23fc97fb9345b6`. It does not merge into the dependency
branch or claim that an unmerged dependency is already in main.

## Counterexample and existing common meaning

```aql
FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS bucket
```

The independently written complete Program groups on physical x, then projects
that grouped value as bucket. The ordinary checker accepts it before source
compilation. On the initial integration, the source parser rejects the key
alias: the red regression failed 1/1 (`run-ANLIvw`,
`focused-test-gLqrbz`). This is a missing Frontend connection; no common group,
projection or execution semantics need to change.

## Connection

PipeAggregate carries optional output names separately from key Expression
objects. SQL grouping retains its existing scope and grammar. The existing
output-alias parser supplies explicit, implicit and backtick names; the copied
operation detaches its name array along with its key/projection arrays.

The group lowerer still resolves every key and aggregate argument against the
pre-group input. The authored name only changes the display name used by the
existing post-group projection. Physical input keys, aggregate calls, limits,
parameters and checked key/evidence contracts are not rewritten. Old input
ranges and implicit key names are not available through the new grouped scope.
Collision checks use the existing case-insensitive rules. No extra execution
Owner, in-source runtime, hidden public key or schema/evidence synthesis is used.

A sibling-key counterexample groups x AS y and input y AS original_y. For input
x=7,y=9 the two values remain 7 and 9; the first alias must not redirect the
second expression to x. A repeated x key projected as first and second retains
`by:["x","x"]`, produces one group per key, and does not strengthen uniqueness.

## Independently authored acceptance

Four full-Program/checker regressions cover plain/implicit/qualified/quoted
aliases, sibling name collisions, repeated physical keys, exact DuplicateOutput
and removed-name UnknownReference. Two new parser regressions cover copied
metadata, quoting and deliberate distinction from SQL GROUP BY.

The existing public group corpus adds eight positive and four refusal cases.
It retains every predecessor case: the selected total is 31 positive / 15 refusal
cases per Local/HTTPS entrance. An independent JSON control and independent
expected rows/types cover NULL groups and duplicates, implicit quoted names,
empty typed grouping-only output, sibling input scope, repeated keys, retained
SET input receivers and computed keys followed by WHERE/ORDER/LIMIT. The normal
packed suite uses the same fixture; there is no special test-only lowered patch.
Result.describe column order/type/nullability, row stream completion, hidden
fields, admission/provider I/O on refusal and epoch-bound replay/reattachment are
checked by the existing consumer.

The direct zero-column Result boundary remains the separate recorded common
contract gap from #901. Adding key aliases does not close it or turn it into a
permanent language restriction.

## Identity and evidence

Grammar and normative rules intentionally change the compilation closure. Their
manifest, normative import references, embedded manifest, generated canonical
vector and independent Run vector move together. Historical predecessor
preimages remain immutable; old Runs are not silently relabeled.

| Identity | Grouping-only parent | This unit |
|---|---|---|
| Grammar | `sha256:bb311179f5afee3d6e03181b66113f045cbd6190ce4174b32d40ac9a67459a8d` | `sha256:4ac55d221c3878197277681acc425497bc6705a864745d4ae004bbcc17915444` |
| Ordinary Values Run | `sha256:af4b746a75926ddcf8a506348a9df55147a10bf9c0b64e4f950d0ec6d513e9d5` | `sha256:732a5690b7573d96b3c54114780ee1255ddeab06d15514f65ec24236c1107251` |

The values, common source schema, Unit and ResultPlan laws do not change.
Independent complete sorted-key preimages establish the new CIDs; they are not
copied from an issued product result. The query AST interface is regenerated
with the pinned Moon toolchain, not hand edited.

Focused evidence before final publication:

- Full Program/lowering/checker counterexamples: 4/4, `run-v2wrFK`.
- `run-PRXKS7`: new parser 2/2; existing SQL/Pipe scope 1/1; aggregate caller
  1/1; grouping-only caller 3/3; Node grammar/vector/profile 28/28; Values Run
  caller 1/1; canonical grammar caller 1/1. Scoped `moon info` and read-only
  manifest, document metadata, spec-family and canonical freshness pass.

Fresh exact-HEAD five-package Local/HTTPS acceptance remains to be run after the
source commit/final main integration. Its revision, package digests and result
will be recorded in the PR body separately from these preparation results. Full
Core/all-target/proof/all-packed/performance checks are not rerun locally. CI
and review completion remain separate; no merge is performed by B.
