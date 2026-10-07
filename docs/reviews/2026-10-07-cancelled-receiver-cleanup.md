# Cancelled consumer receiver cleanup

A retained Transfer can commit its receiver before the consumer dispatch is
delivered. If that consumer is then durably cancelled, it has no accepted input
envelope. Completed-consumer cleanup cannot reconstruct its address, and root
Source cleanup has no incoming input. The committed receiver remains a separate
responsibility even when both task records report released cleanup.

The cleanup-only API admits the original checked edge, durable producer
observation, saved intent/plan, exact committed Transfer record and receipt,
and the original consumer request matched to its cancelled/released record.
The recorded variant checks the original Program/graph and publication evidence
without issuing a new Plan, executable input, grant or start claim.

Native admission additionally requires the exact durable cancellation marker,
current Site identity/generation and delegation, and the real exclusive slot.
It reuses the existing receiver reader-return/reclamation Owner. An absent
original reader is allowed only after exact Transfer/receipt admission. Another
reader fences reclamation; failed cleanup retains the original reservation.
Every retry rechecks current custody. No task terminal state is changed here.

The original consumer request must come from trusted saved Coordinator custody.
The retained plan identifies the checked consumer edge, not its task attempt.
Callers must preserve the saved association; a newly issued request for the
same task is not a substitute for the original request.

## Explicit recovery operation

`native_remote_resident_site recover-cancelled-receiver` uses the existing Site,
bundle, executor-slot and Transfer-journal configuration. It requires:

- `--producer-attempt` and `--expect-producer-dispatch` for the original producer.
- `--consumer-attempt` and `--expect-consumer-dispatch` for the original consumer.
- `--recovery-materials-root` containing `consumer-request.json` (the saved
  issued request) and `retained-transfer.json` (the saved common poll envelope).
- `--publication-custody-root` containing the original publication evidence in
  the same format as existing recorded Source recovery.

Read these original bytes from their existing custody. Do not regenerate the
materials, refresh expiry, substitute another attempt or hand-write the wire.
The operation never creates a consumer envelope or cancellation record. Missing
or mismatched custody is refused, and cleanup failure remains retryable in the
existing journals. Confirmation of this physical operation does not establish
Cloud's durable acceptance or the original Run's formal cancellation terminal.

## Remaining acceptance

See [the evidence record](../evidence/cancelled-receiver-cleanup.json) for exact
executed and unexecuted scopes. The final Native test build exceeded its bounded
preparation deadline; the previous executable was not reused. Caller compilation
and portable Owner tests passed before main integration. At the integrated
source, Native caller checking and interface generation pass, but the portable
receiver selection reaches its 60-second bound without a test summary. The
subsequent existing cleanup caller selection is therefore unexecuted. Earlier
17/17 success from that earlier invocation is not claimed for this integrated source.

The JS output was subsequently observed to have been written after the parent
preparation deadline. Its source map embeds 782 files, all equal to the current
source bytes; the sole nonembedded generated driver and output digests are
recorded separately. Direct execution of the unchanged pinned generated driver
selects only the receiver and existing cleanup files. All 17 cases have exact
matching start/result events and empty failure messages within the 60-second
execution bound. This is generated-artifact execution evidence, not successful
bounded preparation or Native physical execution. The initial failed receipt
remains unchanged. A clean-source normal Native executable build
also exceeded its 180-second preparation bound; no recovery was executed with it.
Both the final recorded-graph test and normal command were additionally attempted
in the standard release profile at the same bounds; both preparations timed out
before execution. These are compiler-preparation failures, not test assertion
failures, and their receipts remain separate.
The original Run's journals, original issued
bytes and three sealed receiver allocations remain preserved.

Read-only extraction of the original failed Run now verifies its saved checked
consumer edge, intent/plan, Coordinator consumer request and Site cancellation
request agree. Its original publication evidence and exact poll envelope have
been preserved as bounded recovery inputs. This historical admission grants no
current execution permission and has not reclaimed the receiver.

After reviewed main adoption, run this exact recovery through existing Owners,
verify zero receiver reservations and physical allocations without new execution,
and send/accept the formal cleanup observation through the current Cloud path.
The recovered-release observation fix from OSS #841 is now merged into main and
included in this branch. It still requires formal Cloud adoption and execution. A new successful
Run must not close the original Run or other historical recovery obligations.
