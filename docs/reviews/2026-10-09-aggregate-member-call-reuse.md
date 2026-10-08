# Reuse aggregate values across equivalent property receivers

Inspected main: `a48c2678421d975602c62709cd8ace4c63dcc118`.
This is a Frontend expression-identity repair, not a new aggregate evaluator,
common contract, syntax, capacity profile or broad compatibility claim.

## Independent discrepancy

```sql
SELECT COUNT(payload.score) AS n
FROM objects
HAVING COUNT((payload).score) > 0
```

The input is a declared nullable closed object with a nullable number member.
Both calls denote the same aggregate over the same input snapshot. The
independently authored Program groups once with `n`, then filters using `n`.
It passes ordinary checking. The previous source lowering instead creates a
second hidden aggregate because one member is a Reference AST and the other
is an explicit Property AST. Member case differences also prevented reuse.
This establishes duplicate computation in the generated Program; it does not
claim an observed incorrect public Run or a measured capacity excess.

The pre-repair selected check executed two tests: one passed, the source/full
Program comparison failed (`run-OR9Kzl` / `focused-test-nRpG2f`). The first
launcher attempt lacked root dependencies and executed no tests. The new
worktree borrows a dependency tree only after matching package-lock bytes and
the package dependency declarations.

The adopted clause scopes are recorded in `docs/spec/query-text.md`:
SELECT arguments use input values; HAVING/ORDER arguments prefer SELECT aliases,
while qualified inputs retain their range meaning. The pinned GoogleSQL
reference `d82db99a923a46571f543a13899dc791a7b6f743`,
[`query-syntax.md`, HAVING](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#having_clause),
also distinguishes these scopes. Aggregate sharing is verified against the
existing ActQL slot-reuse mechanism, not asserted as a vendor execution trace.

## Minimal existing-owner repair

`same_aggregate_call` now compares argument, filter and local ordering trees
through the existing `same_group_expression_in_scopes` helper. It resolves each
receiver in its own clause scope before comparing static property members.
Parentheses, quotation and qualified spelling can preserve that identity;
flattening an explicit object receiver into a range column cannot.

Function, DISTINCT, delimiter, ordering arity/direction and NULL placement
retain their existing equality guards. Operators, parameters, literal values
and demand-sensitive tree structure must still agree. A failure to establish
the same receiver does not authorize reuse. Ordinary expression lowering,
aggregation, type/NULL checking, resource limits and publication owners are
unchanged. No old alias, input or schema is manufactured.

The repair can change generated Unit/Run identities for affected queries by
removing redundant hidden aggregates. Identities are calculated normally from
the actual resulting Program. No old saved Run is reinterpreted, global
grammar/schema/registry pin changed, or measured CID copied as an expectation.

## Independent obligations

- Complete checked Values Program equality for equivalent member arguments
  and per-call filters; selected and hidden calls share their evaluated slot.
- Bare HAVING output alias versus qualified input: a NULL object alias makes
  the former COUNT zero while the original input has three non-NULL scores.
- Explicit object receiver versus colliding range: three object scores versus
  five non-NULL range scores. The predicate distinguishes erroneous reuse.
- DISTINCT and different filters: the duplicate score remains an observation
  for COUNT, and different predicates are not merged.
- Local order and NULL-placement differences: ordered STRING_AGG produces
  `b|b|a|c` versus `c|a|b|b`; repeated aliases never substitute those meanings.
- Empty global COUNT yields zero with the same nonnullable number contract.
- Missing receiver and nested aggregate-alias inputs remain typed refusals.

The public fixture reuses only the existing independently authored object input
and capture recipe. Its new expected Programs, rows, types and column order
are written independently. It adds 12 normal cases and two refusals to the
existing normal/focused HAVING-object corpus, retaining its earlier nine
normal cases, four refusals and one expected demanded-expression failure.
No additional harness, test-side Program patch or enlarged ceiling is used.

## Focused evidence

Repaired JS: **23/23**, `run-xitlKo` / `focused-test-pRy6ww`.
Node fixture/profile checks: **17/17**, `run-WKy4uP` / `focused-test-vGjubg`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 900 -- --target js \
  src/query_program/aggregate_member_call_reuse_test.mbt \
  src/query_program/having_aggregate_test.mbt \
  src/query_program/having_property_order_test.mbt \
  src/query_program/having_object_property_test.mbt \
  src/query_program/group_property_receiver_scope_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 300 -- \
  scripts/aggregate-member-call-reuse-source-input.test.mjs \
  scripts/having-object-property-source-input.test.mjs \
  scripts/having-aggregate-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

Use the normal clean-HEAD five-package producer and existing
`--having-object-property-only` consumer to verify Local/HTTPS through Named
Result and Result.describe. Existing assertions retain acquisition-once,
same-request resend/reattach/reread without reacquisition, internal-column
exclusion and zero admission/provider I/O on preparation refusal. The PR body
must record the actual source SHA, package digests and terminal result; those
are pending at this committed evidence snapshot. Full Core, other targets,
other corpora, Cloud and the overall Frontend goal are not established here.
