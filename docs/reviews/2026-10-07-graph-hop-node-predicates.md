# Fixed-hop Graph node predicate connection

The adopted baseline is `f39590a3b8f71340e6ddaa4c7e3de6c1bd7f41d5`.
This unit connects an existing common operation contract; it does not introduce
an evaluator, identity conversion, property-presence evidence or compatibility
route. Anonymous edge predicates remain the separate PR #821 unit.

## Counterexample and independent control

```aql
DATA g = PROPERTY GRAPH (
  NODE TABLES (objects AS N KEY (id) LABEL Node PROPERTIES ALL COLUMNS)
  EDGE TABLES (links AS E KEY (key)
    SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N
    LABEL R NO PROPERTIES)
);
FROM GRAPH g
|> MATCH p = WALK (a:Node WHERE id = 1)-[:R]->(b:Node WHERE b.payload.score > 10)
|> SELECT PATH_LENGTH(p) AS depth
```

The handwritten complete Program in `graph_hop_node_predicate_test.mbt`
passes ordinary checking. Against the unchanged frontend, the valid source
fails with `UnsupportedGraph`; the focused baseline has one passing control
and two failing source tests. Earlier attempts with incomplete test context
metadata are test-authoring failures and are not product counterexamples.
The valid baseline evidence is `_build/focused-evidence/focused-test-fLA3ZS`.

The current common contract already admits `traverse.hops[i].node_where`.
Starting-node conditions remain `match_nodes.where`. Each fixed reached-node
condition is attached to the corresponding authored hop. Incoming direction
selects source definitions; outgoing selects target definitions. Authored edge
labels determine the static edge candidates. Runtime rows never narrow them.

The frontend resolves property names through existing nullable-property
expression lowering. It does not validate presence/types or manufacture NULLs:
the common checker checks all candidate definitions. A reached-node label is
admitted only when every reached static definition carries it. Other label
filters stay explicitly unsupported, rather than becoming property equality.

## Explicit remaining boundary

For `A -> B -> C`, with scores `0, 0, 20`, an authored quantified terminal
condition `A-[]->{2,2}(WHERE score > 10)` must retain the path to C. Common
homogeneous `node_where` instead filters B and C and would prune B. The frontend
continues to reject quantified terminal conditions with `UnsupportedGraph`.
It must not map this endpoint-only condition to every-hop filtering. Supporting
that form needs a common terminal predicate or terminal binding/filter boundary;
there is no frontend path evaluator or implicit unrolling in this PR.

Exporting reached-node variables as element/property values and named edge
bindings are also unchanged separate boundaries.

## Verification

- Focused JS: 24/24, including the complete independent Program, local/quoted/
  anonymous receivers, two distinct hop predicates, incoming direction, NULL,
  reached-definition scope, missing-property checking, foreign receivers,
  quantified rejection and retained existing Graph lowering callers.
  Evidence: `_build/focused-evidence/focused-test-1yL8uW`.
- Focused Node: 3/3 dependency/fixture tests.
  Evidence: `_build/focused-evidence/focused-test-y5bLbR`.
- New public corpus: 13 positive cases and 8 pre-admission refusals, including
  two independently authored JSON controls. Both the focused public selector
  and ordinary packed corpus include them; expectations are not compiler output.
- Fresh packed Local/HTTPS execution, required CI and other targets remain
  unverified at this preparation revision. No full Core/proof/performance gate
  has been run for this unit.

## Public fixture preparation correction

The first normal package set was produced at
`fd0a8e023dc216970b01377d1764dc25cebc6773`. Its Local JSON controls and the
retained nine starting-node cases passed. The first new source case was rejected
in checked DAG preparation with `GraphIssue::TaskLimit`: ten unrelated UNION
branches used to construct the five node/edge rows exceeded the standard 32-task
limit. This is not evidence of an incorrect node predicate evaluation.
The complete failed receipt is retained at
`worktrees/.codex-scratch/public-query-evidence-UmPG5X/summary.json`.

The fixture now constructs the exact same rows and types with the existing
typed parameter/UNNEST path. All expected rows, column contracts, nullable
cases, JSON controls and refusal obligations are unchanged; no Host limit or
Program admission rule was changed. The normal preparation bridge accepts
both the JSON control and corrected source. That preparation diagnostic does
not replace the pending Local/HTTPS execution acceptance.

## Integration checkpoint

The corrected source corpus completed Embedded Local and HTTPS at
`7e5aee197a9a9027b7c22921b4fbc9abbcd037e5`: each mode passed 22 positives and
13 pre-admission refusals, including Named Result rows/description, column
order, request replay/reattachment and unchanged Run/I/O counters on refusal.
The successful receipt is
`worktrees/.codex-scratch/public-query-evidence-AGd4DZ/summary.json`;
its evidence is complete and its owned installation artifacts were removed.
Five normally prepacked package digests are retained in
`/private/tmp/actql-b-hop-node-7e5aee197-pack/packed-client-packages.json`.

Main `735ac73c5519753f77de31c26d6233ffc015c088` was then merged normally.
The two conflicts were `keyed_graph_program.mbt` and the packed driver's
fixture-copy list. Both edge and node predicate connections are retained,
using main's shared `keyed_constraint` helper. The added combined predicate
case must return no rows: edge key 10 reaches score 10, which fails score > 10.
Dropping either the edge or node condition incorrectly produces a row.

At merge revision `d58c96af7ff37611d0aeffe578fd2217452601c9`, focused JS
passed 32/32 (`focused-test-DcZFrd`), and focused Node passed 4/4
(`focused-test-D90sdG`). The combined public corpus now contains 39 positives
and 21 pre-admission refusals per mode: 14 new fixed-hop node cases, 16 retained
edge cases and 9 retained start-node cases. Fresh packed execution of this
integrated revision and required hosted CI are not established by the earlier
7e5aee197 execution. PR #826 records the subsequent exact-head result separately.
