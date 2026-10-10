# Parenthesized positional operand output context

This frontend connection repair follows #1271 at
`a054de80639807149a6d454b5c59b68dfb0a747e`. The parent is an unmerged
stack dependency; final destination is main. This branch normally adopts
main `8d187fd23` before the repair. No dependency-branch merge is requested.

## Fixed meaning and pre-repair evidence

The saved source in [the original counterexample](fixtures/anonymous-window-parenthesized-set.sql)
expects `(0,0), (1,2), (2,1)`, nonnullable numbers in a/b order. Its two
window orders depend on the immutable original.x and current x after SET.
The same values have a separately authored ordinary JSON control; no expected
Program or rows are serialized from frontend output.

A newly fixed focused counterexample retained the same opposing window orders
with current x=-original.x. Before product repair, text returned
UnsupportedProjection while the independent JSON control passed: 1/2,
run-7w1mZB / focused-test-sjqfan. This was a lowering refusal, not executed
wrong rows. The parser retained a synthetic CTE but lost the positional
export context before compiling its body.

## Connection and scope

Query now retains private parser-owned facts for its internal binding and
positional output role. SQL positional right operands mark their bound output;
identity-only synthetic wrappers propagate that role through parentheses.
Authored CTE declarations and transformed continuations do not receive it.
The generated producer's spelling never proves that it is a synthetic binding.
Propagation charges the original parser work budget.

compile_steps consumes that fact through the existing positional projection
machinery. The standalone entry uses existing script composition for those
bindings; it does not publish an intermediate Result with anonymous names.
No new evaluator, acquisition, save boundary, runtime Owner, provider,
authorization or compatibility fallback exists. query_script_program.mbt,
CTE predicate/capture scheduling, assert and Effect processing are unchanged.
The common checker retains type, identity, NULL, capacity and Result decisions.

The syntax package's interface is generated with the pinned `moon info`, not
edited by hand. The new accessor exposes a frontend AST fact, not SDK input or
an authorization claim. Common Program/wire/grammar contracts are unchanged.
Program topology/CIDs may differ where standalone dispatch now chooses script
composition; this does not reinterpret stored Programs or Runs.

## Independent regression boundaries

Focused tests cover the saved scope, double parentheses, nested sets,
anonymous scalars/aggregates, local CTE inputs, and standalone dispatch. They
keep exact UnsupportedProjection for unnamed authored CTE, BY NAME and DATA
exports. Private QUALIFY references remain invalid input.

The exploratory nested DATA Program has 24 emitted steps, exceeding this
focused unit fixture's 20-step structural ceiling. Its checker refusal is not
claimed as an actual public Host failure. No ceiling was raised. The focused
nested test uses the existing identical x=1,2 Values input without the eight
DATA-construction steps. The unchanged 24-step DATA source stays in public
acceptance with independently specified `(0,0), (1,2), (2,1), (3,4)` output.
A temporary test-only print preserved the diagnostic Program, then was removed.
The diagnostic probe (run-xbSmzf) and a test compilation error
(run-jOhfUL) are not passing evidence.

Six normal and three refusal cases join existing ordinary/scoped public
registration. They include the original x+10 SQL-parenthesized source, nested
DATA, double-parenthesized SUM/COUNT, scalar expressions, typed empty output,
and one shared Source session in SQL. Result rows, describe types/nullability,
column order, private-field absence, same-request reuse and Result reread
retain the existing consumer assertions. Refusals require zero admission and
Source I/O. The independent JSON window control remains in the same cohort.
Scoped inventory: 82 cases per transport, 54 normal and 28 refusals.

Authored registration: 3,365 occurrences, 2,132 normal, 1,186 refusal and
47 execution failures. Historical baseline ce027a937 remains unchanged.
Inventory digest: 66ce0d43b2b94b7692c399d68af988affd930dc8d545b1b39cf9d3ceee4c5d5f.
This pin enumerates authored data; it does not generate result expectations.

## Actual verification and open coverage

After repair: selected JS scopes/checker/callers 39/39, Node fixture/normal
registration 43/43, whitespace clean. Guard run-6JNLQP; focused-test-gjzcEv
and focused-test-f2bJQE. Actual bounded command:
`node /private/tmp/actql-b-parenthesized-positional-focused.mjs`.
Selected query_syntax interface generation inspected JS/Wasm/Native; no
backend-interface divergence appeared. This is not Wasm/Native execution.

Exact committed-SHA package/runtime evidence is recorded in the PR after
execution, separately from these pending-patch checks. Full Core, all targets,
full public corpus, hosted CI and deployment are not established here.
Parenthesized output followed by additional transformed continuations remains
a distinct connection obligation; no blanket anonymous-export permission was
added to make it pass.
