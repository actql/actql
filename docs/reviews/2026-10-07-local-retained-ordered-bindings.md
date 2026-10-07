# Public retained ordered bindings

## Completion unit and integration

This unit closes the public Plan encoding gap recorded by #731. It follows
`f9b78149fb9ff14b562e850cd6fc4a0efd3cbf03` without recreating its work.
Main `8f84de5a69c5e4534634fa0faec0852a6f99b112` was normally merged at
`873858cbbc725debc57e4d32f392385df3be98de`. Local changes were preserved in
a scoped stash and restored without conflicts. Current Graph contracts and
the parent's checked metadata owners remain authoritative. During validation,
#731 reached main at `12c56b6d67f233d735664bb59786dd13b86e1d97`.
Main `6a083adc55fdf91a3c3f105393ce4eb870b285d7` was then normally merged,
including G's allocation observer/census correspondence and full USING scope.
No conflict or unmerged parent remains; the PR targets main.

The ordinary Program is a Values producer, ordered derive and Select,
followed by two independent consumer tasks. Ten authored bindings shadow a
513-unit input name, relay the new slot, derive value from that relay, then
evaluate seven literal outputs. Independent expected published rows are
`[{"id":1,"value":7},{"id":2,"value":null}]` for each of `published`,
`consumed_a` and `consumed_b`. This is not an internally assembled Plan.

## Former refusal and minimal connection

The same ordered fixture previously passed checking but failed normal submit
with `RunHostTaskCompilationRejected` and typed cause
`TaskGraph(Fragment(Pipeline(Encoding)))`. Its Client projection was
`SubmissionUnknown` / `ClientHostFailure`. The retained diagnostic is
`run-4xWwtS` / `focused-test-FX05QG`; it is pre-fix working-tree evidence,
not evidence for this submitted revision.

Raw lowering still refuses OrderedBindings without registered params.
`lowering_relation.emit_sequence_node` factors the unchanged per-step
serializer, leaving that refusal intact. The public compilation owner now
uses selected registry, Values and ordered bodies generated from
`spec/contracts/actql-aoa.json` and its selected registry by the existing
`lowering-registry-vectors.mjs` generator. It admits those actual bodies,
prepares references from the originating checked kernel and calls
`execution_relation.emit_ordered_kernel_node` through the existing
OrderedParams owner. No adapter assembles a reference table or fabricates
evidence. Admission and reference construction have finite limits.

Registered-body admission uses the existing finite client runtime profile,
separate from the caller's output writer budget. A small valid Plan must not
be refused because its selected contract body is larger. An independently
assembled complete Plan wire fixes its exact output limit and one-short
refusal. This exposed a real coupling in the initial implementation:
`run-Bfx6qY` / `focused-test-RdgbpZ` passed 3/4 and rejected that exact bound.
After separating admission, all four cases passed (`run-lpmcCp`,
`focused-test-Lu0hbd`). No runtime work/workspace budget is changed.

The logical node retains its exact checked input edge. Existing selected-task
remapping binds that edge to the task's input, without changing prior slots.
Fragment-local emission still uses its canonical `input` edge and unchanged
source/graph identities. Logical Plan construction is not runtime permission:
`client_local_host/client_sequence.mbt` still independently admits installed
contract bodies and uses `prepare_runtime_fragment` to regenerate and verify
the complete occurrence, root, context and limit evidence before execution.
The existing bounded expression driver, cumulative charges, roots, retained
output, publication and cleanup owners are unchanged. There is no fallback,
new evaluator, scheduler or ledger. Nonordered serialization is unchanged.

## Executed evidence

Focused JS tests passed 18/18 (`run-10PvEz`, `focused-test-33ZaPY`):

- Public ordered task and source-free Values compilation succeeds while the
  same checked sequence still fails raw ordered serialization.
- A fused Values prefix preserves its checked edge. A retained producer
  input is remapped without rewriting the independently specified prior-slot
  table. Finite contract admission and insufficient output bounds refuse.
- Existing ordered params, fragment admission/execution and ordinary Client
  Program cases pass. The independent fragment graph CID remains
  `sha256:893748c3e83ec1067e7649cf789f2d73ed60c313d9b334635a6b2e6dd6774623`.

Two earlier batches exposed new-fixture task-count assumptions, not product
failures: a source-free prefix is fused into one task, while an external
producer has a separately selected derive and projection. Expectations were
corrected to those existing task boundaries; no selection policy was changed.

Targeted Node tests passed 5/5 (`run-ektweF`, `focused-test-qCviPP`). The
new public ordered case and unchanged map/field controls use the ordinary SDK
and Embedded Local Host with a real retained Store. They check all three
explicit Named Results, values/order/schema, independent consumers, request
reuse without additional dispatch, delivered cancellation after positive
progress, input custody before physical-stop confirmation, no partial
publication and empty retained snapshots after cleanup. The public barrier
is not claimed to be inside a later binding; the existing private
borrowed-binding fixture covers that narrower boundary.

The registered-body test compares generated production wires with selected
contract bodies. Removing the ordered public evidence role makes the resource
gate fail. Existing exact/one-short work/workspace, later-binding stop and
one-time cleanup evidence reaches the unchanged bounded owner; this unit
does not claim a new independently executed public budget matrix.

These are working-tree checks. The PR records clean submitted-SHA checks
separately. JS runtime dependencies were rebuilt from this integrated source
and their generated bundles checked; bundles remain untracked. Public API,
Node Host and Workers fixture freshness are checked through their existing
generators. No independent expected row or CID was regenerated from product
output.

At clean intermediate SHA `96afa381cfa4f85c37e898dae6decef1e5744667`,
the integrated JS caller/resource selection passed 17/17 (`run-SWtGZ0`,
`focused-test-BpQ5Re`). A broader targeted Node selection passed 4/5
(`run-nmfQa8`, `focused-test-WOIkK9`): both public ordered/map Host cases,
the evidence-removal test and generated registration passed. The existing
historical registry reconstruction failed. Its function was unchanged from
main; it removed one current Graph operation and replaced two pins, which
cannot restore the older domain/signature preimage after the Graph migration.

The historical registry is now frozen verbatim from
`02a60baf012db5d8d13223392fe0eeaef7ae0e8e` at
`portability/fixtures/pipeline-registry-exact-strings.json`. The original
expected CID `sha256:579c3a62fc22e6fea165bdd5714e3ca26206f606e43098434e84c02c8c0651cc`
and all older independent identity assertions remain unchanged. This is a
historical test artifact, never a runtime registry or compatibility path.
The complete registry test file then passed 3/3 (`run-SBt4wm`,
`focused-test-qE4m5d`). Final submitted-SHA evidence follows in the PR.

## Remaining work

This closes public retained ordered derive, not Local Compute as a whole.
The parent's Native observer/census source alignment was adopted from main;
this change adds no driver state or new physical allocation profile. A Native
capacity campaign was not executed here and is not implied by adoption.
Initial metadata preparation and availability analysis are not certified as
resumable by this unit. Native Host in-flight cancellation remains a separate
completion unit. Full Core, Wasm/Native execution, packed Local/HTTPS,
capacity/proof campaigns, performance and public stop-latency measurements
were not run. Local success is not hosted CI success. Keep the PR Draft while
the remaining verification/review boundary is unresolved.
