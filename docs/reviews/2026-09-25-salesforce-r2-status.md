# Salesforce Effect review R2 status

Review baseline: `15904a32f31573a86a3507253f3eaa1b010adf78`.
Prior implementation and verification baseline:
`40ef6ad720e93b98c2c42e6f7ec0bb170682f135`.

The follow-up review in `02-salesforce-effects (2).md` repeats this
coordinate finding and distinguishes it from the still-open ordinary Run
integration. Its fixed SHA predates the coordinate and Host regressions
recorded below. The finding is not a second implementation task.

## Coordinate and execution boundary

The Stage-to-physical-Task Effect source mapping was already present before
this follow-up. The additional standard Host regression now executes three
source shapes: a Result after a split Stage, the split Stage's final Result,
and its intermediate Result. It verifies the exact producer Task, projected
rows, port close behavior, pin lifetime, and cleanup.

The two-member source test now also runs with a split producer. It first
forces a late pin-capacity failure, then confirms both independent pins use
Task 4 and that releasing one does not invalidate the other. The surviving
pin exports the checked rows after the ordinary output port closes.
Both the shared-source and split-producer Host fixtures now also reject a
pin before Compute has produced its output. The same owners subsequently run
and pin at exact capacity, showing that the early failure did not strand a
holding. This is not the missing local HTTPS no-send regression.

The regression exposed two adjacent execution defects. A managed consumer
rejected Task 0 even when the Run root was Compute, and the source-free Local
Effect Host did not install the existing SGA provider. Both now use the common
Run and Local provider boundaries. The selected physical Task's exact Step is
also retained while generating its sequence. No Effect-specific graph resolver
or second execution state machine was added.

The two-member Host fixture also opens a second captured graph for the same
checked Run and rejects crossing its Result pins into the first graph's
Preview binding in either direction. Both executions and pin sets close
independently. Equal Program and Run identities therefore do not substitute
for the exact captured owner.

## Verification

- Standard Client/Local Host tests: 14/14 (rerun after selected-route
  preflight was bound to the captured Preview).
- Effect application and physical strategy: JS, Wasm, and native 56/56 each.
- Tracked MoonBit public API check: passed.
- Query integration: JS 556/556, Wasm 556/556, native 556/556.
- MoonBit formatting and Node connector assembly: passed.
- Isolated Connector addition gate: baseline and extended all-target checks,
  third-Connector JS/Wasm/native tests, and real Node Host test passed. Its
  isolated fixture needed the Client wire package; the unrelated duplicate
  test match that failed `--deny-warn` was removed.

These are local tests, not a same-SHA Linux CI run or a live Salesforce org
test. No live org credentials or write authorization were supplied.

## Still open

R2-G1 remains a completion condition: connect the checked/captured inputs,
whole-set Preview and apply admission, durable claims, physical writes,
reconciliation, and final publication through one ordinary multi-member
Effectful Run. The current standard Host regression stops at owned input
export; it does not prove the mutation or final Receipt path. Local HTTPS
no-send cases still need top-level coverage.

The checked Effect preparation now exposes a private per-member Plan CID so
the eventual Preview can bind the exact static Plan without reauthoring it in
JavaScript. It is a static identity accessor, not input capture or an apply
permit. Product connection and the review's fault-injection matrix remain
open. Same-SHA Linux CI and live Salesforce are not yet verified.

The installed Host now connects a live Preview input to the generation-checked
managed Result importer and the common canonical Result cursor. For each row,
MoonBit compares the checked Plan selector and intended changes against the
admitted private Preview before releasing prepared Result bytes. Exact row
count and pin liveness are checked before returning the relation receipt.
The Host fixture verifies matching update rows, altered changes, swapped
targets, and a released pin. This is payload evidence only: it neither admits
current target guards nor issues an apply permit, dispatches writes, or commits
an Effectful Run. Prepared-output sinks must reclaim partial bytes on failure.

At `24bff12682889e5004ea60de347ff0c580a2a588`, the grouped Client
distribution gate passed: 73/73 Node tests, packed Node/browser Client smoke,
and native Client mTLS. This does not replace the missing Effectful submit and
apply E2E or same-SHA Linux CI.

