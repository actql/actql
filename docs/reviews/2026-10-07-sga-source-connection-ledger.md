# Named SGA source connection ledger

Date: 2026-10-07. Owner: B. Source inspection baseline:
`ae1f273bc1174e50598d86ab932daa0bc28c5f4d` (main, including #844).
This is a documentation correction, not a new parser, common contract,
execution owner or backend acceptance campaign.

## Document defect and correction

`frontend-sga-surface.md` previously described every named-call example as
non-executable public source. That statement contradicts the installed Script
routes and existing operation-level acceptance records. For example, the
complete named `match_nodes` source in the match record reaches
`lower_script_graph_match_rows`, and the recorded external package campaign
checks its Named Result. Removing the structural envelope did not leave all
named calls disconnected.

The design now names the 15 connected calls and their Graph/Relation boundaries.
The migration document retains the whole adopted inventory and explicitly
distinguishes the four unconnected calls. Historical simple-Graph tests remain
historical; JSON support, parsing, lowering, checked admission and successful
public execution are separate kinds of evidence.

## Source inspection evidence

- `query_script_program.mbt` routes DATA and terminal Graph queries through
  `lower_script_graph_calls` / `lower_script_graph_rows`. Constructor bindings
  use the sole Graph model; they are never fabricated as Relation inputs.
- `sga_script_program.mbt` handles normalize, union, subtraction, Subgraph and
  Delta application while retaining Graph metadata.
- `graph_rows_program.mbt` additionally routes row Bridges, named node/edge
  match, diagnostics, comparison/difference and explicit traversal emissions.
  Ordinary Relation processing follows; a second Graph call is refused.
- The corresponding helper files retain authored argument bodies, producer
  references, selected fields and common checker ownership. The design table
  links to those files rather than a retired structural decoder.
- Neither route has a `reach`, `shortest_path` or `graft_graph` branch.
  `NamedGraphCall` DATA generators remain an explicit `UnsupportedGraph`
  boundary, including `mean_graphs`. This statement concerns current source
  routing; it does not independently establish their common Program support.

## Retained operation-level records

These links identify existing evidence and restrictions, not new executions
of this baseline. A historical document may retain an earlier provisional
name or failed attempt; do not interpret it as a current alias or fallback.
Exact SHAs, manifests, receipts and later integration outcomes stay in their
original records and PRs.

| Current route | Existing record / independent public fixture |
| --- | --- |
| node_rows / edge_rows and selection | [Rows](2026-10-04-graph-row-source-inputs.md), [definition/label selection](2026-10-04-graph-row-selection.md), `graph-row-source-input.mjs` |
| traverse nodes / paths | [Nodes](2026-10-04-traverse-node-source.md), [paths](2026-10-05-traverse-path-source.md), `graph-traverse-source-input.mjs` / `graph-traverse-path-source-input.mjs` |
| match_nodes / match_edges | [Named match](2026-10-05-graph-match-source.md), `graph-match-source-input.mjs` |
| degree / graph_bounds / components | [Diagnostics](2026-10-05-graph-diagnostics-source.md), `graph-diagnostics-source-input.mjs` |
| graphs_equal | [Equality and separate common order gap](2026-10-05-graph-equality-source.md), `graph-equality-source-input.mjs` |
| graph_diff | [Difference](2026-10-06-graph-difference-source.md), `graph-difference-source-input.mjs` |
| subgraph | [Subgraph](2026-10-05-subgraph-source.md), `subgraph-source-input.mjs` |
| union_graphs / subtract_graphs | [Union](2026-10-06-graph-union-source.md), [subtraction](2026-10-06-graph-subtraction-source.md), corresponding `graph-*-source-input.mjs` fixtures |
| apply_graph_delta | [Delta source and generic JSON dependency](2026-10-05-graph-delta-source.md), `graph-delta-application.mjs` |

The source fixtures live under `scripts/fixtures/` and the existing public
driver includes their relevant selections. This correction does not bulk-mark
their examples as executed at the inspection baseline, change any expectation,
or certify Cloud, Wasm/native, full Graph coverage or pushdown. In particular,
the equality ORDER gap and wider traversal selector acquisition remain visible.

## Verification scope

Only the changed Markdown links, source targets and diff formatting need local
validation. Normative query text, grammar, Program schemas, generated pins,
independent vectors, runtime packages and product files are unchanged. No build,
packed run, full Core or manual CI rerun is necessary for this correction.
Required CI for the submitted documentation SHA is recorded separately in its PR.

The changed three-file Markdown local-link/source-target scan found no missing
targets or trailing whitespace; `git diff --check` passed. These are document
checks, not new execution evidence for any operation.
