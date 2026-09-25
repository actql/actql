# Salesforce Effect review R2 status

## Fixed completion unit at current HEAD

This branch's current unit is an ordinary Program with at least two Salesforce
Effect members and multiple rows in each member, executed through the standard
Host. The Run must preserve exact apply and recovery responsibility across a
lost response or restart, publish its final result chain, permit authorized
Result reads, and reclaim private and public holdings after their last owner.
This is one milestone within the original Connector and distribution plan, not
completion of that whole plan.

When this unit is complete, a user can submit that Program through the normal
Client, inspect or reconcile an uncertain Effect without causing another
write, read its separately named published Result, and release the Run's
retained data. The same path must report partial failure and unknown honestly.

| Remaining product connection | Required acceptance evidence |
| --- | --- |
| The public Program/Client ingress still rejects nonempty Effects. Connect the checked Effect Program and captured input owner to whole-set Preview, current authority, target guards, overlap admission, and one apply permit before the first write. | A normal two-member Program reaches apply; stale or overlapping sets send zero local HTTPS requests and consume no write credential. |
| The Host has durable row custody and a MoonBit frontier, but no standard multi-member caller drives its Salesforce Site operations from that admitted owner. Connect the captured rows to exact physical requests and retain each member's `halt` or `continue` progress across restart. | Both members have multiple rows; an independent member continues when the other halts, known rows are never resent, unknown remains unresolved without new evidence, and send counts and order match the durable ledger. |
| One-member, simulated-response publication works. Connect the real multi-member row outcomes to member/set/final Receipts, formal Store commit, authorized Result delivery, and last-owner cleanup through the ordinary Run. | Faults after dispatch claim, saved HTTP response, terminal row admission, and index commit are reconciled without reapplying writes. Distinct private Stage Result and public Program Result names survive; retained holdings are reclaimed only after their last use. |
| Declared Salesforce Catalog/read/write capabilities still need section 22.5 evidence at one revision. | A capability-to-entrypoint/test matrix covers authority, pagination, partial metadata, staleness, schema drift, rate limit, preview freshness, and unknown recovery. Local contract tests and live-org evidence are distinguished. |

The Distribution owner owns the public Client ingress, attach/status,
authorized Result reader, and package-facing contract. This branch owns the
shared Effect execution boundary and Salesforce Site connection; changes to
the Client seam must be coordinated, not implemented as a second Client or Run
manager. Live Salesforce validation additionally depends on an isolated org,
configured custom object, scoped secret-manager reference, and explicit write
permission from the user. None has been supplied, so live validation remains
unverified; local product-path and fault-injection work can proceed.

The concrete Distribution seam is the existing `prepareSubmit`/`submit`
installation: accept the same checked Effect Program and captured Run owner
used by `runCapturedEffectComputation`, then delegate authorized apply to the
Host's MoonBit-preflight/frontier and Site writer path. The public
attach/status/reconcile and Result reader must report that Run's durable
known and unknown facts without creating another Client-side Effect scheduler.
This branch will supply the completed Host/Site operation and its tests; the
Distribution owner supplies public ingress and package-facing state access.

Outside this completion unit, but still part of the original broader plan,
are new providers, Salesforce Bulk and unagreed APIs, Cloud OAuth operations,
other distribution modes and frontends, and the separately managed performance
branch. Moving these items outside this unit does not mark them complete.

## Latest completion gates

