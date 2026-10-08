# Quoted scalar function binding

This closes a Frontend connection gap for the already installed scalar function
subset. It does not introduce a function catalog, UDFs, additional namespaces,
overloads or an expression evaluator.

## Requirements and reference evidence

The selected SQL/Pipe profile uses GoogleSQL identifier decoding and built-in
function semantics. Backticks delimit an identifier, not a string or another
function namespace. The selected reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`:

- [Parser](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/parser/googlesql.tm):
  `token_identifier` decodes quoted identifiers; `function_call_expression_base`
  accepts the resulting path expression.
- [Resolver](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc):
  `GetFunctionNameAndArguments` obtains `ToIdentifierVector()` and
  `LookupFunctionFromCatalog` resolves the resulting names, without giving
  quotation a separate scalar-function meaning.
- [Quoted keyword function fixture](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/parser/testdata/keywords.test)
  and [quoted IF analyzer fixture](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/chained_function_call_special_cases.test)
  corroborate this syntax and binding distinction. They are source evidence,
  not a live Google service differential run.

The historical `scalar_call` guard rejected every quoted name before using the
closed installed-name table. Three earlier tests recorded that implementation
limit as a refusal. They did not establish a semantic reason to refuse the
quoted spelling of an installed function. This change removes that limit using
the existing name decoder and case-insensitive installed-function lookup. No
new structural grammar, machine expression, contract body or CID preimage is
introduced. Unsupported names and qualified forms remain explicitly refused.

## Independent counterexample and change

```sql
SELECT `IFNULL`(7, 1 / 0) AS value
```

The independently authored complete Program uses the existing
`coalesce: [{literal: 7}, {divide: [{literal: 1}, {literal: 0}]}]` expression,
an ordinary source-free Values witness, projection and explicit Named Result.
The lowercase/unquoted control and the expected Program pass the ordinary
checker. Before the fix, compilation of the quoted spelling fails instead of
issuing that same Program. The bounded red test receipt is
`_build/local-checks/attempts/run-xV4zIm` (one test, zero passed).

`query_expression/lower.mbt::scalar_call` now receives the decoded path without
rejecting its quotation metadata. It still uses the exact installed-name table
and existing arity rules. `` `ACTQL`.`CONCAT` `` remains the explicit ActQL
null-skipping operation; `` `CONCAT` `` remains strict STRING concatenation.
The single identifier `` `ACTQL.CONCAT` `` does not become a two-part name.
`SAFE`, unknown functions, unsupported namespaces and incorrect arity do not
become executable. This does not add quoted aggregate/window-name support.

Expression fixtures independently fix the expected coalesce, conditional,
strict/legacy concatenation, character-length and ceiling trees. The complete
Program fixture fixes lazy evaluation and ordinary checker acceptance. The
existing IFNULL public fixture adds decoded/mixed-case names, lazy fallback,
typed NULL and STRING/Unicode results, with exact independently authored
columns and values. Its default cohort and existing `--ifnull-only` selection
both include the additions; no new public acceptance runner is required.

## Evidence and remaining work

- Focused JS: **14/14 passed**, including the new expression and complete
  Program controls, existing IFNULL/ceiling/character-length boundaries and
  source-free callers. Receipt: `_build/local-checks/attempts/run-UxPup5`;
  focused evidence: `_build/focused-evidence/focused-test-k1yQ8O`.
- Public fixture syntax and `git diff --check` passed in the same bounded gate.
- The existing packed public IFNULL cohort now has thirteen positive cases,
  nine preparation refusals and one demanded-failure case. Public execution
  has not yet been verified for this change. Quoted success, NULL type,
  declared column order, stream completion, no-admission/no-provider-I/O
  refusal and same-request/result reattachment must use the normal packages
  and the existing Local/HTTPS consumer.
- Full Core, Wasm/Native, broad packed and CI success are not established by
  this focused gate. Previous unit successes remain evidence for their own
  source revisions.

The exact submitted SHA, package manifest/digests, public command results and CI
status belong in the PR body; this source record must not claim unrun evidence.
