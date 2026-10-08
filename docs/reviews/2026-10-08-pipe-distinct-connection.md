# Pipe DISTINCT: public-source connection

## Scope and independent counterexample

Base: `6b87de57ca62c49b719af4a6cc234da6c1153fbc`.
The common Program checker already accepts an explicit visible-key `distinct`.
At this base, `FROM pair |> DISTINCT` is rejected by the public query parser.
The pre-change focused test executed one case and failed at source parsing;
its independently authored Program passed the ordinary checker first.
Evidence: `_build/local-checks/attempts/run-FxFnfF` and
`_build/focused-evidence/focused-test-i0G63R` in this worktree.

The selected reference is GoogleSQL
`d82db99a923a46571f543a13899dc791a7b6f743`,
[Pipe DISTINCT](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md#distinct_pipe_operator)
and `Resolver::ResolvePipeDistinct` in `googlesql/analyzer/resolver_query.cc`.
Distinct compares visible columns. Range-variable names survive only for values
that remain in the visible column map; displaced values are not representative
payload. It is not equivalent to resetting all aliases with SELECT star.

The decisive public rows have old ids 2 and 4 with the same amount 20.
After `SET id = 0`, both become `{amount:20,id:0}` and must collapse.
Including the old private ids would leave two rows. `DROP id` similarly leaves
one amount 20. An original amount range reference remains usable; original id
is rejected. Expected rows, types and order are authored in
`scripts/fixtures/pipe-distinct-source-input.mjs`, including a separate JSON
control, rather than generated from the query compiler.

## Implementation boundary

The parser retains a separate Distinct operation. The lowerer sends the ordered
unique current physical slots to ordinary keyed distinct, which already projects
those slots before equality. No redundant identity SELECT or second evaluation
is added. Range mappings retain only those same slots; a later ORDER evaluates
current columns and cannot recover SELECT expressions or removed aliases.

CTE, DATA, SELECT-headed tails, set continuations and JOIN prefix composition use
the existing query producer bindings. No execution, source acquisition, type,
ordering, Result publication or identity owner is duplicated.

The current common keyed-distinct domain is KeyComparable. JSON and other
non-key-comparable fields are refused by the ordinary checker before admission.
Closed value-table receivers are explicitly refused before lowering could expand
them and conflate a NULL object with an all-NULL object. This is a current support
gap, not a permanent language restriction. Full GoogleSQL object/array grouping
support is not claimed: that needs a precise common typed comparison/admission
contract, including rejection of JSON. It must not be replaced by permissive
complete-row equality or frontend-side grouping. The whole Frontend goal remains
open beyond this connection unit.

## Verification and identity

Focused source tests compare two independent complete Program bodies and check
range preservation/removal, CTE and set composition, malformed syntax and the
existing Pipe scope/JOIN regressions. The normal packed corpus includes the new
cases; `--pipe-distinct-only` selects those same authored cases, not a substitute
implementation. Acceptance compares Named Result rows and Result.describe
columns/type/nullability, source read counts, stream completion, same-request Run
identity and read/reattach without extra provider calls. Refusals require zero
Run admission and provider I/O. A source-free scalar UNNEST case also excludes
private array/seed fields from equality and public output.

The grammar manifest changes. Values Run identity is derived independently from
the new grammar closure and the unchanged authored Program and dependency
preimages. The preceding grammar/Run vector is retained. Generated manifests,
document imports, canonical tests and package interfaces are updated by existing
generators. Old saved identity is not reinterpreted. Unit and Result Plan identity
are not changed by this surface grammar edit.

Final SHA, executed test counts, exact-source five-package digests and Local/HTTPS
results are recorded in the PR. No CI success, full backend conformance or
unexecuted packed success is implied by parser/checker tests. No merge is made.