The next Plan sub-inventory now issues an opaque proof only after the checked
Result cursor and its completed export receipt both finish. The private
Preview, exact member, and live input pin must still match when the proof is
used. An inventory check requires one distinct proof for each Plan-bearing
member and rejects missing, duplicated, foreign, and released proofs. This
does not cover members without a Plan, current guards, whole-set write
footprints, or apply authority. The proof constructor remains inside the
product bridge rather than the generic row comparator, because arbitrary
rows supplied to that comparator do not prove Result provenance.

The Host regression now binds two independent Effect members to the same
completed Result. Each member finishes its own checked Plan cursor; the proof
inventory accepts either proof order and rejects an omitted or duplicated
member. A same-boundary collection footprint is rejected before export,
whereas separate provider boundaries admit the two-member payload check.
This fixture performs no mutation and does not establish whole-set apply.

The admitted Preview owner also retains each member's existing source,
resolved Contract, capability-evidence, and authority-scope CID. A common
captured-Run check now compares complete current-observation inventories
against those exact bindings while all Result pins remain live. The Site
must still authenticate and refresh those observations; equal caller-supplied
CIDs are not an apply permit. The two-member Host fixture rejects a missing
entry, each changed CID, and reuse after pin release.

The same captured Preview can now check the whole derived row-key inventory
without reparsing the transported Preview. The common 0.1 apply-identity
admission reuses that check, so it has no second key rule. The Host fixture
uses a real logical request scope and derived keys for both members, rejecting
missing, reordered, foreign-scope, and released-input cases. This establishes
the excluded key binding only; it does not renew authority, grant apply, or
send a mutation.

The Client Host now supplies the Ledger frontier with the historical private
Preview identity retained by the same Captured Run owner. In the two-member
Host fixture, a durable possible-send claim for a halted member leaves the
independent member ready after the SQLite Ledger is reopened. Reusing the
claimed row does not create another claim. The frontier remains readable after
one Result pin is released, while current apply checks correctly reject that
released input. This is durable progress reconciliation, not the missing
standard Effectful submit, whole-set permit, or physical mutation path.

The common MoonBit apply preflight now checks each selected route against its
Preview capability-evidence CID and authored row policy. Ordinary `halt`
requires a serial single-row route with ordered requests and identifiable
per-row outcomes. `continue` can use a collection route only with per-item
atomicity and exact row-result identity. Both require a declared manual or
exact unknown-outcome reconciliation path; provider idempotency support is
recorded separately. Salesforce's REST Collections documentation confirms
ordered SaveResult/UpsertResult responses and independent row handling when
`allOrNone` is false: [create](https://developer.salesforce.com/docs/platform/api-rest/guide/resources-composite-sobjects-collections-create.html),
[update](https://developer.salesforce.com/docs/platform/api-rest/guide/resources-composite-sobjects-collections-update.html),
[upsert](https://developer.salesforce.com/docs/platform/api-rest/guide/resources-composite-sobjects-collections-upsert.html).
Those provider facts do not prove ActQL's serial scheduling, current registered
capability issuer, or physical send authority. The Host fixture currently
supplies route codes for the common check; it is not the product admission
source and no write is dispatched by that fixture.

The common MoonBit risk body admission now validates the exact canonical 0.1
body and its self CID. A captured-Preview check compares the body with the
exact Preview, review projection, authority, policy, validity, issuer, and
authentication evidence references; two members require both
`effect_scope_approved` and `partial_application_accepted`. The two-member
Host fixture rejects a missing claim, foreign binding, altered body, and a
released input pin. These are semantic and identity checks only. The product
Host still needs to authenticate the issuer and evidence, enforce current
policy and expiry, and carry the resulting whole-set apply authority to the
physical dispatch owner. Matching CID strings are not such authority.

The risk comparison now also retains and checks `issuer_kind` and `decision`
against separately authenticated Host facts. Equal evidence CIDs cannot
relabel a policy `allow` body as a human `approved` decision. JS, Wasm, and
native Effect/strategy tests each pass 57/57; the standard Host bridge passes
14/14. This remains a comparison boundary, not issuer authentication or a
whole-set apply permit.

MoonBit now also derives the detached-authentication payload CID from the
canonical risk body with only `self_cid` and `authentication_evidence_cid`
excluded. A fixed independent vector verifies the preimage; changing only
the authentication reference changes the complete body CID but not the
signed payload CID, while changing the Preview changes the signed CID. The
Node Host bridge exposes that exact MoonBit result. This does not verify a
signature, issuer trust, expiry, or current grant; those remain prerequisites
for the ordinary Effectful apply path.
