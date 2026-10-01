# Durable Output report custody and exact acknowledgement

## Receiver handoff (Cloud owner: F)

The original `actql-remote-output-result/0.1` bytes and CID are unchanged.
The report CID commits its dispatch CID, Output intent CID, exact payload
request, physical digest, Transfer request and destination-committed receipt.
The dispatch and intent transitively bind the original Run, task attempt,
Site/generation, Coordinator authority, Result and publication occurrence.
The authenticated transport scope must still be checked independently.

The new closed, canonical response is
`actql-remote-output-report-reply/0.1`, with fields in this order:
`dispatch_request_cid`, `intent_cid`, `outcome`, `reason`, `report_cid`,
`version`. An accepted response has `outcome: "accepted"` and `reason: ""`.
Only after durable acceptance may the receiver call the common issuer.
An exact replay obtains the same response from its saved acceptance fact;
neither a new revision nor another Output operation is required.

The common APIs are `remote_output_report_reply_json(result, reply)` and
`admit_remote_output_report_reply_json(body, original_result)`. The public JS
projection will expose the same issuer/admitter through coordinator-core.
The issuer is not evidence that its caller actually committed acceptance.
Cloud must connect it to its existing durable Output owner, not a waiter.

A checked refusal uses outcome `refused` and one closed reason:
`authorization_denied`, `scope_mismatch`, or `report_conflict`. An HTTP status,
unvalidated error object or arbitrary diagnostic is not a definitive refusal.
Old `200 / {accepted:true}`, empty/malformed replies and other report identities
do not complete custody. There is no legacy success fallback.

## Site custody boundaries

Before posting, the existing Site journal owns exact original report bytes and
the typed inputs required to re-admit them without runtime/payload access.
ACK acceptance is a separate durable fact from physical payload reclamation.
The existing control process enumerates unacknowledged reports on startup and
retries with bounded backoff; it does not depend on an in-memory holder queue.
Physical release can finish first, without preserving a payload or executor slot
solely for replay. Neither cleanup completion nor publication is a report ACK.

Checked refusal is durable, queryable, non-secret attention state. Explicit
retry rechecks the current authenticated scope and sends the original bytes.
No report regeneration, Compute/Transfer rerun, new attempt, public Execution
reconcile change, O2 or O6 completion is implied.

## Bounded retention and evidence

The Site journal retains one immutable snapshot slot per Output intent. The
current implementation bounds the retained report set at 32 slots (at most
64 MiB of custody snapshots at the 2 MiB snapshot limit). Duplicate reports,
ACK replays and cleanup retries reuse the slot and do not consume another
history entry. Once the normal slot bound is reached, a new Output is rejected
before payload/Transfer work; existing reports, ACKs, physical cleanup and
their durable completion remain operable. This is the R1 unit's bound, not a
proof of the wider §6 history limit.

An explicit retry stores a versioned local marker,
`actql-site-output-report-retry/0.1`, containing the last checked refusal. The
marker is not a wire ACK and preserves the recovery reason for inspection;
retrying never changes the original report bytes or identity. An accepted ACK
is terminal and cannot be overwritten.

The fixed-toolchain evidence for this unit is:

* native SQLite journal and protocol tests: 90/90 for the combined native
  target, including durable refusal, explicit retry-marker preservation, an
  ACK-save lock failure that leaves the report pending, slot exhaustion with
  existing cleanup/ACK, and reopen/re-admission; the protocol JS and Wasm
  targets are 73/73 each;
* Node remote-site runtime gate: 191/191, including the focused gateway and
  Coordinator suites, packed `coordinator-core`, commit-result-unknown replay,
  and an exact typed ACK after Coordinator reconstruction;
* real native resident Site `--output-report-only`: one executor entry,
  receiver ACK deliberately lost after durable acceptance, physical release
  before ACK, holder termination immediately after report handoff,
  Coordinator/Site restart, byte-identical report replay, and final
  `reservedPayloadBytes=0`, `pendingOutputIntents=0`;
* common remote-site protocol JS tests: 73/73 on the pinned checkout before
  the native process run. Initial local attempts without the pinned MoonBit
  toolchain or the optional esbuild dependency are environment setup failures,
  not product results; the reruns use the pinned toolchain and scratch cache.

The native evidence JSON is emitted as
`resident-output-report-custody-verified` by
`scripts/test-native-resident-site.mjs --output-report-only`. The retained
scratch directory is preserved until review handoff so the SQLite journal,
executor log and TLS proxy trace can be inspected.