The follow-up review at `b3aecf969` is tracked as two open gates. SF-G1
requires an ordinary checked, multi-member, multi-row Program to carry its
exact Effect inputs through authorized apply, restart reconciliation,
publication, delivery, and cleanup. The shared publication coordinator now
accepts an issued set Receipt tied to its exact Ledger and Preview. This
component connection does not satisfy SF-G1: the publication fixture has
only one member and does not execute Salesforce HTTP writes.
The completed computation now retains its exact Result export owner,
retention inventory, and Effect-source Artifact contracts. Its final-chain
preparation rejects a copied computation or foreign Preview. This closes a
provenance seam but still stops before apply and publication.
The installed Host fixture now carries a real checked Compute and its distinct
private `rows` source and public `answer` Result through encrypted Preview
holding, Effectful Store commit, replay, Result retirement, and metadata
retirement. Its publication test now saves two row responses and terminal
receipts in the real Effect Ledger, reopens that Ledger, rejects physical
resend, issues the member and set receipts from saved rows, and commits the
final publication. MoonBit rejects a foreign publication Preview at the
Ledger-to-publication seam. The physical responses in this fixture are
simulated, and it covers only one Effect member. It does not establish
whole-set apply admission, real Salesforce I/O, the multi-member fault
matrix, or the public Client submit/delivery path required by SF-G1.
The Effectful commit test also reconciles a lost Store acknowledgement without
reissuing the set, while private holding tests retain one prepared ciphertext
across failed commit retry. Provider-linked multi-member publication remains
required.
The checked two-member Host fixture now leaves one member's first row in
possible-dispatch state, reopens the Ledger, and sends both rows of the other
member through a local HTTP endpoint. MoonBit's captured frontier keeps the
first member blocked under `halt`, permits the independent member, and issues
an `unknown_outcome` set without resending the uncertain row. This is a
regression of the retained owners and durable progress, not a standard apply
caller or formal publication of that two-member Run. The endpoint is local
HTTP, not a credentialed Salesforce Site.
The same fixture now retains exact private Effect-source Artifacts for both
members, sharing one immutable physical allocation through two independently
retirable Store holdings. The Captured Run records both source holdings and
keeps the private `rows` inventory distinct from the public `answer` Result.
After Ledger reopen, its durable mixed known/unknown set cannot be published
as a successful Run; the Preview and both source holdings remain available for
reconciliation until explicitly retired. This closes an inventory and
holding connection, not the ordinary apply caller, successful multi-member
publication, or credentialed Salesforce request path.
The Host now has one captured-Effect apply driver that runs the existing
MoonBit whole-set preflight before the first durable claim and takes each
next row from the MoonBit frontier over real Ledger heads. Its two-member
regression rejects stale bindings with zero claims, rejects a Site callback
that makes no durable progress, and resumes the independent member after an
unknown first member. The Site callback still uses a local HTTP fixture, and
the public Client has not yet installed this driver or the Salesforce writer.

SF-G2 requires a capability-to-evidence matrix for every advertised
Salesforce read, metadata, and write operation, followed by isolated-org
validation when credentials and write scope are authorized. Local tests are
not live-org evidence. Neither gate is closed by Receipt or Store tests.

Review baseline: `15904a32f31573a86a3507253f3eaa1b010adf78`.
Prior implementation and verification baseline:
`40ef6ad720e93b98c2c42e6f7ec0bb170682f135`.

The follow-up review in `02-salesforce-effects (2).md` repeats this
coordinate finding and distinguishes it from the still-open ordinary Run
integration. Its fixed SHA predates the coordinate and Host regressions
recorded below. The finding is not a second implementation task.

At `d0ae9638747e64ba523dd7ea05ffc89c263c732e`, the R2-1 code path
retains both authored `stage` and resolved producer `task` in the checked
source. The same expanded graph resolves `port_target` to that Task; batch
and single pin entry points both consume `source.task`. The split-source,
preceding-split, shared-pin, port-close, and foreign-owner regressions remain
in the product tests. A local rerun of `client-program-bridge.test.mjs`
passed 17/17. This is evidence for the coordinate fix, not a claim that the
review's local HTTPS no-send scenario or R2-G1 is complete.

R2-G1 is incorporated as the remaining vertical acceptance target: one
ordinary checked/captured multi-member Run must retain all input owners,
admit the whole Preview and current guards before any write, persist exact
pre-send claims and raw/typed row observations, reconcile known and unknown
outcomes without resending, then derive member/set and final Run receipts
through durable publication. The fault matrix must cover boundaries around
physical dispatch, raw response, typed outcome, and final commit. The tests
must assert that stale or overlapping work sends zero writes and that an
independent member proceeds when another member halts. The current component
fixtures below do not constitute that product-path proof.

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

