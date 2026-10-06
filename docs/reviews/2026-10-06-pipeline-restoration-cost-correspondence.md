# Pipeline restoration cost correspondence

Baseline: main `0e810449cc1a5d330fb244d7651617366ef135f3`.
This unit fixes the existing read-only artifact consumer. It does not change
campaign execution, reuse authorization, workflow scheduling or source closure.

## Missing boundary

`mutations.mjs` already records three independent replay boundaries: mutated
source, pristine source, and restored mutable bytes executed by a new owner.
`inspectMutationPart()` requires the last boundary's three targets and original
source correspondence. The offline `projectCampaign()` consumed only mutated
and pristine receipts and their action durations. It could therefore report
complete selected phase evidence while ignoring post-restoration costs and
receipts. No existing campaign is removed or newly required here.

The consumer now includes `postRestoreReplayMs`, `postRestore.observations` and
`postRestore.executions`. These remain a separate `post-restore` phase; they are
not added to pristine replay or to enclosing job wall time. Missing duration,
target or verified receipt leaves selected evidence incomplete. Observation
values participate in the workload/oracle fingerprints; occurrence IDs alone
do not. Capacity's separate contract remains unchanged.

Regressions exercise negative duration, omitted target/phase/receipt, substituted
receipt digest and empty restoration cases. The actual offline stored-ZIP CLI
returns nonzero even when every other phase contains valid observations.

## Retained original and read-only replay

Historical main run: <https://github.com/actql/actql/actions/runs/37198759659>,
attempt 1, source `7c4bcb61b8d7e7c37b4be8eb986e1811842d345b` (2026-10-04).
Artifact ID `11302307982`, name
`relation-pipeline-L-M0-37198759659-1-7c4bcb61b8d7e7c37b4be8eb986e1811842d345b`,
ZIP bytes `3973399`, SHA-256
`8ec85470b25eb7af21965816d9fe9307ee1e86cad6585b7fa98f1a1004b61a04`.
The existing bounded ZIP reader checked those actual bytes. Its `evidence.tar`
was read without importing/executing contents or extracting paths to the host.

The exact `fixed-mutations-L-M0.json` bytes are retained losslessly at
`evidence/2026-10-06-pipeline-main-37198759659-L-M0-fixed.json.gz`.
Uncompressed: `3241184` bytes, SHA-256
`5ce6b98807105317e43a3496e08045ff403afad2081d9e8dfeca61ea146d9e22`.
The focused original-replay test verifies that identity before using the actual
consumer. It exposes 12 formerly omitted new-owner receipts (36 total) and
`121772.41893600009` ms of post-restoration action time: JS `24189.233001999906`,
Wasm `29196.78731400019`, Native `68386.39861999999` ms.

This is replay of historical evidence, not newly executed mutations at this
candidate SHA. Embedded receipt digests and new-owner source correspondence are
checked; the complete archive log/build custody and authenticated final gate
remain separate from this projection test. Originals are not rewritten.

## Selecting the next reduction target

Existing read-only collector invocation:

```sh
env -u GH_TOKEN -u GITHUB_TOKEN node scripts/ci-evidence.mjs actql/actql \
  --runs 37198759659,37199235874 --json
```

Its lossless output is retained at
`evidence/2026-10-06-ci-cost-two-successful-runs.json.gz`; endpoint/field identities,
attempts, sources, runner labels and completeness are preserved. These completed
2026-10-04 runs are historical samples, not measurements of current main.

| Sample | Total distinct job seconds | Observed job wall span | Session JS mutation step | Assigned pipeline mutation steps |
| --- | ---: | ---: | ---: | --- |
| main `37198759659:1` | 14099 | 2483 s | 72 s | 870 s / 770 s |
| PR `37199235874:1` | 13754 | 2142 s | 72 s | 789 s / 821 s |

The PR sample source is `d16e5c8e7da84000b00cbdf626884d6c2bc3ed8b`. Sources/events
and observed configurations differ. These rows prioritize investigation, not a
before/after speedup estimate, queue-time claim or net savings. Pipeline mutation
is the next deterministic-family candidate; costly packed public/recovery steps
are not eligible merely because they dominate wall time. Before broadening reuse,
close that family's complete inputs and compare its scientific observations and
restoration obligations. Current-input changes must still trigger fresh execution.

The missing restoration phase must be included in any future ROI estimate.
Healthy/mutant workspaces already are isolated; this does not reimplement them.
No net runner saving or task completion is claimed by this cost repair.
