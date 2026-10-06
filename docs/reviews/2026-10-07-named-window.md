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

## Normal fixed-package public acceptance

The initial normal package source `51d7a5e4b860ecd11938d005621441bb796c96a0`
stopped before Host execution: main's SDK tarball omitted its imported
`operation-formats.mjs`. Evidence is `public-query-evidence-WxksIZ`; this is
not a named-window execution pass. B isolated the packaging-only repair in
[PR #684](https://github.com/actql/actql/pull/684), shared ownership on #679,
and normally merged fixed dependency `2bf5141056ccd01f14b0fb807033455c35709f6a`
into this branch. SDK implementation/diagnostics remain E-owned.

Normal five-package source after that merge:
`5e1beb8d503bda677a549adeedfd9e314710c0aa`. The ordinary runner completed
Embedded Local and public HTTPS with 13/13 successful cases and 10/10
pre-admission refusals per transport. Named Result rows and describe columns
(order, complete type and nullability), duplicate/NULL behavior, one acquisition,
retransmission identity and no re-execution were checked by the existing helper.
No expectations, ceilings or input sources changed after the initial attempt.

Commands, with pinned MoonBit/Node PATH and MOON_HOME for packing:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-named-window-fixed-20261007-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-named-window-fixed-20261007-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
npm_config_offline=true npm_config_include=optional \
node scripts/test-packed-public-query.mjs --named-window-only
```

Evidence: `worktrees/.codex-scratch/public-query-evidence-Fw80yG`, with successful
summary and captured Local/HTTPS output. The harness removed the external
installation after saving source/package digests and logs. The normal producer
directory retains `packed-client-packages.json` and five tarballs. Digests are
listed below; they are not rewritten to stand for another HEAD.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `af57abf7f4cbbed70fcc316975b70e532b6d67cb26737c552ea9608d12922a75` |
| sdk | `ba73a00f0506c67ca00995da5dca55ddf929280e51d57fbd996cfa027997d947` |
| run-host-core | `f788f89786f0e42377e936c40284b07a9458f3ff937b7c6b6a3d8c0b0743e1b0` |
| local-node | `e4aa05b303316cbbd2071f004e324b05bd64295a51c4c31100252e15c727c413` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Submitted-HEAD CI/content review remain separate; keep the PR Draft. Dependency
#680 and SDK delivery #684 must reach main before final integration. Passing this
selected corpus does not close #680's unchanged JOIN capacity reproduction or
the broader Frontend/standard coverage gaps.

## Subsequent main integration

Normal merge adopts main `be30c8fdf2b3133219f7becc74c5667619806c70`, including
bounded field/property-name lookup and the SDK delivery repair already merged
as #682. The package delivery fix is no longer a missing main capability;
#684 now contributes only its contained archive regression/evidence. The
unmerged #680 parent remains. Post-merge named-window JS checks pass 4/4
(`focused-test-cjIDOg`); read-only spec-family/document metadata checks passed.
No packed campaign is repeated merely for integration. The public success above
remains bound to `5e1beb8d503bda677a549adeedfd9e314710c0aa`, not the later HEAD.
