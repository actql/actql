# Checked remote task Run projection

`projectTaskSiteRun` binds an effect-free checked Run to its admitted durable
Coordinator task records. It uses the checked graph's task keys, Result ports
and dependency readiness from `inspectTaskProgress`, then asks the existing
unpublished Run-state issuer to produce the public state wire. It does not
parse a second plan or introduce a scheduler, ledger or aggregate revision.

The trusted Host supplies its saved task start claims and cancellation request.
Those inputs are facts to reconcile, not permission to dispatch. A missing
observation after a claim remains unknown. Unknown, failed or cancelled work
prevents selecting another task. Duplicate claims, foreign task keys, foreign
Run records and competing task attempts are rejected by the shared owners.

Physical settlement alone cannot enable publication: every checked task needs
admitted durable output evidence. Producer-only completion leaves the Run
unpublished. Once both tasks are complete, only checked Result-producing tasks
receive publication work. The existing publication owner must still commit the
index; this projection cannot report an available Result or committed success.

Cancellation-request persistence, execution stopping and cleanup stay distinct.
Collected facts go through `confirm_client_run_cancellation`, the existing
shared eligibility owner for live and restored execution.
The snapshot cannot project completed cancellation until all task observations
are terminal and their cleanup obligations are discharged. Missing task
observations remain pending, even if the Host sees no physical payloads. The
caller must still use the existing Run/cancellation owner to resolve revision,
publication/fence races and commit a transition. This is not an alternative
terminal-decision or stop operation. Model and Effect graphs are rejected.

Each task retains its own admitted dispatch identity, execution scope, revision
and cleanup state. `nextWork: none` is not a cleanup confirmation. In particular,
producer holding stays owned while the consumer and publication proceed.
`recovered_after_loss` can discharge its common cleanup obligation but remains
distinct from normal `released`; neither proves recovery of another Run.

## Executed evidence

- Eight selected Run Host boundary cases passed using the bounded nonzero Node
  wrapper, including four whole-Run cases. The tests use actual common protocol
  admission and independent assertions for readiness, unpublished availability,
  revisions and cleanup; they are not Native execution evidence.
- The selected `run-host-core` runtime was rebuilt from the changed sources.
  Shared Host interfaces compiled on JS, Wasm and Native; the JS-only ABI
  compiled on JS.
- The existing single-record projection still refuses a two-task Run.
- The existing actual Native two-task harness now uses this whole-Run
  projection. Coordinator reconstruction passed with acquisition/producer/
  consumer counts 1/1/1, independent `[{id:3}]` and schema, durable typed Output
  ACK, both tasks normally Released, receiver reclamation, all Site temporary
  capacity counters zero and Result reread. Producer-only completion stayed
  unpublished. The original producer holder remained live.
- Actual cancellation before consumer handout passed with counts 1/1/0;
  delayed exact dispatch and repeated cancellation did not start the consumer.
  Only after both exact cleanup observations did the snapshot project
  cancelled, with both tasks Released and temporary capacity zero.
- Both Native selections retained the existing 180-second bound and stripped
  build. The initial sandbox listener refusal (`listen EPERM` on loopback) and
  its scratch remain preserved separately; it was not a product assertion
  failure. These tests use the actual Site and protocol listener, not the public
  Cloud Client or Cloud publication service.
- No wire version, canonical preimage, formal package pin or Native binary was
  changed by this unit. No full Core, packed, proof or performance campaign was
  run.

## Remaining connection work

Cloud #138 / OSS #182 still requires durable checked task claims, retained input
custody and Transfer reconstruction, consumer dispatch, publication and both-task
formal release through the public Client path. The earlier Native component
acceptance retained the original producer holder; it does not prove holder
regeneration or public Cloud execution. Formal Cloud adoption must use reviewed
merged-main sources and matching five-package and Native artifacts. Preview
acceptance and #88's original Run recovery remain separate and unfinished.
