# Parenthesized positional operand output context

This frontend connection repair follows #1271 at
`a054de80639807149a6d454b5c59b68dfb0a747e`. The parent is now merged into main and verified as an ancestor of adopted
main `bb2be575ca74f522d7dfceedd47d7bce2f956dbf`. No unmerged dependency
remains; base and final destination are main. The author fix is
`15ba72eb48a2bc1664f7b0dbab89535d3c404c59`; the main integration preserves
its source and independent expected rows while adopting current resource pins.

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
Inventory digest: bd1cb3d71f607d8164a245c9f6d5262e66d524461c71adab6c5e8563a9650ecd.
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

## First submitted-HEAD public attempt and fixture correction

Clean HEAD `7646f9991e068450c99c533152cd5d822b6fb7b9` passed normal
five-package production and independent manifest/revision/SHA-256 verification.
Guard `run-SI2flH` then failed at the existing scoped consumer's column-contract
assertion, with both transport workers terminal and no live children. Receipt:
`worktrees/.codex-scratch/public-query-evidence-VULnqE`, including
`010.stdout.log`, `010.stderr.log` and `summary.json`. The original scoped
parenthesized window source and nested DATA set passed on both Local and HTTPS
before the anonymous aggregate case stopped the campaign. Later normal and
refusal cases are not established by this failed attempt.

The anonymous aggregate fixture incorrectly declared SUM(x) nonnullable.
[The common group contract](../spec/language.md#group)
requires SUM to return NULL when no non-NULL input exists; COUNT remains
nonnullable. The independently pinned relation-typing Group vector also
requires nullable SUM for a nonnullable argument. The positional set's joined
contract therefore has nullable a and nonnullable b, even though these
particular rows are (0,0), (3,2). Correct only that authored column expectation
and its data-inventory digest. Source, rows, ordering, budgets and product
implementation are unchanged; do not replace SUM with COALESCE or infer its
contract from the observed nonempty rows. The revised final-HEAD campaign will
be recorded separately and must still complete every registered obligation.

The corrected fixture and normal/scoped inventory passed selected Node checks
43/43 (`run-NY5JSW`, `focused-test-djNQAa`). No MoonBit/product input changed
in this correction. The saved ORDER/LIMIT anonymous-output audit is a separate
future connection: at product source 7646f9991e, two text forms refuse
UnsupportedProjection while an independently authored ordinary JSON control
passes its checker (1/3, `run-kfqL1e`, `focused-test-EtcAqy`). It is not an
executed wrong-result claim or a case silently removed from this cohort.
