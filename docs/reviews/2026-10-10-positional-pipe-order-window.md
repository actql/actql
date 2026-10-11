# ORDER windows over positional Pipe input

## Existing requirement and fixed counterexample

Pipe ORDER window expressions consume the current Relation scope. A hidden
window result supplies the explicit sort key without renaming or dropping the
already evaluated public occurrences. Anonymous and duplicate authored columns
are valid positional set inputs, while private storage names remain inaccessible.
This repair connects those existing contracts rather than changing them.

On baseline `233635daad8692562969212bef1d6d75ffea130c`, this complete source
fails with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x
  |> ORDER BY ROW_NUMBER() OVER (ORDER BY kept DESC)
  |> LIMIT 1
)
ORDER BY a, b
```

For x=1,2, the independent expected rows are (0,0),(2,-2). An independently
authored complete JSON Program derives the anonymous negative value, projects
kept/neg, computes a descending row_number, sorts its result, takes one row,
selects a/b, appends the anchor, and explicitly sorts the Named Result. That
Program passes the existing checker. Baseline guard `run-huKEhu` executes two
tests, with the JSON control passing and the source failing specifically with
UnsupportedProjection. A second unchanged baseline guard `run-7Yol9W` confirms
the same result after a local evidence-state assertion prevented the intended
edit; neither guard is reported as a successful check.

Preserved test:
`/private/tmp/actql-b-positional-order-window-233635daa-baseline.mbt`.
Independently authored Program, source, input and expected rows:
`/private/tmp/actql-b-positional-order-window-independent-control.json`.
This is compiler/checker evidence, not an incorrect published Run.

## Minimal repair and scope

Continue `positional_set_terminal_projection` through OrderAnalytic, as it
already does through ordinary ORDER and analytic evaluation. This preserves the
preceding SELECT's positional role. Reuse the existing ORDER window lowerer,
evaluated physical occurrences, private-key allocator and explicit sort/take.
No execution owner, source refetch, schema/pin change, capacity exemption,
fallback or consumer-side Program patch is introduced.

The existing plain OVER-key resolver reports UnknownColumn for a missing key;
expression references report UnknownReference. Tests preserve those concrete
refusals, ambiguity and AS displacement rather than assuming every failure has
the same diagnostic. The first expanded diagnostic probe (`run-Mgcajn`, 28/29)
expected the wrong error family for a missing plain key; the product already
refused it. The fixture expectation was corrected from the existing resolver
contract, not from an incorrect value or weakened execution requirement.

## Independent public obligations

Eight normal cases cover the complete JSON control, source counterexample,
AS followed by SET with an immutable range receiver ordered oppositely to the
current value, scalar window arithmetic with a declared parameter and
LIMIT/OFFSET, duplicate authored aliases with a separate usable key, a legitimate
name resembling an ORDER private slot, nullable values, and typed empty output.
Six refusals cover anonymous private keys, dropped input, ambiguous aliases,
a displaced range, a leaked hidden window key, and a qualified anonymous key.

The same existing public consumer verifies Named Result values/order,
Result.describe types/nullability/declaration order, hidden-column absence,
Source acquisition counts, same-request Run reuse and zero Run admission/
provider I/O for preparation refusals. Neither expected Program nor rows is
generated from the compiler; no output Program is patched for execution.

Registration includes both the normal corpus and the existing selected cohort.
The data-only inventory is 3,537 occurrences: 2,230 normal, 1,260 refusals,
47 execution failures; digest
`49975cde7830955d2be918d4cc2704daaee4d1f9d0084b7418bb0b06eb507a1c`.
Selected registration is 254 cases per transport: 152 normal, 102 refusals.
Registration alone is not execution evidence.

The older DATA/QUALIFY window fixture's format assertion now uses its precise
`set-corresponding-refuse-window-` family and asserts the original count of two.
An unrelated SQL ORDER-window family must not inherit its DATA-specific format
requirement; all original refusal cases and assertions remain.

## Integration and validation

Normal merge `233635daad8692562969212bef1d6d75ffea130c` adopts main
`5c0ca14580309eaf43bdbd7dc2e1b227b479d3fd`, including merged EXTEND/AS #1312.
No unmerged parent dependency remains. Final destination is main.

After the repair, guard `run-cgnh6J` passes the two baseline/control tests.
Guard `run-IIb5y0` passes 22/22 focused JS tests for the new boundary, positional
helper, set ORDER private scope and ordinary analytic ORDER expressions.
Guard `run-EWOit4` passes 54/54 targeted Node tests (18 fixture, 36 inventory).
Formatting and `git diff --check` pass. The earlier Node probe `run-I4Twbc`
failed only because the overly broad older DATA-window fixture selector also
matched the new SQL fixture; that selection is corrected above.

At this commit, exact clean-HEAD normal five-package packed Local/HTTPS
acceptance is pending. Full Core, Wasm/native, the full packed corpus and CI
are not claimed. This repairs one existing composition boundary; the broader
frontend goal remains incomplete.
