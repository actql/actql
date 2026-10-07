# Bounded Graph path modes: connect the existing traversal contract

Baseline: `f2dc744ddbabe2ed6887961be2961881338a2847` (main).

## Counterexample and contract

The parser rejected a finite anonymous quantified edge unless MATCH selected
ACYCLIC. This also rejected the default WALK mode:

```aql
DATA n = SELECT 1 AS id;
DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst
  UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES)
  EDGE TABLES (e AS E KEY (key)
    SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N
    LABEL R NO PROPERTIES)
);
FROM GRAPH g
  |> MATCH p = WALK (:Node)-[:R]->{2,2}(:Node)
  |> SELECT PATH_LENGTH(p) AS depth
  |> RESULT paths
```

Independently keyed self-loops produce four two-hop WALK paths, two TRAIL paths
and no ACYCLIC path. Projection preserves that multiplicity: the four WALK rows
are all `{depth: 2}`, not one DISTINCT endpoint or depth row.

The existing grammar already permits the bounded quantifier with every admitted
path mode. `docs/spec/language.md`, requirements
`traverse.closed-modes-and-filters` and
`traverse.minimum-eligible-node-depth-and-order`, already define finite
homogeneous bounds for WALK, TRAIL and ACYCLIC. `check_traverse` admits those
modes with literal finite bounds; `keyed_graph_program.mbt` already lowers each
mode and both authored bounds to that same operation. The existing path kernel
tracks edge identity for TRAIL and node identity for ACYCLIC. No common owner
or mode semantics need changing.

The selected external reference is
`google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`,
[Graph patterns](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/graph-patterns.md).
The [Google Graph pattern reference](https://docs.cloud.google.com/spanner/docs/reference/standard-sql/graph-patterns)
also distinguishes bounded edge quantification and restrictive path modes.
This connection does not claim implementation of every quantified subpath,
group variable, search prefix or unbounded form.

## Change and preserved boundaries

Remove only the parser's ACYCLIC-only gate and its now-unused private mode
argument. Keep one homogeneous finite quantified edge, nonnegative minimum,
positive maximum, minimum no greater than maximum, and the current refusal of
quantified internal edge variables/predicates. Invalid or unsupported shapes
keep the typed Graph-shape diagnostic and a source position. Common checker,
capacity, traversal, Result and publication owners remain unchanged.

The new ordinary Program test is independently written and compared in full
for all explicit modes and the default. Both expected and generated Programs
pass the ordinary checker. The Graph selector is a shared producer reference;
the frontend neither reacquires its Graph nor creates an endpoint-tuple graph.

The public fixture adds an independent JSON control and eight complete authored
text cases. `{2,2}` detects mode and parallel-edge multiplicity; `{0,2}` with
explicit ORDER BY detects preservation of both bounds and the zero-hop path.
Its expected depths are WALK/default `[0,1,1,2,2,2,2]`, TRAIL `[0,1,1,2,2]`,
and ACYCLIC `[0]`. Twelve refusal cases retain unsupported bindings/predicates
and invalid bounds across the three modes. They use the ordinary packed corpus
and its existing `--graph-source-only` selector, without a separate harness or
post-lowering Program patch.

## Verification checkpoint

- Before the product fix: focused JS 1/3 passed; bounded WALK failed parsing
  both directly and through complete source compilation.
- After the fix: focused JS 18/18 passed, including independent full Programs,
  ordinary checking, existing Graph source modes and matched path consumers.
- Fixture request identity and corpus registration: focused Node 2/2 passed.
- Pristine submitted-SHA packed Local/HTTPS acceptance and submitted-SHA CI
  remain separate evidence, to be recorded in the PR body after execution.
- Full Core, Wasm and native runtime acceptance have not been run locally.

Grammar, normative bodies and machine contracts are unchanged. No canonical
body/CID or generated pin change is needed: newly admitted text uses an already
defined ordinary traversal. The initial frontend adoption ledger is historical
coverage, not evidence of execution on this submitted SHA.

Retained pre-fix and final logs are
`/private/tmp/actql-b-bounded-modes-before.log` and
`/private/tmp/actql-b-bounded-modes-final.log`; bounded wrapper receipts live
under this worktree's `_build/local-checks/attempts` and `_build/focused-evidence`.
