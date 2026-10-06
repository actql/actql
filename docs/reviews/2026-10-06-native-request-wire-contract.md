# Native request-response wire derivation

## Scope and authority

This is the bounded lookup/held extension left explicit by
[the initial Native wire derivation](2026-10-04-native-wire-contract.md)
(PR #368, issue #349). The inspected and executed baseline is OSS main
`c558da09dff69e1d84fed3741b86ca228b3a03a9`. The baseline was frozen rather
than repeatedly integrating unrelated concurrent changes.

The existing `spec/contracts/actql-client-host.json` and build-time generator
now derive `lookup_found`, `lookup_not_found`, `lookup_unknown` and `held`
validation for Native as well as JS. Held state constraints live in that
schema's `allOf`/`oneOf` clauses. Its new `request_response_rules` describes
which alternatives bind the expected request identity. Both emitted consumers
validate the expected identity using the same required field schema and bind
it by exact equality. Generation refuses missing, duplicate, unknown or open
alternatives, missing required identity fields and inconsistent identity
schemas instead of silently dropping a constraint.

Native no longer maintains its own envelope fields, checkpoint kinds, string
limits, state rules or request-ID equality. JS's public held/lookup exports
also delegate to the generated rules. This extends the existing bounded
compiler; it does not add a runtime schema interpreter, a second Host decision
owner or another wire version. Existing configuration and artifact CIDs are
unchanged.

## Preserved behavior

- `waiting_checkpoint` requires a checkpoint and forbids either terminal field.
- `resuming` forbids `endReason` and `terminalErrorCode`; a retained checkpoint
  remains permitted.
- `ended` requires `endReason`; a retained checkpoint and `terminalErrorCode`
  remain permitted.
- IDs and metadata retain UTF-16 maximum lengths and control-character refusal.
  Expiry metadata remains opaque bounded text, not a new timestamp grammar.
- `not_found` and `unknown` retain their distinct meanings. Found/held identity
  is matched without case folding or Unicode normalization.
- Native bounded held JSON parsing, request construction, transport uncertainty
  and the existing `InvalidHostRequestLookup`/`SubmissionUnknown` diagnostics
  are unchanged. This is a validation convergence, not a demonstrated
  authorization bypass.

## Executed counterexamples and independent acceptance

Before production edits, a fresh selected Native release build from the exact
baseline ran 29 tasks. The expanded independently authored corpus ran the
actual exported JS wire validators and that Native CLI over mTLS. It recorded
**500 passes and 22 failures**: Native accepted newline, NUL, DEL, 257 ASCII
units and over-limit astral text in unknown reasons/found expiries, and invalid
expected IDs for found/not-found/unknown replies. JS rejected each. Existing
held state behavior passed; its problem was duplicated authority, not a newly
claimed state-machine defect.

The corpus retains its original 102 cases and now has 522 cases. It includes
an explicit 24-row held state/presence truth table on both submit and lookup,
256/257 and astral boundaries, controls, missing/extra fields, request-ID
mismatches, malformed checkpoints and all current checkpoint kinds. Expected
answers are literals and independently authored tables, never outputs from the
product generator or validators. NUL stays in remote responses because OS
arguments cannot contain it. Empty expected CLI IDs are not used as a response
rejection oracle: the CLI rejects those before transport.

Every new Native case verifies the exact response endpoint, request body and
identity after valid negotiation. Negatives require the precise response
validation diagnostic; argument, profile, transport, process and spawn errors
cannot count as malformed-response rejection. The executable runs outside the
checkout with an empty executable PATH.

After repair, **555/555** selected corpus/generator/wire tests passed. The
existing full Native transport assertions plus selected SDK index, in-process
port, redirect and checkpoint callers also passed: **665/665** counted Node
tests, including the 522-case corpus. The original transport assertions run
before that imported corpus and remain intact. The SDK tests resolve this
checkout's actual client-wire package. This is focused source-package and
transport validation, not a pristine packed-package or real Host Program Run
campaign.

## Authority evolution and freshness

An actual temporary authority change reduced the unknown-reason maximum to
255, required a checkpoint for ended held replies and changed the lookup
identity binding to `prepareAttemptId`. Three independently authored controls
passed first. The read-only generator detected stale output. After regeneration
and a fresh selected Native build, all three changed expectations rejected in
both actual JS and Native entry points. Restoring the authoritative bytes,
regenerating/rebuilding and rerunning restored all three positive controls.
Separate stale-JS and stale-Native output mutations were also rejected at the
exact named freshness checks. All temporary changes were restored byte-for-byte.
Generator tests cover each added schema and relation and malformed binding
rules; the ordinary freshness check still compares exact JS, Native and type
outputs.

## Commands and limits

Using the checked-in Node/MoonBit pins and existing bounded/nonzero wrappers,
with one gate at a time:

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- --target native --release --deny-warn src/cmd/native_client
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/test-native-client-wire.test.mjs scripts/generate-client-host-wire.test.mjs packages/client-wire/index.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/test-native-client.mjs scripts/generate-client-host-wire.test.mjs packages/client-wire/index.test.mjs packages/sdk/index.test.mjs packages/sdk/host-port.test.mjs packages/sdk/http-redirect.test.mjs packages/sdk/checkpoints.test.mjs
node scripts/generate-client-host-wire.mjs
node scripts/check-actql-spec-family.mjs
node scripts/check-canonical-json.mjs
node scripts/check-owned-contract-versions.mjs
git diff --check
```

The original fail-first receipts are `run-hrgEOa` (build) and
`run-fe523i` / `focused-test-JaaUx4` (corpus). Repaired focused acceptance is
`run-FBYck5`; the expanded transport/SDK regression is `run-tAZQPx` /
`focused-test-oAFIwv`. These identify local evidence at their recorded source
state; exact published-head verification and automatic CI are reported in the
PR separately. Generated and edited MoonBit formatting is checked with the
pinned formatter.

No full Core/all-target, proof, packed, performance, Cloud deployment or live
provider acceptance is claimed. Draft preparation and focused local success do
not replace normal required hosted checks or establish merge readiness.
