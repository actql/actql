# PR #63 integration with Graph Result order evidence

This is development evidence, not acceptance of the integrated branch.

| Input | Fixed source |
| --- | --- |
| Frontend and public Client (#63) | `2e21a039245ba681a90a7f18a3fd6e2797265107` |
| Graph provider and Result order (#92) | `682ebfb4f45943dc30480d6263fe9b173620d61c` |
| Isolated merge, before this evidence record | `a345d3f17d5129bba3570d1bb6b2cbab30d604fc` |

The merge preserved the declared Result order. Its two test conflicts were
resolved by requiring exact published edge-row order and by retaining #92's
rule that a nullable Graph edge label is not a Relation candidate key.
The merged code built with the pinned MoonBit toolchain. Focused JS tests
passed: `relation_results` 97/97, `pipeline_typing` 335/335, and
`relation_evidence` 20/20.

The clean packed installation was generated from the merge source with
`npm run build:runtime-packages -- local-node run-host-core` followed by
`node scripts/test-packed-public-query.mjs`. Its Local phase stopped at
`mean-graphs`: the public Client returned `ClientProgramRejected` before
Run acceptance. A direct common preparation of the independently authored
JSON Program identifies `stage_results.LocalProgramIssue.Order` /
`relation_results.UnresolvedOrder` at `stages[0].results.edges`.
The complete run's logs are in the workspace evidence directory
`worktrees/.codex-scratch/public-query-evidence-wXGVGz`.

The targeted command
`ACTQL_TEST_SGA_CASES=graphs-equal,diff-apply node scripts/test-packed-public-query.mjs`
passed `graphs-equal` through the packed Embedded Local Named Result, then
rejected `diff-apply` before Run acceptance. Direct common preparation of
its JSON Program reports the same `UnresolvedOrder` at the edge Result.
The targeted run's logs are in
`worktrees/.codex-scratch/public-query-evidence-cN2jet`.
With `ACTQL_TEST_SGA_CASES=graphs-equal`, the independently authored rows,
normal delivery end, request lookup, attach and reread passed through both
packed Embedded Local and HTTPS Remote. The native CLI representative case
also passed. That run's logs are in
`worktrees/.codex-scratch/public-query-evidence-te5pYm`.
All three runs used the same packed `run-host-core` SHA-256
`3d6b5085121b69a084fed07a39695d5188cc4cafbd586e025a54969079351dac`
and `local-node` SHA-256
`46de3f26ad500efb1cf24224f48df960e20900e2daa70bb097302d23eb7782bb`.
Temporary installed packages and Stores were removed after logs and digests
were retained.

The relevant boundary is `src/relation_evidence/sets.mbt` and
`src/publication_order_policy/plan.mbt`. #92 removes the nullable edge-label
candidate-key exception. The existing language contract requires an eligible
key or a retained total sequence to complete ties in an authored
`order_by`; the projected-field fallback is reserved for Results without
authored order. The Graph row contract also states that projection alone does
not prove row order or unique keys. A physical edge enumeration or the
projected-field fallback therefore cannot be relabeled as a retained order
witness. Both failing fixtures explicitly order their edge Result by
`src`, `dst`, and nullable `rel`. The Frontend emits the expected Program;
the authored JSON Program fails at the same boundary. The order terms and
expected rows must remain intact. Do not drop `order_by`, sort rows in the
Frontend, or treat a nullable label as a non-null Relation key.

The owner of the Graph order evidence should identify a valid existing witness
with its checked producer and runtime obligation, or a contract-compatible
correction at this boundary. If the current contract cannot represent the
necessary proof, the missing public meaning must be decided explicitly before
changing the checker. After a fixed SHA is
available, rerun the original eight named SGA sources through both packed
Local and HTTP. The earlier #63 source
`2e21a039245ba681a90a7f18a3fd6e2797265107` passed 8/8 with the
previous Graph provider SHA, but that result does not validate #92's new
ordering semantics.
