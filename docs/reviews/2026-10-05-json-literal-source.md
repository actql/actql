# Generic JSON literal source connection

Base: `7e337afa9e5a64035c5925aca1d93ba0ef787aaf`. Common dependency:
`f80c8133158ee2bd4cf73cf4f5544d3c67dc26c2` / PR #463. Branch:
`feat/frontend-json-literals`. This connects the adopted GoogleSQL literal
prefix to the common typed literal; it does not change JSON execution or
provide a Delta-only path.

`JSON` plus decoded STRING chunks lowers to
`{typed_literal:{type:"json",value:text}}`. String escaping/chunk concatenation
belongs to the existing query parser; JSON decoding, exact numeric-domain
refusal, duplicate-key behavior and complete-input budgets belong to the
common owner. JSON null remains a non-null JSON value, distinct from SQL NULL.
Quoted `JSON` and a bare identifier remain ordinary references.

The complete independently authored Program in
`src/query_program/json_literals_test.mbt` checks all six JSON roots and two
literal-spelling variants through the ordinary checker. Parser/lowering tests
passed 3/3 (`run-I7xdi4`); existing expression/literal regressions passed 12/12
(`run-1fQbM0`). Manifest/profile independent tests passed 14/14
(`run-8yjI4s`). The new grammar changes invocation/Run identity; independent
Values Run vectors preserve the common dependency's prior identity and derive
the new one from authored preimages (2/2, `run-uOwwT3`). No product CID supplies
an expectation.

The ordinary public-query harness registers all-root versus ordinary scalar/
SQL NULL, empty Result, JSON null IS NOT NULL, and four pre-admission refusals.
Each successful fixture spells ordered full description contracts and rows
independently. The narrow external-tarball selection is:

```sh
node scripts/test-packed-public-query.mjs --json-literal-source-only
```

Packed results belong to their exact SHA in the PR validation record. Neither
this parser/checker evidence nor PR #463's machine-input packed success is text
execution evidence. The imported profile's adoption ledger retains its
historical runtime-conformance status. New source acceptance and Graph Delta
composition are separate completion units; no A/C boundary review, full
GoogleSQL JSON numeric range, Wasm/Native runtime or final CI success is claimed.

## Parent integration on 2026-10-06

Normally integrated common typed JSON `00521024e055471a00736c8a2c024166f35267af`,
which includes main `eb74d7b65d0f338ef5862a7d9cd7397744a08eaa`. The ordinary
packed harness retains both JSON selections and main's new analytic/membership
selections. Historical Run vectors retain their complete original closures;
current vectors use the combined expression law and source grammar.

On the merge tree, selected JSON parsing/lowering and grouped-IN caller tests
passed 6/6 (`run-SkIaME`, `focused-test-Rf8rAg`); independent grammar/Run
vector tests passed 3/3 (`run-E4AbTP`, `focused-test-DFkeFP`). Compiler pins,
document imports and canonical vectors were regenerated from merged bodies.
Previous packed acceptance remains evidence for its original clean source SHA.
Integrated packed execution is recorded separately after the Delta child
adopts this parent; no runtime output supplied the fixture expectations.
