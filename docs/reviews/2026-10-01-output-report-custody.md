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
projection exposes the same issuer through coordinator-core.
The issuer is not evidence that its caller actually committed acceptance.
Cloud must connect it to its existing durable Output owner, not a waiter.

The public projections are
`outputReportAckJson(record: OutputRecord, originalReport: string): string`
and `outputReportRefusalJson(record: OutputRecord, originalReport: string,
reason: 'authorization_denied' | 'scope_mismatch' | 'report_conflict'): string`.
Both re-admit the report against the expected Output owner. The refusal
issuer does not decide authority: the receiver must establish the current
definitive refusal first. Raw HTTP/errors are not inputs to that decision.

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
their durable completion remain operable. This is the Output-report unit's bound, not a
proof of the wider §6 history limit.

An explicit retry stores a versioned local marker,
`actql-site-output-report-retry/0.1`, containing the last checked refusal. The
marker is not a wire ACK and preserves the recovery reason for inspection;
retrying never changes the original report bytes or identity. An accepted ACK
is terminal and cannot be overwritten.

The fixed-toolchain evidence for this unit is:

* native SQLite journal and protocol tests: 91/91 for the combined native
  target, including durable refusal, explicit retry-marker preservation, an
  ACK-save lock failure that leaves the report pending, slot exhaustion with
  existing cleanup/ACK, and reopen/re-admission; the protocol JS and Wasm
  targets are 74/74 each;
* Node remote-site runtime gate: 191/191, including the focused gateway and
  Coordinator suites, packed `coordinator-core`, commit-result-unknown replay,
  and an exact typed ACK after Coordinator reconstruction;
* real native resident Site `--output-report-only`: one executor entry,
  real SQLite receiver killed immediately after durable acceptance, its ACK
  deliberately lost, physical release
  before ACK, holder termination immediately after report handoff,
  Coordinator/Site restart, byte-identical report replay, Site killed directly
  before and after ACK commit, and final `reservedPayloadBytes=0`,
  `pendingOutputIntents=0`, `pendingOutputReports=0`, with no allocation
  directories left. Legacy, empty, malformed and other-report HTTP 200 replies
  and an unconfirmed 503 leave the original report pending. ACK-only replay
  preserves the receiver's durable state and revision. A checked refusal is
  inspected after process exit; explicit operator retry re-enables the same
  report without payload or executor reconstruction;
  two real control processes replay concurrently, one ACK is held until the
  other process saves it and exits, and the late ACK leaves the saved journal
  bytes/revision unchanged after physical release;
* common remote-site protocol JS tests: 73/73 on the pinned checkout before
  the native process run. Initial local attempts without the pinned MoonBit
  toolchain or the optional esbuild dependency are environment setup failures,
  not product results; the reruns use the pinned toolchain and scratch cache.

The native evidence JSON is emitted as
`resident-output-report-custody-verified` by
`scripts/test-native-resident-site.mjs --output-report-only`. The retained
scratch directory can be preserved with `ACTQL_TEST_PRESERVE_SCRATCH=1` so the
SQLite journal, executor log and TLS proxy trace can be inspected. Default
successful runs remove their owned installation after emitting the evidence.

The same real-process scenario also runs through installed packed public
packages with `scripts/test-packed-resident-materials.mjs --output-report-only`.
CI retains its summary, stdout/stderr and tarball digests independently of the
disposable installation.

## CI corrections and evidence boundaries

The first full run of `2c3c4f9f0` (36822147574) failed in three distinct ways:
the native Coordinator still emitted legacy Output ACKs (Native Linux,
macOS and separated-network); the common native job omitted the real SQLite
fixture prerequisites; and the new ACK schema was not registered with its
normative document owner (spec). The corrections migrate the receiver to the
common typed ACK issuer after exact durable acceptance, supply SQLite to the
native core job, and register the schema with the specification family. No
expected result, ACK fallback or validation gate is relaxed.

Initial local HTTP runs lacked the required scratch root or the worktree's
pinned DuckDB installation. The final rerun uses the shared, unchanged pinned
installation; these setup failures do not count as product passes.

The local `check:spec` run passed through contract validation, then stopped at
link validation because the borrowed esbuild-only installation lacked `unified`.
The unchanged remaining commands are rerun with the repository's pinned document
dependencies; the pushed CI is the complete same-SHA specification gate.
The resumed canonical gate then detected stale generated identity vectors after
the schema-family registration. The existing independent canonical/hash oracle
regenerates that family vector; it does not copy a product-emitted CID.
All unchanged `check:spec` commands after each documented stop passed on resume.
The final local checks also pass `moon fmt --check`, warning-free JS/Wasm/native
checks, and 436 canonical identity tests on each of the three targets.

The existing Native HTTP and full resident Site scenarios also pass after
migrating their Output fixtures through the existing durable receiver. A first
full resident run stopped at payload reclamation because one fixture still
bypassed that receiver and returned `RemoteDispatchIntentMissing`; its
Output-plan and delivery calls now use the same owner as the other scenarios.
No timeout or expected cleanup state was relaxed.

The preflight snapshot bound includes the maximum decimal width of an admitted
Transfer revision, rather than the single-digit revision of the sizing fixture.
A regression with revision 2147483647 verifies that the actual snapshot fits
the preflight bound before physical work begins.

Cloud adoption and real Cloud ACK acceptance remain F's responsibility.
The OSS acceptance receiver, actual native processes and packed exports do not
prove that Cloud has connected the new durable ACK contract.
