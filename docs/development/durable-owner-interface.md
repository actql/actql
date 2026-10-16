# Durable Owner interface references

The existing Common transitions and their physical journal adapters remain the
operation authorities. Prepared transitions, physical commit, durable conflict
and an unconfirmed commit reply are separate outcomes. An observer projects
facts; its result is not a Run result, approval or physical-release ACK.

| Attribute | Existing authority and executable reference |
| --- | --- |
| Responsibility | `src/remote_site_protocol`; `src/remote_transfer`; `adapters/host-common/sqlite-transaction.mjs`: `createSqliteTransaction`; `adapters/host-node/remote-site-coordinator.mjs` |
| Inputs/outputs | `adapters/site-node/sqlite-dispatch-journal.mjs`; `adapters/site-node/sqlite-transfer-journal.mjs`; `adapters/host-node/sqlite-coordinator-journal.mjs`; `adapters/host-common/observation.mjs`: `observationVersion`, `observationLimits` |
| Identity | `adapters/site-node/sqlite-dispatch-journal.test.mjs`: `reopen reconciles exact resend`; `adapters/site-node/sqlite-transfer-journal.test.mjs`: `destination evidence collision`; `adapters/host-node/remote-site-coordinator.test.mjs`: `Site status cannot replace evidence` |
| Ownership | `adapters/host-common/sqlite-transaction.mjs`: `throwSqliteInitializationFailure`; `adapters/host-node/remote-site-coordinator.test.mjs`: `output owner retains a continuing sibling`; `adapters/host-common/observation.test.mjs`: `timed-out delivery keeps its connection owned` |
| Synchronization | `adapters/site-node/sqlite-dispatch-journal.test.mjs`: `accepted dispatch is durable before`; `adapters/site-node/sqlite-transfer-journal.test.mjs`: `destination commit evidence is durable before`; `adapters/host-node/remote-site-coordinator.test.mjs`: `after the query await` |
| Failure | `adapters/host-common/sqlite-transaction.mjs`: `outcome`; `adapters/host-common/sqlite-transaction.test.mjs`: `lost physical COMMIT reply`; `adapters/host-node/remote-site-coordinator.test.mjs`: `failed/unknown first material save` |
| Cancellation | `adapters/site-node/sqlite-dispatch-journal.test.mjs`: `evidence and cleanup planes`; `adapters/host-node/remote-site-coordinator.test.mjs`: `output cleanup owner retries`; `adapters/host-common/observation.test.mjs`: `failed optional storage initialization` |
| Resources | `adapters/site-node/sqlite-transfer-journal.test.mjs`: `concurrent journal handles`; `adapters/host-common/observation.mjs`: `observationLimits`; `adapters/host-common/observation.test.mjs`: `queue overflow` |
| Extension | `adapters/site-node/sqlite-dispatch-journal.test.mjs`: `journal migration`; `adapters/host-node/sqlite-coordinator-journal.test.mjs`: `legacy records`; `adapters/host-common/observation.test.mjs`: `unknown event content` |
| Verification | `scripts/owner-fault-mutations.test.mjs`; the exact source-qualified journal, Coordinator and observation test selections recorded separately in execution receipts |

The physical COMMIT-reply test writes to real SQLite, loses only the returned
acknowledgement, then reopens and observes the same original attempt twice
without another write. Reclassifying that throw as a known failure is detected
by the independent assertion. Suppressing an original operation failure inside
the observation wrapper is detected by its original-error assertion.

The existing source-less fixture path may execute unmodified adapter sources
against qualified compiled Owner artifacts without rebuilding them. That is a
component qualification, not a newly compiled runtime or normally installed
public product. Lost/duplicate/reordered/stale-generation, permission, deadline,
physical cleanup and unknown-outcome cases retain their individual receipts.
