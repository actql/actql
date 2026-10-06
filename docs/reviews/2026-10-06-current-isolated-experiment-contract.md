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

An execution of the new source/policy image is required separately; the older
image does not establish current physical acceptance. Successful main comparison,
ordinary-PR acquisition and net runner savings remain unverified. No workflow,
selector, scope expansion, guard removal or Actions dispatch is part of this
change.
