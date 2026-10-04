# Traverse node emission from public text

## Baseline and responsibility

Initial fixed source: `7bc0367339711cc85c80ce82a387a11e3f189ce3`, B's
Graph-row text input (#303). Its main dependency is
`d5f0802c93e2863b092aa8f1a9e9a7cc97b12c5b`, which includes C's common
traverse-node connection (#289) and definition rows (#299).
This unit connects existing named arguments; it introduces no new Graph
syntax, Carrier, execution owner, selector resolver or traversal kernel.

| Boundary | Existing owner | Frontend change |
|---|---|---|
| Parse named `traverse` and identify `start.from` as a reference | `query_syntax/sga_call.mbt` | Reused without another parser |
| Earlier DATA producer resolution | `query_program` ordinary lexical bindings | Resolve the selector to its emitted step; do not expand it |
| Numeric literal admission | `query_expression/lower.mbt` | Expose the existing numeric admission for named arguments |
| Fixed node output schema, identity, predicates, bounds and capacity | Common traverse checker and owner | Emit authored arguments unchanged; supply only the three output names for ordinary name resolution |
| Graph-to-Relation script call | B-owned Graph branch of `compile_query_script` | Pass existing known DATA inputs to the lowering module in DATA and terminal branches |
| Shared capture, CTE, assertions and Effects | D | Unchanged; direct installed selector Sources remain unconnected |

The Graph-call branch still refuses unsupported consumers before Run
admission. It does not synthesize a raw-key selector, presence proof,
uniqueness, ordering witness or successful Graph membership.

## Source and independent obligations

```aql
DATA n = SELECT 1 AS node_key;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)
);
DATA seeds = FROM g |> node_rows() |> SELECT id AS element;
FROM g
  |> traverse(start: {from: seeds, id: 'element'}, direction: 'out',
              min_hops: 0, max_hops: 1, path_mode: 'trail',
              emit: 'nodes', max_output_rows: 10)
  |> SELECT start_id, node_id, depth
  |> WHERE depth >= 0 |> ORDER BY depth |> RESULT nodes
```

The zero-hop expected row contains the same full typed identity in `start_id`
and `node_id`, and `depth=0`. The key is `[1]`, definition is `N`, and key
type is number. The expected domain is independently hashed from the authored
constructor and complete SELECT producer definition. A separate JSON control
uses Values, so its definition domain intentionally differs; neither domain
is taken from actual compiler output or a Result sample.

The full Program expectation in `traversal_nodes_test.mbt` is independently
authored, including all source-free seed, derive, projection, constructor,
selector and Result steps. The five packed positives cover that JSON control,
DATA selector source, an empty ordered-hop label list, an empty Relation
selector and a quoted DATA name. Seven refusals cover an unknown producer,
String-as-reference, missing selector column, unconnected path output,
invalid hop bound/path mode and an extra argument.

The existing packed application compares full ordered Result descriptions,
rows, stream completion, exact-request reuse and no added Run/acquisition on
retry/attach/read. Refusals retain zero admission/provider I/O and missing
request lookup. No Program is patched after lowering. The source module is
copied unchanged into the repository-external installation.

## Evidence and remaining scope

Local focused JS evidence before publication:

- Graph Program/checker cases: **8/8**, including five retained row cases and
  three traversal cases; the complete Program expectation and malformed-body
  refusals use the normal checker.
- Named numeric admission: **1/1**, covering fractional/trailing-point tokens,
  signed values, exact-integer ceiling, overflow and signed-zero rejection.
- Independent grammar/Run identity and manifest Node tests: **7/7**.
- Read-only compilation manifest, normative metadata, Workers and Node
  freshness checks pass; changed scripts parse and diff checks pass.

These are focused source/checker/identity checks, not packed execution or full
backend conformance. Packed Local/HTTP and required automatic CI remain
unverified until actual submitted-source evidence is recorded. No local full
Core, all-target, proof or performance campaign is required for this change.

The query rule bytes change the grammar manifest and dependent compilation,
Plan and Run identities under version 0.1. The new independently assembled
Values Run vector is
`sha256:cfd9395735fcb60fa33631944f54a49b5865dd7f55116bc26759b0ee72a037b4`;
the previous grammar/Run vector is retained with its original closure.
No Graph identity law, runtime storage or snapshot contract changes.

This first connection covers earlier DATA Relation selectors and explicit
node emission. Direct installed selector Sources require D's existing checked
capture/share boundary. Path emission remains another source-connection gap;
neither is redefined as a permanent language limit. Typed literal/list and
predicate selectors retain their common contracts but are not established by
the selected packed corpus. C's common JSON traversal evidence and B's source
execution evidence remain separate.

D's saved shared-CTE predicate counterexample is still independently unresolved.
It does not block this unit, and this unit cannot close it.

### Submitted-source identity follow-up

Submitted `1218b85be09e03ec9433a98e5264ed9e10c7563d` reached the
SGA normative-preimage assertion in [automatic CI 37175418951](https://github.com/actql/actql/actions/runs/37175418951).
The spec job failed because that separate assertion still pinned the previous
query-rule bytes; it is not a successful spec run or packed acceptance.
The traverse rule addition is the only changed input to this grammar closure.
Independent SHA-256 over the authored rule file gives
`65b078b5222afb74121a0785ffc2f3b3acba8642dbbb67e56477cb924fe20933`;
independent sorted JSON assembly gives grammar CID
`37e9fadf9ae65bc194ad17b790ce208450550defcdbfb8354ef3c5c9c0cf4f6d`.
The preceding grammar vectors retain their original rule bytes rather than
being recomputed under the new rules. Product output is not the oracle.
The corrected SGA preimage assertion and compilation-manifest tests pass
**6/6** through the bounded Node wrapper. No product or execution code changes
are included in this follow-up; fresh submitted-HEAD CI and packed execution
remain required.
