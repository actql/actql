# Named WINDOW: query-local resolution to existing analytic specifications

## Scope and reference

Connect `WINDOW name AS specification` and `OVER name` / `OVER (name ...)`
to the existing inline analytic Program. Window definitions are syntax-level
bindings, not Relation producers, computed slots or storage/placement commands.
The base is #680 integration `54a55712446bf79f9c331de8dbd936819c19597c`, which
adopts main `e3c85c7b7b7a98e94ebe919764e05225f83d8dd9` and the #678 parent.
Unmerged parent dependencies remain; the ultimate merge destination is main.

Selected sources:

- [GoogleSQL named-window rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls#rules_for_using_a_named_window_in_the_window_specification).
- GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
  `googlesql/analyzer/analytic_function_resolver.cc`, `SetWindowClause` and
  `CheckForConflictsWithReferencedWindow`: declarations are flattened in
  order, names are case-insensitive, and inheritance rejects clause conflicts.
  Local reference checkout was read only; no vendor service differential run.

Declarations can inherit earlier declarations. A named reference forbids a new
PARTITION BY; inherited ordering cannot be redefined. A framed base cannot be
extended with ordering or another frame; plain aliases retain it. Unknown,
duplicate, forward and circular names are refused. Each SELECT term, CTE and
derived/set operand has its own declarations. Window expressions still resolve
against SELECT input columns, not its output aliases. Only used specifications
become analytic computation; unused expressions are not evaluated.

No RANGE, unbounded/default aggregate frames, new numeric law, execution owner,
provider, materialization or fallback is introduced. Common signature/type/
capacity rules still decide whether a fully resolved specification is executable.

## Independent counterexamples and implementation

`src/query_program/named_window_test.mbt` independently authors the full Values
-> analytic -> projection -> sort -> Named Result Program. It is checked before
comparison with bare, quoted and inherited window sources. At the fixed base,
the source was rejected while that Program passed (`focused-test-K7F5MT`).

The parser retains unresolved names with their authored byte positions until
the query's WINDOW clause is read, then returns concrete inline specifications.
`query_window.mbt` reuses existing bounded expression/order/frame parsing and
accounts declaration lookup/copy work. The lowerer rejects any unresolved name
that escaped its supported SQL context. It never emits a window-name field into
the common Program or adds an execution step for a declaration.

A related getter boundary also had a concrete defect: clearing an analytic
order list obtained through `operation_at` mutated the parsed query, producing
`0 != 1` on a subsequent read (`focused-test-LC1VTY`). Direct projection calls
now copy mutable analytic/aggregate lists, as replacement projections already
did. This is a parsed syntax ownership counterexample, not a demonstrated
public Run corruption. The regression keeps the original expected specification.

Public JSON control and complete row/column expectations are authored in
`scripts/fixtures/named-window-source-input.mjs`; no compiler output generates
them. The unchanged source corpus covers NULL ordering, duplicate rows, case/
quotes, declaration inheritance, numeric ROWS frames, hidden QUALIFY calls,
alias-versus-qualified input, GROUP/HAVING, CTE/Pipe composition, unused
failing expressions and empty typed Results. Refusals retain declaration,
scope, SELECT-alias visibility and parameter checks before admission/I/O.

## Local evidence before packed execution

- Named-window tests 4/4; affected QUALIFY 6/6 and analytic scope 4/4: JS 14/14.
- Targeted Node fixture/independent grammar manifest checks: 9/9.
- Query syntax interfaces generated for JS/Wasm/Native (6 metadata tasks),
  not execution evidence for those three backends.
- Existing generators refresh grammar/import metadata, canonical vectors and
  Workers/Node fixtures. Independent canonical input calculation retains all
  predecessor identities and yields current grammar manifest
  `sha256:313692ca4371f8802b8593c0feae61a7ed43836dd36cefe379a6b187ecf1cb0a`.
- Evidence under `_build/focused-evidence`: `focused-test-jxAEhV`,
  `focused-test-xt5exW`, `focused-test-W5d0fS`, `focused-test-o79Ayu`.

Public acceptance is registered in the ordinary campaign as well as
`node scripts/test-packed-public-query.mjs --named-window-only`. Planned
acceptance is 13 successes and 10 refusals per Embedded Local/HTTPS transport,
including independent Program/rows, Result.describe column order/types, one
source acquisition and no re-execution on reads/attach/retransmission. Packed
execution is not established at this pre-execution checkpoint. It must use the
normal five packages and record their exact source SHA and tarball digests.

#680's JOIN capacity reproduction remains separate and unchanged; a passing
named-window corpus cannot close it. No full Core/all-target execution, proof,
performance campaign, manual CI retry or merge is included in this evidence.
