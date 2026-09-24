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

The common publication coordinator now issues an Effectful computation
Manifest, pre-effect Receipt, and Captured Run from a real retained Host
Result set and an admitted private Preview. Its positive product fixture uses
the same name for the Stage Result and declared Program Result, and rejects
a Preview referring to a foreign Artifact. Issuance does not publish or
release the prepared Store owners. The ordinary Effect fixture exposed a 0.1
contract gap: an Effect may consume Stage Result `rows` while the published
Program Result is `answer`. The current Captured Run issuer only looks for
the Effect source Artifact in the published Result inventory by name.
Changing the fixture's name would not resolve that general case. The exact
Effect-source Artifact inventory and its Preview binding still need a
coordinated contract correction before ordinary Effectful Run completion.
The coordinator also requires the exact in-process export owner, not a copied
result object or a second execution of the same checked Run. This is physical
custody for issuance, not a durable publication or recovery guarantee.
Unpublished Result-set release now uses the common prepared-owner cleanup
actions as one single-flight operation. A failed physical release retains a
retry handle and blocks later evidence issuance; the Host fixture no longer
loops over raw prepared handles to reclaim its results.
The Result schema now has its own durable prepared owner, bound to the exact
Run and physical inode generation. Its release follows the physical payload
owner, while a committed metadata inventory adopts only that Run's schema
owner. Separate preparations share physical bytes without sharing custody.
Store tests cover release, commit, another Run's live preparation, sync
failure, replacement allocation fencing, and restart after alias unlink.
The real Host fixture now returns
to zero charged schema bytes after unpublished Result-set release. This
fixes prepared Result schema custody; it does not by itself complete the
ordinary Effectful apply or final publication path.

The common MoonBit publication validator now admits an Effectful final
Receipt together with the full computation chain, Result evidence, durable
bindings, immutable publication request and attempt, and exact public index.
The index must reference the final Receipt, not the pre-effect computation
Receipt. The generated Node bridge and common Host control expose this
validator without adding a second JS chain rule. A product-shaped control
fixture accepts complete Result evidence and rejects a computation-Receipt
index, missing derivation, and foreign Preview owner. This is a commit
admission prerequisite only: the existing Store and publication coordinator
still accept Effect-free chains exclusively. No Effectful durable commit or
ordinary Effectful Run success is claimed by this change.

The local Store's `putPublicationContract` path writes complete contract wire
into an immutable physical object and links it by semantic CID. Its commit
reader compares those stored bytes with the supplied wire. The private Effect
Preview requires encrypted retention and is not in that Store's current
Run-publication admission registry. Simply adding Preview to the metadata
inventory would either fail admission or persist private Preview plaintext.
The Store now prepares keyed AES-GCM private evidence through its existing
prepared-object custody and can place that ciphertext under a separate
`publication-private` physical holding. It deliberately creates no semantic
alias before a durable holding: such an alias would survive a crash without
an owner. Local tests verify ciphertext at rest, uncommitted reclamation,
binding to the exact name and semantic CID, key rejection, holding retirement,
and reopen with a separately supplied key. This physical path is not private
Preview admission, read authorization, or Effectful publication metadata.
Effectful commit integration must bind it to MoonBit's exact Preview admission
and carry the holding through apply, final commit, and Run retention policy.
The Store must not duplicate canonical identity or final-chain rules in JS.
The common MoonBit owner now derives a distinct private Preview holding CID
from the admitted Preview, exact Run occurrence, authoring context, and Store
authority. The Host control exposes that binding only from its opaque admitted
Preview handle; a product-shaped fixture stores and reads the encrypted wire
under the derived holding. An independent fixture fixes the 0.1 preimage and
checks that changing Run or Store authority changes the holding while leaving
the semantic Preview CID unchanged. The fixture retires the holding afterward;
ordinary apply, final commit, restart recovery, and retention are still open.
The local Store can now re-open that exact encrypted holding, compare its
decrypted wire with the admitted Preview binding, and confirm directory
durability without re-encrypting or sending an Effect. A failed confirmation
sync remains retryable against the same ciphertext. This closes physical
holding reconciliation only; it is not a committed Effectful Run index.

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

The selected SGA provider in the full Node bridge had made the RelA-only
artifact gate fail. Build-time composition now derives a RelA-only bridge
from the same product source, omitting the SGA provider and refusing to
advertise SGA in its checking environment. Its Node entry shares the
standard Host lifecycle and publication policy. The artifact gate verifies
the transitive package and linked-core closure, then executes a checked
Local Program through that entry. The full selected bridge still passes
the split-Stage SGA and Effect source tests. The grouped documentation gate,
MoonBit format check, and 61 Host/boundary tests passed locally. This fixes
the packaging regression, not R2-G1 or the missing live-org validation.

Effectful checked computations now derive the same scoped Client request
identity and immutable intent preimage as Effect-free Programs. The retained
Effect closure supplies its checked Program Definition and effective
Parameter Values, not a caller-supplied raw document hash. A real SQLite
request journal test verifies same-key replay after reopen and rejects a
changed Effect intent under that key. MoonBit's JS, Wasm, and native tests
verify the common preimage and invalid request ID. This closes the request
identity prerequisite, not public Effectful submit, apply, or publication.

Run publication admission for an Effectful computation now checks the exact
prepared owner before issuing a Run Definition. The prior Host fixture used
generic evidence admission with a placeholder Parameter Values CID; the new
owner-bound admission rejected it. The fixture now derives that CID from the
checked Effect request identity and rejects changed Program Definition,
Parameter Values, Program Semantics, or Check Environment evidence. This
closes an early binding gap, not the later current-authority/apply boundary.

The common Host publication control now carries that Effect admission as an
opaque owned token through Run Definition issuance and checked Effect Run
binding. The installed Effect preparation shares the Client serializer but
remains separate from public submit. An explicit compute-only Host entry uses
the existing strategy runtime, retains the captured Effect owner, and rejects
an invalid owner. A Node/SQLite test runs checked Values-to-Effect Compute,
reopens the exact request definition, and rejects changed intent. No public
Effectful submit, mutation, or final publication is implied by this entry.