The captured-input MoonBit owner now provides one semantic preflight over
complete Plan proofs, current source/Contract/capability/authority bindings,
target guards, selected routes, risk acceptance, derived keys, and whole-set
footprints. Both Node bridge profiles expose the same check. The real Host
fixture accepts a two-member Preview and rejects missing proofs, foreign
bindings, missing guards, a foreign route, insufficient risk claims, wrong
keys, and released input pins. Its members use distinct Effect identities so
their guarded row CIDs identify distinct rows. This is not a send permit:
the ordinary Host must authenticate current external facts, retain the
captured owner, and carry a non-forgeable admitted authority through common
durable dispatch. Salesforce Site writers still do not receive that owner,
so R2-G1 remains open.
Plan proof issuance and complete-member inventory admission now live in the
shared `physical_strategy` owner. Both the full and RelA-only Node bridges
call that same MoonBit implementation; their duplicate proof types and
inventory loops were removed. Three-target tests, the real Host bridge, the
RelA-only product artifact, public interfaces, and documentation gates pass.
This gives the future whole-set apply owner a portable, non-forgeable payload
proof, but does not itself admit current authority or unlock dispatch.

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
Result set and an admitted private Preview. Its product fixture publishes
Program Result `answer` while the Effect consumes Stage Result `rows`.
Captured Run 0.1 retains the latter in a separate exact Effect-source
Artifact inventory and holding inventory; the regression asserts that it
does not masquerade as a published Result. A foreign Artifact in the Preview
is rejected. Issuance does not publish or release the prepared Store owners.
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
admission prerequisite. The Store now accepts the exact Effectful chain, but
the ordinary publication coordinator still accepts Effect-free Runs only.
No ordinary Effectful Run success is claimed by this change.

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
Preview read authorization or apply admission. Store commit now binds the
holding to MoonBit's exact Preview admission and durable Run metadata;
ordinary Effectful apply and Run retention admission remain open.
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
holding reconciliation. A later Store commit now uses that check before
installing the Effectful public index.

The next final-Receipt integration must start with durable row outcomes, not
with a Host wrapper around `issueEffectfulFinalRunReceipt`. The current
SQLite Effect Ledger stores possible-dispatch heads and raw HTTP responses;
its `outcome_receipt_cid` is an exact reference but does not itself prove a
provider projection, typed row result, or member/set partition. The common
MoonBit final-Receipt issuer currently validates the references supplied to
it, while its contract explicitly leaves physical outcome admission to the
Host. A direct wrapper accepting caller-assembled member receipt wires would
permit a fabricated successful result to reach final issuance. The required
order is: admit each stored physical observation under its exact claim,
durably record the typed row outcome and its receipt, derive member and set
receipts from those admitted heads, then issue the final Run Receipt from the
same captured computation owner. Unknown remains possible-send and cannot be
converted to failure or retried as a new physical send.

The common MoonBit member-row evidence gate now checks a candidate member
receipt partition against the exact admitted Preview row order, each Ledger
basis and durable head, active physical ownership, and the CID and state of
each physically re-admitted terminal row Receipt. A restarted real-SQLite
Host fixture accepts an applied row plus an unattempted row and rejects a
missing terminal Receipt or a still-active owner. The gate deliberately
returns only a partition check: the member's aggregate typed outcome is not
yet derived from the row observations, and the ordinary Host does not yet
issue or durably commit member, set, or final Run Receipts through this gate.
The product SQLite reader now takes one durable head snapshot for a candidate
member, re-admits each terminal row Receipt from its saved response, and invokes
that MoonBit gate. A common Host wrapper first authorizes evidence viewing for
every exact dispatch, retaining an owned claim snapshot across asynchronous
authorization. Real SQLite and local HTTPS Collections tests cover restart,
partial row outcomes, denied evidence viewing, and reordered rows. This still
does not authenticate or issue the aggregate member outcome.
The progress reader now takes all member heads in one SQLite read snapshot,
so concurrent writers cannot make one frontier from different revisions.
An active physical call remains active by its logical row owner even if its
durable head advances to `unknown` during settlement. The common frontier
therefore does not open a later row of that member until the physical call
actually settles; after settlement the unknown fact remains for reconciliation.

