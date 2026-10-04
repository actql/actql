# Property arguments in existing analytic navigation and frame calls

## Scope and fixed baseline

This independent branch starts at main
`7e32faa5a455dc4beafa02a8cd06313e83772d50`, including #388's Draft CI policy.
There is no unmerged code dependency. It repairs one Frontend boundary:
`lower_analytic_call` used scalar-only expression lowering for the first
argument of `LAG`, `LEAD`, `FIRST_VALUE` and `LAST_VALUE`, although the common
Expression and analytic contracts already admit nullable object properties.

The [adopted query scope](../spec/query-text.md#scope-and-lowering) resolves
SELECT siblings and analytic arguments against the input snapshot. The
[common analytic contract](../spec/language.md#analytic) retains navigation's
argument domain with nullable output and evaluates first/last value within
explicit ROWS frames, respecting NULL values. Window order determines the
calculation and does not itself order a public Result. The first profile's
frame/offset restrictions and required deterministic position evidence remain.

## Independent counterexample and repair

```sql
SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous
FROM objects
```

The [complete handwritten Program](../../src/query_program/analytic_property_arguments_test.mbt)
contains Values, one ordinary analytic operation with a structured property
argument, and a final projection. Its ordinary checker acceptance succeeds.
Both SQL and equivalent Pipe lowering fail at the scalar reference boundary
before repair: baseline **1/3**, `run-aBhb6C` / `focused-test-lWWgJ1`.
Neither the expected Program nor the result expectations come from compiler
or provider output.

The repair changes only the argument's expression entry to
`append_with_properties`. Existing longest-prefix scope resolution supplies
the receiver slot; the common checker validates object members and nullable
propagation. Evaluation remains inside the common analytic call. No eager
derive, sibling-alias expansion, copied evaluator or extra physical boundary
is introduced. Frame aggregates, partition/order-key expressions, ON keys,
CTE capture, assertions, Effect and acquisition are separate boundaries.
Checker, planner, provider, Host, SDK, wire, grammar and saved data are unchanged.

The focused regressions cover SQL/Pipe full-Program equality, quoted/qualified
arguments, all four functions, computed properties, input-versus-output aliases,
Pipe SET's current receiver and retained range snapshot, exact stale/unknown
reference refusals, existing frame/offset refusals, common rejection of missing
members/scalar receivers, and the existing expression work limit.

## Public acceptance obligations

The [public fixture](../../scripts/fixtures/analytic-property-source-input.mjs)
contains ten positives (one handwritten JSON control and nine source cases) and
seven preparation refusals. Input order is 2,1,3; the explicit final ID sort
produces 1,2,3. Payload scores in analytic ID order are 20,10,NULL, so LAG must
return NULL,20,10 and LEAD must return 10,NULL,NULL. Selecting another object as
`payload` must not rebind that SELECT's analytic argument. After Pipe SET,
the old range receiver still gives original scores while offset-zero navigation
of the current receiver gives 5,30,15. Frame values, arithmetic, a typed zero
offset, a nullable member and empty typed output have independent expectations.

The usual harness compares Named rows, full ordered `Result.describe()` column
contracts, NULLs, internal-column exclusion and completed streams. Resend,
lookup and attach must return the same Run without additional acquisition.
Refusals retain existing typed public input errors, zero durable Run admissions
and zero provider I/O. The cases run in the normal packed corpus; the focused
`--analytic-property-only` flag only limits local selection. It does not bypass
normal pack, clean-source, digest or publication checks, and no generated Program
is patched in the test.

## Executed checks and pending coverage

New focused JS tests pass **9/9** (`run-6V6eUq`, `focused-test-JTDWyC`). Existing
OVER callers pass **3/3** (`run-VWa3F0`, `focused-test-X3Pq87`). A test diagnostic
pattern initially used Issue where the API returns Diagnostic and was corrected
before submission. The SET assertion's private index was corrected to the
three-column input's existing naming rule; public values and expected Program
did not change. These intermediate failures are not execution passes.

Packed Local/HTTP and submitted-HEAD CI are pending. Full Core, all targets,
native, proof, performance and a Google service differential run are not local
checks for this unit. Draft preparation is not merge validation; the intentional
`awaiting ready_for_review` result is not a rerun request. No merge is performed.
