# Outbound R1: durable observation replay

## Completion unit

The existing Coordinator owns admission and replay receipts. A fully matching
accepted observation is ACK-only after current authentication and exact
authority/Run/dispatch/Site/generation checks. State and admission history are
one durable update. Reply/status does not create separate receipt namespaces.
Unaccepted stale observations, conflicting state, and changed filled evidence
identities are refused. Storage failure or an unknown commit result is not ACKed.

R3 is inherited from merged main, not resubmitted. R2 automatic redelivery,
O2 cancellation, O6 generation/restart handling, Cloud implementation, and a
general bound for every Site `prepare_*` transition remain outside this PR.

## F: public package delta

`@actql/coordinator-core` adds:

```ts
export function transitionIsReplay(transition: Transition): boolean;
```

The existing issuance/admission functions remain the source of canonical
records and typed evidence. Minimal use, after reading the original durable
record under the Host's trusted authority:

```js
const durable = coordinator.admitDurableJson(savedBody);
const journal = coordinator.createJournal(expectedAuthority);
const record = coordinator.restoreDurable(journal, durable);
const request = coordinator.durableRequest(durable);
const response = coordinator.admitResponseJson(body, request, statusReply);
const transition = coordinator.prepareResponseObservation(record, response);
const replay = coordinator.transitionIsReplay(transition);
const expectedRevision = coordinator.transitionExpectedRevision(transition);
const nextBody = coordinator.responseDurableJson(durable, transition, response);
```

The Cloud persistence adapter must atomically reconcile the currently stored
record before acknowledging. For `replay`, `nextBody` is exactly the unchanged
body: do not CAS to `expectedRevision + 1`, write a separate receipt, or issue
new start permission. For a new admission, persist the exact next body/history
at the same commit boundary before `commitTransition(transition)` or ACK.
If storage changed meanwhile, restore the new durable record and re-admit;
never ACK solely from an obsolete in-memory handle. Current authentication and
trusted expected scope are required even for already admitted receipts.

The JS wrapper retains `CoordinatorOwnerRejected` and its typed owner cause.
New core refusal kinds are `ObservationHistoryRequired`,
`ObservationHistoryCapacityExceeded`, and `ObservationAdmissionClosed`;
ordinary identity/state collisions remain refusals. Do not parse Debug text
or turn storage/transport errors into these semantic refusals.

## Persistent format and bounds

Wire contracts and Run/dispatch/evidence CID rules remain unchanged at 0.1.
The canonical stored body uses
`actql-remote-coordinator-history-record/0.1` with
`observation_history_json`; the Node SQLite discriminator is
`actql-remote-coordinator-history-journal/0.1`. This is a distinguishable,
non-compatible coordinated persistent change, not an implicit migration.
Old records cannot provide the new replay guarantee. Refusal retains their
bytes and outstanding responsibilities. The private snapshot includes WAL;
unsupported original databases are never opened with SQLite during preflight.

There are 64 ordinary positions and seven finite closing facts/evidence slots,
at most three typed profiles per position, at most 213 profiles, and a
131,072-byte canonical history limit. The closing-fact table and admission-close
conditions are in `docs/design/remote-site-execution.md`. Retry-only revisions
do not consume arbitrary closing slots. Final evidence reception is not closed
merely because physical release happened first. This does not establish §6's
global history bound.

## Direct verification and reproducible commands

Use the repository's pinned MoonBit environment and dependencies.

- `moon test --target js src/remote_site_protocol`: 70/70.
- Same package on Wasm and native: 70/70 each.
- The format-inspection, Client request journal, Coordinator journal,
  Coordinator, and outbound gateway Node test files: 79/79 before adding the
  separate-process regression. Coordinator journal alone after that addition:
  13/13. No skipped tests in these runs.
- `npm run check:remote-site-runtime`: 175/175 after the separate-process
  regression and main integration, followed by successful packed Coordinator
  verification. No skipped tests. CI also directly runs the shared SQLite
  format-inspection tests.
- Native `platform_native/remote_journal` with a real SQLite library/root:
  15/15, including WAL/no-SHM refusal and primary-plus-close-failure retry.
- `node scripts/test-native-resident-site.mjs --observation-replay-only`:
  real native executor entry 1, historical observation replay after Coordinator
  owner reconstruction, release, reserved payload bytes 0, pending intents 0.
  This is local HTTPS/native execution, not real Cloud or O6 Site restart.
- The separate-process regression restores the journal and typed owner in a
  fresh Node process; no pending-memory receipt map participates.
- Packed `@actql/coordinator-core` exercises `transitionIsReplay` through the
  installed public package and preserves the durable body and revision.
- `node scripts/local-checks.mjs run lint`: passed. The first local attempt
  resolved the old shared checkout's Client wire declarations and failed on
  `WireResultDescription`; using a C-private dependency reference to this
  tree's declared Client wire package resolved that environmental mismatch.
  No product declaration or check was weakened. The lint job's JS-only subset
  has its existing intentional MoonBit-source test exclusion.

For the fixed old-owner continuation check, create an unmodified checkout of
`8028e8a708db6a5ef2b82f6d559b3d2bf7e55041`, build its Node release bridge,
and build the current tree's Node release bridge. Then run:

```sh
node scripts/test-coordinator-legacy-custody.mjs /absolute/legacy/worktree
```

`ACTQL_TEST_SCRATCH_ROOT` selects an outside-checkout evidence directory. The
test creates an actual old-owner WAL/no-SHM journal, verifies non-destructive
new-writer refusal, continues the exact old dispatch's custody with the old
owner, and verifies that the old writer rejects new history-bearing records
without logical state/history updates. A typed release observation is not
proof of physical Site cleanup; that is separately measured by the resident
test. The script retains its small DB fixtures and `evidence.json` for review.

The local full `check:spec` was intentionally interrupted while another
developer's same expensive resource audit was running; it is not recorded as
a full pass. Final required Linux CI and the full native foundation gate are
still pending. Final SHA and CI results belong in the PR validation section.