The shared Effect apply Receipt admission now accepts a member with known
applied or accepted rows and later unattempted rows as `partial_failure`.
Its previous guard required an explicit failed row, contradicting the 0.1
halt/continue receipt rule and preventing this ordinary partial outcome from
being recorded. The three-target Run publication suite passes 122/122 on
JS, Wasm, and native. This semantic admission fix does not establish the
missing physical row-outcome custody or final publication path.

The physical SQLite Ledger now retains one bounded outcome record per exact
dispatch entry and links it to the already stored response's physical digest.
Single and Collections rows have separate owners even when they share one
HTTP response. The Store checks capacity, collisions, metadata integrity and
restart recovery; it does not admit the outcome's semantic body or authorize
a terminal ledger transition. The common MoonBit outcome issuer, provider
projection binding, member/set receipt derivation and product caller remain
open. Local Salesforce Site tests pass 120/120 at this increment; this is not
a live-org or same-SHA Linux CI result.

The common MoonBit row check now binds a closed canonical `EffectOutcome`
projection to the exact admitted Preview member and row. Salesforce single
and Collections projections use it; a shifted Collections row or foreign
member is rejected. This is typed shape and row binding, not proof that the
physical response produced the projection. The Host Ledger can also reopen
an outcome record only through its original exact dispatch claim and saved
response. A common evidence-read path checks current read authorization
before that access. Real SQLite restart tests cover single and Collections
custody, distinct row owners, foreign order, and zero resend. The Site suite
passes 122/122 and common publication tests pass 124/124 on JS, Wasm, and
native. The original physical response and row outcome remain readable after
the durable ledger head advances to applied or failed. Real SQLite tests
cover both terminal single and mixed-terminal Collections rows after reopen;
the Site suite still passes 122/122. Those tests append synthetic terminal
facts. Product issuance of semantic outcome Receipts and their terminal
transitions remains open; physical records alone are not successful writes.

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

The local Store's Effectful stored-evidence check asks
the common MoonBit owner to admit the final chain and exact public index,
compares every supplied public contract with stored bytes, confirms the
encrypted private Preview under its derived holding, and confirms every
captured Effect-source holding and public Result binding. A real Store fixture
rejects an Effect-free index, altered private wire, and omitted source holding.
Store commit now installs the public index only after this check and retains
the private and Effect-source holdings in its durable metadata inventory.
Reopen revalidates the exact chain; metadata retirement reclaims both holdings.
A confirmed non-commit retains its inventory until an unshared physical
holding is explicitly retired. These Store operations do not admit physical
row outcomes or issue the final Receipt from an ordinary Effectful Run.

The common MoonBit Effect owner can now issue a member Receipt from one
durable row-head snapshot. The Host first authorizes evidence viewing, then
re-admits each terminal row Receipt from the exact saved response. Unknown
rows retain their dispatch and ledger-head references; unattempted rows have
no invented terminal outcome. The issuer rejects an active physical owner,
missing terminal evidence, or a foreign row binding. A real SQLite restart
test compares the issued Receipt with the independently sealed fixture and
checks an unknown/unattempted partition. This does not yet issue the set
Receipt from every member or connect the standard Effectful Run apply and
publication path; R2-G1 remains open.

The 0.1 Effect Set Receipt can now be issued by the common MoonBit owner from
one exact member Receipt per Preview member. Its member and set states use the
same aggregation rules as reference admission; member replay observations
remain explicit because terminal row state alone cannot establish replay.
The Node Host evidence path issues each member from saved SQLite facts before
asking MoonBit to issue the set. A two-member restart fixture covers applied,
unattempted, and mixed partial-failure aggregation. The issued set is not an
apply permit or a durable final Run commit, and replay flags still require an
authoritative standard Run caller. R2-G1 remains open.
