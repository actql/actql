# Any-direction Graph path acceptance and the installed output ceiling

The initial package campaign used source revision
`d785acb32ea1d248419ba8e1e802ee7c56a2d695`. Its normal five-package manifest is
`/private/tmp/actql-b-any-direction-d785acb32-pack/packed-client-packages.json`.
The retained public receipt is
`worktrees/.codex-scratch/public-query-evidence-esdk8n/summary.json`.
Nine Local positives reached Named Result; the next, bounded WALK, failed.
Later positives, refusals and Graph HTTPS were not reached in that campaign.

## Preserve the mathematical expectation

The original five-node, six-edge fixture has one zero-hop path, six one-hop
paths and thirteen two-hop WALK paths: twenty rows of the declared depth
projection. This expectation remains in `graphAnyDirectionOverCeiling`; it
has not been changed to the fourteen rows observed before failure.

The installed provider first retains the complete path Relation, including
`start_id`, `end_id`, `node_ids` and `edge_ids`, before the SQL projection.
There are three identity occurrences at depth zero, five at depth one and
seven at depth two, totaling `3 + 6*5 + 13*7 = 124` occurrences.
Each declared JSON identity contains a 71-byte domain CID, a one-byte element
definition name, the keys `definition`, `domain`, `key`, `key_types`, `kind`,
and the string `number`. These strings alone require at least 110 bytes per
occurrence, even before punctuation, key values and path column names:
`124*110 = 13,640 > 10,000`. This lower bound is independently authored, not
computed by the product value meter or from sampled output.

`client_program_selection.mbt::selected_graph_limits` installs a 10,000-byte
value/text ceiling. `local_sga_provider/graph_pipeline.mbt` passes that
ceiling to the traversal output owner. The refusal therefore has a real
installed resource boundary; it is not evidence that any-direction WALK is
unsupported or that a frontend condition disappeared. Neither that ceiling
nor the total Host memory budget is raised.

## Distinguish public evidence from diagnosis

An external two-case probe submitted both the independently authored complete
JSON Program and the original text through the public SDK. Both failed.
`run-uvAQfC` used the unmodified tarballs. Diagnostic-only observations then
showed the following chain:

1. `TraversePathsOutput(CaptureLimit)` while retaining path output;
2. provider mapping to `Execution(InputSet)` and `MoonBitHostFailure`;
3. `StrategyNotComplete` during attempted publication;
4. the public failed Run with `ACTQL_E_UNPUBLISHED_RUN`.

Attempt `run-FgqHuO` observed the exact traversal issue at progress 14 and
work 9,031. Attempt `run-3Xr0VH` observed the output buffer with fourteen rows,
row ceiling 100, node usage 743, text usage 9,944, and work usage 10,687;
its ceilings were nodes 10,000, text 10,000 and work 100,000. The failing
append is not evidence that those partial rows were published: the Run
failed without a Named Result.

These attempts are under this worktree's `_build/local-checks/attempts`.
They used a disclosed external adapter logging overlay; the final two also
used the same-source unminified runtime from the normal package producer
with observation-only additions. They establish diagnosis, not pristine
packed acceptance. The original runtime, overlay notes and failed Stores
remain in `/private/tmp/actql-b-any-walk-d785acb32-diagnostic`.

## Acceptance correction

Normal positive bounded cases now use one node and two independently keyed
self-loops. Their independently enumerated depths are:

| Mode, bounds 0..2 | Depths |
|---|---|
| WALK | 0, 1, 1, 2, 2, 2, 2 |
| TRAIL | 0, 1, 1, 2, 2 |
| ACYCLIC | 0 |

These cases detect parallel-edge collapse, repeated-edge handling, the
zero-hop path and accidental double counting of a self-loop in `both`.
The original graph remains in the fixed-hop, reverse-direction, property
and NULL positives. Its twenty-row bounded WALK input remains registered
as an execution-capacity failure, preserving its source, parameters and
mathematical expectation. Failure acceptance requires no published Result
and stable failed Run identity on attach and resend; it does not count as
a successful twenty-row traversal.

The fixture registration check passed 5/5 (`focused-test-Jcgtql`). This is
not Local/HTTPS acceptance of the corrected corpus. That public acceptance
and the exact submitted revision's required CI must be recorded separately.
