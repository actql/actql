# Current isolated Session experiment contract

## Actual blocker and scope

The isolated reuse predicate still fixed experiment digest
`3611a80f4e044eaf65fc452cc914f25c0c48b80b6c2ec09c3a5a2829f5e46f7b` from
`2034069ff171d09684b43cba21e9e9552dc3aa69`. The actual current ten-file experiment
cohort has digest
`5fb3fc315c59e0c88123cc6824e9634729f84e81824ab18cf323e22c11f37a14`.
Even under the unchanged reviewed host/kernel/toolchain conditions, the current
cohort therefore remained open. This is a legitimate refusal by the existing
predicate, not a need to discard input identity.

Refresh only the finite experiment review at
`8e090492aa323836bca86871602b8dd6109f5d4f`, which adopts main
`0e121e64b688064d1cabbee26bd35126e94b586a` into the local execution branch.
Keep the single current contract. Earlier experiment digests remain unreviewed;
there is no compatible-old-cohort list or automatic promotion of new fixtures.
Keep the existing host image, kernel, toolchain, CPU input identity, isolated
environment, immutable image inventory and Actions authentication conditions.

## Effect review of the changed experiment inputs

Relative to the prior review, exactly two of `isolatedExperimentPaths` changed:

| Input | Change | Effect on the thirteen selected experiments |
| --- | --- | --- |
| `src/query_integration/local_managed_group_wbtest.mbt` | The Group fixture follows actual selected tasks for split aggregates, preserves child/consumer holding checks, adds the private-port-close regression and reserves the fifth output in split cases. The shared task-start helper adds a task number to its failure diagnostic. | Group-only cases are not selected by any mutation contract. The shared helper still uses the same existing execution owner and return behavior. Changed diagnostics are not scientific outcome identity; assertion detection, intended suite/filter and restoration remain checked independently. No external I/O, random/clock input or additional execution callback is introduced. |
| `src/query_integration/physical_graph_wbtest.mbt` | Adds deterministic mixed-input nearest/as-of graph tests and makes `captured_graph_fixture`'s preparation budget an optional parameter. | The added tests are outside the set/Nest filters. The shared helper's default remains 1,000, so the existing selected calls retain their preparation condition. The added branches use existing checked planning/provider functions and literals; no external service, ambient configuration or process scheduling observation is added. |

The other eight reviewed files, all thirteen independent IDs/sites/suites/filters,
the mutation edits and their assertion/restoration criterion are byte-identical
to the preceding review. Product-source changes remain separate action inputs
and require fresh execution; this review does not certify those changes or make
old receipts applicable to new source.

This is a source-level finite effect review under the existing declared trusted
Node/Moon/OS semantics. It is not universal implementation refinement or a proof
of runtime determinism outside the stated contract.

## Existing physical evidence and refusal checks

The unchanged public original
`evidence/2026-10-06-local-isolated-session-8bbe08fca.json.gz` records thirteen
intended running-assertion detections and byte-exact restoration at
`8bbe08fca045be6c00a64eb5a68889295082c67c`. Its uncompressed SHA-256 is
`52d9e7931fe6a3b14d2b00a51094f4f83f4161363440360ab22b207d33afb6aa`.
Each of the ten reviewed input files has exactly the same bytes/mode/length in
that real image and in the new review revision. The new regression checks this
correspondence and replays its original logs through the scientific consumer.
The original revision/authority/receipts are not rewritten. That local image
still fails the Actions host/kernel authority conditions and authorizes no reuse.

Refusal cases retain changed fixtures, old experiment bytes, toolchain changes,
another host image/kernel and changed CPU observations. The historical physical
originals remain accepted only at their actual Git source; later product inputs
cannot borrow them. Local evidence is not an authenticated protected-main origin.

## Current-source local physical acceptance

At clean source `b34f6e5445b731584729a1f8c09ec8c2404ccde6`, the existing legitimate
local entrance built immutable scratch image
`sha256:2fe53665521475b06b49132da38a88296767dc2d682c3633f941be2ce627de73`.
Its 3,837 staged source files include 3,806 selected product-source paths.
All thirteen registered experiments produced their intended running assertion
failure (`failureCount: 1`); the original source bytes were restored and the real
scientific consumer accepted the result. The independent image inventory and
consumer confirm that all four installed core build metadata files remain
absent. The existing owner closed its container and image successfully.

The complete original, including input manifest, immutable image definition,
arguments, thirteen raw assertion logs and restoration observation, is retained
unchanged at `evidence/2026-10-06-local-isolated-session-b34f6e544.json.gz`.
Uncompressed SHA-256:
`9a2e83e9be1396bedc7410fa11b48a8e8942c39f80098f7baa4b238969454c04`;
gzip SHA-256: `e957c96702376edfc1c6e5b7e8fcb4878b0ddc70bf964d0a3f5dc56693501bcc`.
The replay regression checks its actual revision and bytes through the real
consumer and refuses changed source, missing logs, compile-only failure and
failed restoration. Publishing the evidence does not rewrite its source SHA.

Executed command (Linux Moon installation is the retained pinned local input):

```sh
node proofs/ci-evidence/local-isolated-acceptance.mjs run \
  --engine /usr/local/bin/docker \
  --builder-image sha256:e894118949319b479bfc3e16e545cb2f85b7a2194aa86ea9cd4e29538f2b13c3 \
  --moon-home /Users/t14i/workspace/20260822/worktrees/actql-local-isolated-session-acceptance/_build/local-isolated-toolchain/moonbit
```

Bounded receipt `run-M878DS` completed with exit 0 and released its locks.
Preparation/build/execution/inspection/close took respectively
23,889/19,018/160,721/1,305/730 ms; overall guarded elapsed time was 214,947 ms.
These are local observations, not a controlled before/after savings comparison.
The preceding `run-ZCNbNO` failed at image build with Docker EOF, before any
experiment. Its custody, input manifest and supervisor log remain retained;
473 MB of owned regenerable staging was reclaimed. After normal OrbStack start,
the missing failed image was confirmed and the same command succeeded.

This local physical evidence retains `reuseAuthorized: false` and its lack of
Actions provenance. Successful authenticated main comparison, ordinary-PR
acquisition and net runner savings remain unverified. No workflow, selector,
scope expansion, guard removal or Actions dispatch is part of this change.
