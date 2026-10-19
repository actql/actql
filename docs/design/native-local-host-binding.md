# Native Local Host binding

This records the adopted trust and credential boundaries for the standard
Native Local CLI. These are implementation requirements, not claims that Local
execution or Provider approval has passed public acceptance. The existing
Native Remote CLI, its wire contracts and distribution remain intact.

## Explicit configuration adoption

The operator explicitly selects the configuration, execution account and private
user-owned Host state. Directory discovery, a Program or a URI cannot select
trusted authority. Merely passing a file to the preparation-only CLI is not an
adoption operation.

Adoption durably binds the exact selected source/configuration, admitted account
configuration, account, adoption/profile identity and managed-root identity.
Retain the original bytes and their identities; configuration identity rules do
not normalize Program, Model or Effect data values. Physical containment must
bind the selected root and reject symlink/path aliases that escape it.

Use the existing Native journal and its physical custody boundary. Do not create
a second Local journal, execution Owner, scheduler or approval mechanism.
Current admitted operator configuration determines current authority. A Run
retains the historical configuration and authority binding under which it was
admitted; current settings cannot silently replace those originals on restore.
Authority expansion requires explicit adoption. Restriction or deletion never
causes automatic profile reapplication or regeneration of removed grants.

An initial profile is published content whose finite body, identity preimage,
CID and containment rules have independent expectations before shipping. Empty
authority is valid. Connectivity, Connector registration and adoption do not
generate Provider read/apply permissions. Source read and Effect apply remain
independently authorized at their existing boundaries. Approval does not supply
otherwise denied authority.

Ordinary reconnection is retained-only. It cannot create a state child, stage
an absent account copy or initialize a database, key or epoch. Only the explicit
adoption operation may continue a matching unfinished initialization. The
operator must first select a private configuration root; configured physical
libraries are not loaded from an untrusted discovery root.

## Initialization and interrupted adoption

Freshness requires an exclusive, explicitly selected private Host-state creation
and matching durable initialization intent. A missing configuration, adoption
row, key or database is not freshness evidence. Bind the real private state and
managed-root custody rather than accepting caller-supplied labels as proof.

Persist a one-time initialization intent under an exclusive fenced claim before
creating configuration content. Create without overwriting an existing file.
Confirm the exact created file identity and durably finalize adoption before
protected dispatch. Config creation and a journal commit are separate physical
events; their combined result is not assumed atomic.

| Observed state | Required action before protected I/O |
| --- | --- |
| Explicit fresh state, exclusive claim, no conflicting content | Persist intent; create exclusively; confirm identity; finalize adoption. |
| Matching recorded intent, creation not yet performed | Continue only under the original fenced claim and exclusive creation. |
| Matching intent and exact created content | Recover that initialization; finalize the original adoption without rewriting content. |
| Finalized adoption with matching custody/configuration/account/root | Open existing Owners and evaluate current admitted authority. |
| Concurrent initializer | Refuse or observe the original claim; never create a second initializer or combine grants. |
| Existing config without matching initialization/adoption proof | Refuse protected dispatch; require explicit recovery rather than overwrite or merge. |
| Divergent file, foreign account/root, ambiguous creation or lost custody | Refuse protected dispatch; do not reset keys or infer that execution never occurred. |
| Adopted configuration removed | Preserve adoption and original Run evidence; do not regenerate permissions. |

An unknown commit response requires reopening and inspecting the original
durable intent/adoption under its original identity. It is not permission to
retry fresh initialization, send a Provider request or create another Run.
Physical cleanup failures retain the existing Owner and retry handle; the
failure must not convert unfinished adoption into a fresh environment.

The first assembly slice selects private user-owned configuration and state
parent directories explicitly. It exclusively creates one named state child
and binds both real roots, the source file generation, exact source bytes,
admitted account/CID and original initialization nonce. The account document
budget is 1 MiB; initialization and physical configuration witnesses are
bounded to 8 KiB each. Explicit entries, including an empty entry set, are
accepted without generating a bootstrap profile. A named bootstrap profile is
refused until its original is installed and verified.

The immutable initialization intent precedes exclusive configuration creation.
The separately persisted configuration witness binds its actual device, inode,
length and original intent CID. An existing state child without its intent,
or copied configuration without its creation witness, cannot become fresh by
retrying adoption. Completed staging and an intent preceding creation can be
reopened under the same filesystem lock and original bindings. This staging
boundary is not final journal adoption and grants no protected execution.

Restoration uses the existing SQLite adapter's retained-only open, after format
and custody admission. It refuses missing/empty databases and missing schema
constituents without creation, migration or schema repair. Fresh initialization
has a separate exclusive creation proof; ordinary open or physical absence is
not that proof.

The explicitly selected runtime configuration originals accompany account
adoption. The bounded selection admits at most eight distinct single-component
file names, each with at most 64 KiB of exact bytes. It excludes the separately
bound account file. Its immutable manifest records raw-content digests, source
file generations and the actual selected private managed-root identity. The
manifest is bounded to 8 KiB and is included in the initialization intent.

Finalization stores this manifest and the selected original bytes in the
existing SQLite transaction with Submission epoch custody and final adoption.
Reopening checks exact membership and original bytes, source generations and
managed-root custody before returning configuration or authorization material.
Missing stored originals are not copied back from a currently available source,
and a byte-identical replacement file cannot assume its predecessor's identity.
These configuration records confer no execution permission; the existing
execution-account Owner evaluates each current access tuple.

### Initial signing-key material

The selected Native Crypto Library can generate fresh Ed25519 material for
trusted initial installation. This synchronous operation returns secret PKCS#8
PEM bytes and the corresponding public SPKI PEM. Its temporary private DER is
explicitly cleared after encoding; that does not retire the returned PEM,
copies, Writer or escaped aliases. OpenSSL key/context handles are released
before return. Optional generation symbols do not change legacy Library load,
verification or signing requirements.

Generation does not adopt a Store, signer, physical key generation, public-key
CID, grant or credential use. The existing installer must first establish its
exclusive original initialization, then retain the actual private Writer and
file generation through durable creation and close acknowledgements. A missing
key in an existing or ambiguous Store cannot select fresh generation. Current
Reviewer/Checkpoint authorization, original key/public-key correspondence and
operation-bound signing uses remain independent of these newly generated bytes.

### Exclusive initial signing material

The existing adoption session may consume the original exclusive directory
creation once to generate a private signing file. Eligibility is a shared private
cell across session aliases, never an input Boolean or a condition recovered from
missing files. Reopened, partial or conflicting initialization is refused without
key generation. The same actual Writer is acquired before secret generation; an
unconfirmed write, seal or retirement preserves its original issue and partial
names. A retained-close acknowledgement concerns only the original descriptor and
directory sync, not publication or namespace cleanup. An unsuccessful constructor
likewise retains its actual Writer for cleanup without granting write authority.

The resulting private view binds the original session, Store root, file
generation and private projection. The public key remains DATA until the existing
authenticated installation journal adopts the same physical original. It is not a
source-root key original, configured signer, credential grant or current signing
permission. Missing old key originals are not repaired by generation or capture.
The Library, temporary key buffers, private/public encodings, Writer and escaped
view overlap still require the existing actual caller resource supply; format
lengths and a diagnostic ceiling are not numerical funding.

### Authenticated initial Store signing original

A trusted explicit first installer can carry that same session's opaque material
and the pinned Common bootstrap policy into the existing journal initialization.
The original marker and physical database inspection, not a caller Boolean,
select the first branch. The existing initialization transaction establishes the
epoch key and authenticates a closed initial-signing payload with that same key
before inserting the installation control row and confirming COMMIT. It retains
the original initialization intent, Host adoption, Store-root file projection,
public-key body/CID and original PEM, exact policy body/CID, issuer identity and
ReviewerProof purpose. The issuer identity comes from the Common policy Owner's
original-intent projection; the payload does not issue an operational grant.

The ordinary launcher requests this initial material path only after admitting
the installed Native image and exclusively preparing the project for explicit
`init`. Its private adoption request does not prove freshness: the same Native
session must independently consume its original exclusive creation. Ordinary
adoption without that request retains the legacy journal path. A request against
existing or ambiguous state refuses instead of falling back, replacing a key or
backfilling policy. Neither successful initialization nor a restored original
selects a default signer or supplies Reviewer, issue, claim or signing permission.

This is a closed alternative in the existing installation `host` control row.
The historical raw adoption body remains a separate exact alternative. The
adoption body/CID and initialization body/CID themselves do not change. The
`issued` counter, setting-original rows and their `files.length + 1`, eight-object,
8192-byte reservation and 2048-byte authenticated-payload bounds do not grow.
The complete nested record must fit the existing codec/snapshot limits or the
same transaction refuses it. Intake bounds are not physical read or workspace
funding. No extra row, issuer file or replacement policy ledger is introduced.

Restore authenticates the exact retained payload with the current original epoch,
admits policy and public-key originals through their existing Common Owners,
checks original intent/adoption/purpose/root role, and restores the same physical
private-file projection. A returned view retains its Host, Library through that
Host, original projection, policy and public metadata; current access fences the
same retained row and physical generation again. A configured source-root key
stays source-root, and a HostAttestation key cannot alias this ReviewerProof key
by physical file or raw public-key identity. An old raw row, missing metadata,
foreign policy/epoch/key, changed control revision or Unknown initialization
never chooses a fresh capture. Lost COMMIT acknowledgement preserves the same
operation and its uncertainty; lookup can observe an authentic committed original
but cannot create a replacement key, policy or claim. Read failure retains its
original typed cause; if transaction retirement also fails, both causes survive
in the same existing Host error path, and the database remains fenced.

This physical metadata seam is not default-signer selection, Account/Reviewer/
Run authorization, first issue, use claim, signature or public approval. Those
existing operational gates must independently bind the exact original purpose,
Checkpoint, preimage and use. First issue alone samples the trusted clock and
persists the finite absolute expiry; initialization and restore do not sample or
renew it. Configured/named signers and the generic explicit issuer-file route
retain their separate original authorization, and a missing legacy supplier stays
unavailable. The actual caller must retain the overlapping session/material,
HMAC/codec workspace and escaped view until their own physical acknowledgements.

The private initial Reviewer registration joins that same physical original to
an already-adopted public Host configuration without explicit signers and the
actual selected machine actor's independent current `run:resolve` Account
decision. The actual public-key CID labels the key; the actor labels the
Reviewer. Neither label supplies authority. Named selection and any explicit
signer map refuse default fallback. Replacement of the Host configuration,
Store key generation or original installation retires this view. Configured
Reviewer/key readers cannot consume the initial registration as their own file.
The subsequent binding uses the configured route's same original Checkpoint,
Client read and paired-scope checks. This registration still supplies no issuer
grant, private-key acquisition, durable claim, signature or approval application.
Its original Host/configuration/key and Account reads retain their overlapping
workspace and lifetime; parsing ceilings are not reservations or close receipts.

The initialized key may also supply the existing opaque Reviewer proof material
through a closed key variant. Its configuration identity is the existing digest
of the authenticated initial control body, and its generation identity is the
existing digest of the retained Store file projection. This introduces no CID
domain, configuration file or permission. The same original Checkpoint snapshot,
unsigned proof, authenticated Submission and paired-capture readers remain in
use. A final noncallback key/Host generation check follows the existing original
subject fence. The explicit issuer-file operation retains its configured
source-root key and cannot consume the initialized key variant. This connection
reads projection metadata only: actual private-key correspondence, durable
first issue/sample/expiry, same-use claim and signature remain independent.
The key variant and its small scope record retain the original Host, policy,
projection and installed Reviewer throughout overlapping current callbacks;
these references, record storage and read workspace are not free aliases or a
physical cleanup acknowledgement.

The default-only first-issue storage phase uses the same immutable grant packet
and Journal transaction, with an additional closed authenticated installation
payload. The original epoch HMAC binds the first clock sample, any earlier
original validity bound, pinned policy, initialization, exact grant/operation
and selected Host configuration/connection. The grant retains the absolute
expiry and one-use limit. The existing full grant/Run custody census and original
Submission authentication remain in place; the default branch additionally
restores the same Store-root key generation. The configured issuer-file branch
and its packet bytes are unchanged. Existing payload, packet, work and per-request
reservation bounds apply without relaxation.

That private storage phase reads an existing operation before sampling the
clock. Its exact original use/outcome is history only; missing or corrupt use
custody cannot select another sample, expiry, claim or ordinal. The first
retained default operation also fences its same original Submission, Checkpoint
and purpose; a different operation/attempt plus decision preimage cannot bypass
claimed or Unknown custody. This default-only restriction leaves configured
issuer-file operations' existing exact key/preimage rule intact. A first append,
exact attempt-bound use claim and trusted-clock lower bound share the existing
transaction and rollback. Lost COMMIT acknowledgement fences that original
responsibility. Neither the private stored result nor authenticated metadata is
a physical signing permit: the enclosing original operation must retain its
paired Checkpoint, current Client/Reviewer/key gates, exact purpose/earlier bound
and material custody through actual physical signature and final acknowledgement.
No public default-signer or Node physical supplier follows from this storage port.

### Initial signing payload DATA

The original initial-signing installation payload has a typed DATA codec in
the existing Common Local original-record Owner. Its thirteen String fields
keep the Native field order, spelling, escaping and existing record budgets.
Both creation and restoration use that same closed record definition; a
consumer need not maintain a second key vector or interpret positional fields
outside this Owner. Nested policy/public-key original bytes and PEM text are
retained exactly, not normalized by the codec.

The decoded field record is not the Native opaque initial-signing original.
It authenticates no Store, epoch/HMAC, actor, physical file generation or
current installation. Existing policy/public-key admission, PEM/raw-key
correspondence, native projection-layout checks, purpose separation and the
original transaction/current fence remain mandatory in the physical consumer.
A missing legacy original still cannot be filled from today's configuration.
The field record, thirteen String references, codec arrays and decode/encode
workspace belong to the existing installation/Host inventory; they supply no
funding, grant, claim, key use or cleanup acknowledgement.

### Writer close custody

The existing filesystem Writer records its original close outcome separately
from later diagnostics. A consumed but unconfirmed close remains pending through
seal/cancel retries and finalization; it never closes a reused descriptor or
unlinks partial material as if cleanup had succeeded. An acknowledged close is
idempotent, while failures before close leave that first physical close available.
This preserves the original Writer's custody rather than issuing key adoption or
converting process exit into a creation, cleanup or signing acknowledgement.

### Private Root rejection cleanup

The private Root constructor retains its own descriptor-close outcome when
privacy validation rejects a pinned directory. A failure before acquisition
acknowledges only that no descriptor remains from this constructor; a confirmed
rejection close is idempotent. An unconfirmed close retains the original Root
and diagnostics, stays pending and never closes a reused descriptor. Neither
result admits the rejected directory as a current or authorized Host Root.

The additive private-Root custody entrance returns the existing
`NativeRootOpenFailure`, retaining its constructor refusal independently of any
cleanup diagnostic. Its `retry_cleanup` acts only on that same rejected Root;
a missing descriptor or confirmed close clears that reference, while an
unconfirmed close keeps it. The successful privacy/containment predicates remain unchanged. The custody
constructor uses the existing observed namespace walk even before it has a
final Root descriptor. Private-current observations use that same walk and
cannot resume after an unconfirmed temporary close. The first namespace close
failure remains original even if cleanup encounters another one. The failure object issues neither
a usable Root nor Host adoption, and cleanup cannot retry acquisition.

### Private Root under the original read context

`open_private_root_in_current_read_context_with_custody` uses the same active
original Native read context as the scoped generic Root entrance. A missing
context or nonpositive diagnostic bound refuses before UTF-8 encoding or Root
acquisition. The private constructor still applies its existing namespace,
owner, mode, ACL and no-follow checks; entering a read context does not grant
filesystem permission or admit a directory as the Host installation.

The constructor retains the original context use before entering physical
allocation. It publishes the same acquired Root into custody before leaving,
including a rejected Root and its diagnostic aliases. Only confirmed physical
cleanup returns that Root's context use; escaped managed Root/diagnostic aliases
can still keep the original backing busy. A failed close, managed return,
reference retirement or GC opportunity is not a physical acknowledgement.
The path String, UTF-8 backing, acquisition carrier, Root/failure record,
descriptor, diagnostic bytes and context references overlap under the original
Host/installation phase envelope. The diagnostic ceiling is not funding.

The enclosing caller must enter its independently admitted original Domain
around the whole managed operation and perform its Core/current fences. This
entrance issues no context, capacity, permission, Host binding or installation
authority. In particular, it does not combine the currently separate original
read and installed SQLite Domains or authorize an unbound SQLite fallback.
Missing original bootstrap, whole-phase or retained-alias coverage remains
unavailable.

The existing-adoption consumer has a separate scoped entry. It uses the same
Adoption constructor, original configuration selection, exclusive lock and
failed-acquisition carrier. Its closed internal Root opening selects the scoped
private constructor for source, parent and optional managed directories alike;
no legacy Root substitutes for a missing context. The legacy entry retains its
original behavior. Neither entry initializes a missing Host, and a scoped Session
does not combine its filesystem context with a selected SQLite Library context.

## Direct Local credential grant/use scope

### Explicit post-adoption issuer acquisition

The initial adoption identity remains immutable. The complete grant is issued
and appended only by an explicit authorized operation after the original Run
and its post-approval resume intent, claimant and generation exist. It is not
embedded in the initial configuration, automatically issued by submit/approve/
resume, or replaced after an unknown acknowledgement.

An issuer selection is a finite file explicitly included in the original Local
installation selection, using the existing `actql-config/0.1` format:

```json
{"version":"actql-config/0.1","native":{"credential_issuer":{"enabled":true,"issuer_authority":"credential-authority-a","principal":"operator","connection":"cli","max_uses":2,"expires_at":"2099-01-01T00:00:00.000Z"}}}
```

`NativeLocalHostConnection.acquire_credential_issuer` obtains an opaque binding
through the existing Account Owner's `bind_dispatch_authorization`. The exact
tuple is the selected principal and connection, resource
`credential/<issuer_authority>`, operation `issue`; its subject is the original
issuance/adoption intent CID and its context is the real Host authority scope.
No permission is inferred from the issuer name, parsing this file, explicit CLI
invocation, submit, Source read or Effect approval. A principal need not be human.

The binding rechecks the original Host, exact file generation/content, current
Account decision, subject, scope and expiry. A replacement file with identical
bytes is refused. It is an issuer decision, not a grant or send permit. The
grant append must separately verify the original checked Effect, exact Provider
request and credential installation, the real opaque current resume claim and
lease, and the original use/Effect Ledger state in the existing journal
transaction. Missing or unknown originals cannot be repaired by acquiring
another binding. Cancellation retains observation and cleanup responsibility
while preventing new protected use.

The common credential Owner produces the exact Local grant. Its immutable
operation identity and grant bytes/CID belong in bounded appended custody of
the same private Native journal/capacity Owner. Lookup addresses that original
operation under current authorization, without issuance, expiry extension or
use-limit renewal. Initial secret installation remains independently owned.

Add a distinct typed Direct Local scope to the existing common credential
grant/use Owner and its Native physical adapter. Do not encode Direct Local
work as a Remote Site, runtime bundle or DispatchRequest. A Client request or
Effect Ledger CID does not inhabit those identity domains.

The existing Remote wire, identity preimage and CID domain remain unchanged.
Local and Remote scopes/grants are distinct alternatives and cannot substitute
for one another. The Local contract binds these actual inputs:

- Local Host, account, original adoption and current authorization identity.
- Original Run invocation and the checked unit/operation occurrence.
- Original attempt and credential-use fence.
- Connector registration/revision and the exact Provider target/request.
- Applicable expiry and the original grant/use identity.

The grant/use Owner validates these bindings before credential use and send.
Recheck current Source read or Effect apply authority, installation identity,
expiry and cancellation fences at their existing boundaries. Approval is
additional evidence, not a substitute for current authorization.

Sending follows the existing durable send-start record. A confirmed response is
reused under its original request and attempt. A possibly sent request remains
unknown and retains reconciliation custody; neither reopening credentials nor
restarting the CLI permits a blind resend. Retain responsibility for observation
and cleanup of started work after cancellation.

### Typed credential originals

The common credential Owner exposes separate `LocalCredentialScope`,
`LocalCredentialGrant` and `LocalCredentialUse` types. Remote grant/use types,
their wire and CID preimages remain unchanged. Neither decoder accepts the
other domain. Constructing or decoding a Local original proves its bounded
shape and identity, not current authorization, approved execution or secret
access. The Native Host must supply the actual original bindings and current
checks before the existing physical credential Owner can consume a use.

The Local scope binds account ID and configuration CID, Host adoption CID,
current authority scope CID, original Submission scope and Run invocation,
checked unit and operation-occurrence CIDs, original attempt ID, Connector
registration/revision, Provider operation/origin/path/method, checked semantic
request CID and the raw transport-body CID. The body CID hashes exact bytes,
independently of semantic request canonicalization. It preserves Unicode,
line endings, absent fields and explicit NULL rather than applying
configuration normalization.

For the initial approved Effect connection, the fence consists of the existing
resume intent CID, original claimant and positive Int64 generation. There is
no invented Site/Dispatch identity or placeholder fence CID. These scalar
bindings do not replace the opaque original claim handle: the physical caller
must still check the current common resume fence, cancellation and Effect row
claim in the original journal transaction. Observation-only settlement cannot
authorize a new send.

The grant wire `actql-local-credential-grant/0.1` is a closed flat object with
the scope fields plus `issuer_authority`, `expires_unix_ms`, `max_uses` and
`version`. Keys are emitted in lexical order using the existing value-preserving
writer. Expiry and fence generation are canonical decimal Int64 strings;
`max_uses` is an integer from 1 through 1,024. The grant is bounded to 32 KiB,
64 value nodes and depth 2. The whole UTF-8 body is the SHA-256 preimage.

The use wire `actql-local-credential-use/0.1` contains `grant_cid`, `use_id`,
`use_ordinal` and `version`, with the same key ordering and shared credential
record writer. Its whole-body SHA-256 identity is bounded to 4 KiB, 12 nodes
and depth 2. Restore admits the exact saved bytes and ordinal; it neither
claims another ordinal nor refreshes lifetime. The existing physical Owner
retains responsibility for durable use consumption, revocation, uncertain
sends and observation. No Local credential journal is introduced.

Native request bodies remain within the existing 65,536-byte ceiling. The
initial request methods match the installed Native adapter: GET, POST, PUT and
PATCH. GET binds the actual empty-body digest. Declaring an origin, operation
or body digest cannot expand the installed operation allowlist. Grant issuance
must have explicit trusted inputs; adoption, Program submission and approval
alone do not create credential permission or a new grant.

The Native adapter dispatches the distinct Local and Remote grant/use types
into the same credential claim, send, outcome and query implementation. Both
domains use the existing database, trusted clock, revocation records and
credential-use scopes. Local installation requires its own typed authorization
callback; a Remote installation cannot authorize a Local use by default.
The Local send entrypoint also requires a current guard. Trusted Host assembly
must check original adoption, current authority, checked operation and the
opaque execution claim in those callbacks. Pure scope equality and a caller's
Boolean are not evidence that these checks have occurred.

Before claiming a Local use, the adapter isolates the transport bytes and
matches their digest, method and installed path against the grant. It retains
the existing durable ordinal/use claim before I/O, current checks before send
and saved outcome after I/O. Restoring or querying a use does not claim another
ordinal. Claimed and unknown outcomes remain distinct from unsent work and
never authorize automatic resend. These adapter obligations do not replace
the Run approval, send-start, reconciliation or cleanup Owners.

The physical SQLite claim transaction already distinguishes a fresh ordinal
from the retained original. Native credential sending preserves this fact:
only a newly committed claim can install a use and approach I/O. A retained
claim readmits its exact saved use and checks the original ordinal, then returns
`UseAlreadyClaimed` without inserting or repairing it. Missing or corrupt use
custody returns its typed refusal instead. Explicit query uses the same saved
use readmission; physical uncertainty remains a typed refusal.
`UseAlreadyClaimed` does not assert a saved outcome or semantic Effect completion.

Credential query reports transport facts only. Its `succeeded` value means a
stored HTTP success status, not a confirmed Effect outcome or retained response
body. The existing Effect response and receipt Owners supply those originals.
A missing use record, claimed use, unknown outcome or terminal-record failure
does not establish that a request was unsent or can be sent again.

## Public execution and restoration

The preparation identity uses the separately adopted closed
`actql-local-preparation-fence/0.1` body: original Client intent/scope, checked
operation occurrence, actual Run invocation and checked Unit definition. Public
body/CID admission verifies identity only. It cannot create an operational token,
resume generation or credential permission. Existing Local resume and Remote
grant bodies/CIDs are unchanged.

The original Work's durable first-start seam now produces a private witness
only after a successful new start and final current authorization/cancellation
check. The same Effect Work retains it before acquisition. False or unknown
claims do not return a witness, and reopening a started Run cannot mint another.
The observed Run revision is independently current, never part of this immutable
identity. Evidence borrowing and cleanup retain their existing paths after a
Checkpoint; a preparation-only check cannot redefine those responsibilities.

Binding the complete identity to actual checked occurrence/invocation and the
GET-only preparation grant/Catalog request is still required. Source-bearing
invocation evidence is obtained from the original captured Source owner, not a
replacement invocation template or fabricated future CID. The first-start
witness is not itself a checked target-read grant. Matching Native target
observation and public recovery remain separate, unexecuted acceptance.

Private grant-original custody now has a bounded appended packet separate from
the initial adoption preimage. The user-chosen operation ID and original
Submission scope determine its stable lookup key. The intent binds the exact
grant CID and selected issuer original; changing grant bytes changes the intent,
not the original operation ID. Records are immutable, and the existing journal
transaction commits packet and custody count together under its capacity Owner.
Per-Run custody is limited to 64 originals and 65,536 bytes, with reservation
before packet encoding. Lost originals, witnesses or reservations refuse without
repair. Lookup never issues a grant or mutates the Run control revision.

The private append additionally requires the real current post-approval resume
claim, original issuer decision and exact retained scope/limits. A possibly-sent
Effect row cannot obtain renewed credentials through this path. These helpers
are not publicly callable: the actual checked Provider request and installation
must still be supplied by the trusted Host assembly before a CLI grant operation
can consume them. Stand-alone packet/custody fixture definitions do not prove
Provider authorization, physical approval, crash recovery or public CLI success.
Pre-approval target observation uses a distinct preparation fence issued at
the original first-start boundary. It cannot borrow a future resume claim.

Trusted Host assembly connects to the existing original Submission, pre-start
Run persistence, checked Source/Compute, publication and Result Owners. Prepare
and durably bind the original Run before protected physical work. The public
CLI then exposes bounded read, original lookup and cancellation through those
Owners. An exited CLI is not evidence of cancellation or cleanup completion.

Configuration adoption does not establish checked-publication applicability.
Effect-free Local publication uses its own distinct frozen catalog and the
original checked-preparation audit proving zero semantic completions. A Resident
catalog is not a substitute. A real completion, including sole-view completion,
cannot be represented as an empty journal; it requires the original applicable
completion evidence or refusal. Publication and Receipt remain with their
existing Owners.

Restore the original Submission and Run, not a newly compiled execution.
Preserve saved Source/Compute/Model responses, request identities, approved
materials and unknown Effect responsibility. Metadata lookup does not reopen a
payload, consume another read grant or send a Provider request. A new read is an
explicit new operation; receipt-confirmed completion remains distinct from a
delivered prefix or normal transport terminator.

## Direct Local preparation credential identity

The read-only preparation alternative retains the full original closed fence
identity, including the Client request intent/scope, checked observation
occurrence, actual Run invocation and Unit definition. Admission of its body or
CID is an identity check only. Trusted Native assembly separately retains the
opaque first-start witness from the original Work/journal and checks current
permission and cancellation before protected I/O. Public identity constructors
and decoders cannot issue or reconstruct that operational witness.

`actql-local-preparation-credential-grant/0.1` uses the same finite Local grant
field map, replacing `fence_claimant`, `fence_generation` and `fence_intent_cid`
with `preparation_fence_cid`. The reader requires the full admitted original
fence, matches its CID and original scope projections, and admits exact canonical
bytes only. The initial operation is `salesforce:record:observe`, method `GET`,
with the existing empty-body SHA-256 digest. A preparation grant cannot authorize
PATCH, mutation resume, approval or a renewed execution claim.

`NativeClientEffectSourceWork.prepare_observation_fence` binds the same retained
first-start witness to the live original capture context. The existing checked
Effect identity issuer resolves the authored member against its actual consumer
Artifact and pinned inputs. The fence uses that occurrence CID, the captured Run
Invocation, the consumer Unit definition and original Client request projections.
It never receives these five identities as caller-selected strings. The context,
inputs, checked preparation, actual captured Run and Artifact must still be the
same live Owners when the fence is read. Current Work/cancellation/Checkpoint
checks bracket capture callbacks and identity encoding. Closing the capture or
losing current permission invalidates protected use; identity bytes cannot
reconstruct or renew the token after process exit.

Preparation uses the existing `actql-local-credential-use/0.1` record and finite
ordinal rules. The distinct original grant CID identifies the typed alternative;
restore never claims another ordinal or refreshes expiry. Old Local resume and
Remote grant/use bodies and CIDs remain unchanged. Preparation identity, original
grant acknowledgement, durable use claim and actual Provider entry are distinct
facts. Absence or a reconstructed identity never proves an observation unsent.

The existing private grant-original journal stores Preparation and Resume as
closed typed alternatives. A Preparation packet contains the full canonical
`preparation_fence` original alongside the original `grant` and `intent`; a
Resume packet retains its original two-field bytes. Packet admission selects
the exact closed shape and never falls back from an invalid Preparation body
to Resume. The full fence must match both the grant CID and original Client
intent/scope. Decoding this storage record does not recreate an operational
Work token.

Both alternatives share the existing immutable append transaction, issuance
witness, 64-original/65,536-byte per-Run limit and exact capacity reservation.
Preparation append additionally requires the same live original Work/journal
fence under the existing transaction. Current issuer, adoption, account,
cancellation and started/Checkpoint facts are checked after encoding and
before append, including exact replay. Repeating the original operation keeps
its grant, expiry, allowance and reservation unchanged. A different operation
ID cannot mint another allowance for the same original preparation observation.
Missing or altered originals and reservations refuse instead of being repaired.
The checked Direct Local Catalog/request and credential installation remain
separate prerequisites before exposing this storage seam through the CLI.

The Native credential adapter admits Preparation through a separate typed
installation callback. Remote and Resume callbacks do not authorize this
alternative, and a Preparation installation does not authorize either of
them. The initial installed operation set is limited to
`salesforce:record:observe`, GET and an empty request body. Exact target path,
origin, complete original scope and body digest are checked before the same
existing ordinal claim. Preparation uses the original shared trusted clock,
durable use record, revocation, outcome persistence and query implementation.
Its public send entrypoint requires a current guard; trusted Host assembly
must supply the opaque Work fence and independent read/issuer decisions.
Missing original use custody remains a typed query refusal, never an assertion
that the observation was unentered or permission to resend.

## Direct Local checked Catalog and target request

The existing Salesforce Catalog/projection/declaration/request Owner has
closed Site and Direct Local binding alternatives. The Site observation and
capability bodies retain their exact original fields and ordering. Direct
Local observation uses `actql-salesforce-local-catalog-observation/0.1` and
binds account configuration/identity, authority scope, adopted Host, original
Client request intent/scope and Run invocation, plus the actual connection,
org, principal, namespace, connector, origin and sync occurrence. It contains
no Site, Site generation or Dispatch substitute. Catalog identity does not
grant metadata disclosure, observation entry or mutation authority.

Both alternatives use the same resource metadata, field requirements,
nullability/type checks, declaration and executable Mapping construction.
The immutable static declaration can be reused only under the same admitted
installation; each executable request is separately bound to its original
Run and request. Local capability uses
`actql-salesforce-local-write-capability/0.1` with the actual installation and
runtime binding. Its profile omits individual row values and original Run
identity, while exact execution admission checks those original facts. Equal
capability content never makes a foreign Run's request interchangeable.

The first Local target-read request is derived from the existing admitted
update-by-record-ID candidate and current Catalog. Its GET, empty body and
exact candidate path use the existing REST-byte identity domain
`actql-salesforce-rest-request/0.1`. The later PATCH body remains a separate
request identity. Current Local Catalog/credential org and original Host,
account, request and Run must match before using the GET. An altered target,
foreign org, mutation scope or mismatched preparation fence is refused.

`observe_native_local_salesforce_effect_target` connects this checked GET to
the same Native credential transport and target/Preview projection Owners.
The actual physical response and semantic projection are separate typed
facts; projection failure retains the received original rather than hiding
it. Host assembly must reserve and save exact response/use/request originals
in existing capture custody before durable preparation acknowledgement.
Receipt/capture failure does not make an entered use unsent or authorize a
new grant or another GET. Historical named Catalog restoration reprojects
exact retained response bytes/use evidence through the existing recovery
function and rejects missing, changed or foreign originals without I/O.

The original preparation fence visits actual captured target proposals through
`visit_native_effect_target_requests`, the same Mapping/request visitor used
by Remote observation. The checked authored member and pinned consumer index
come from that fence and its capture context, rather than CLI-supplied row
positions, selectors or changes. Each receiver sees a
`NativeClientLocalPreparationTarget` bound to this live Work, current Catalog
and original checked GET. Original request intent/scope and Run invocation must
match. Current Work, cancellation and capture checks bracket projection and
receiver callbacks; an incomplete export is not a complete observation batch.

The target's credential scope projects its actual GET, original occurrence,
consumer Unit and fence. This is identity material only. It issues no grant,
claims no use and confers no independent read, issuer or mutation permission.
Host adoption/current Account and credential installation still require their
own checked binding before grant acknowledgement or physical entry. Closing
the capture invalidates operational use of retained targets; retaining their
public identities does not recreate a token or permit Source/Compute replay.

### Current Host preparation binding and explicit grant acknowledgement

The finite Provider original is another file in the initially selected bounded
configuration set. It uses the existing configuration version, with no secret,
grant, Site, Dispatch or future mutation claim:

```json
{"version":"actql-config/0.1","native":{"salesforce":{"connection_revision":"connection-original","connector_registration":"salesforce","connector_revision":"salesforce/0.1","environment":"local","namespace_id":"namespace-original","org_id":"00D000000000001EAA","resource_origin":"https://example.invalid"}}}
```

The closed file admits only an installed Salesforce implementation revision and
a finite HTTPS origin. The existing Catalog and credential Owners still admit
the actual org, target request and complete credential scope. This file selects
installation identity; it supplies neither metadata nor secret installation.
Its exact source generation/content and stored adoption custody are checked on
each use. Missing originals or identical file replacements are refused.

`bind_salesforce_preparation` binds the real Host and selected original to the
same opaque live preparation fence. Current authorization requires the
original principal/connection/authority scope, `run × submit`, and
`<checked Effect resource> × read` through the existing Account Owner. The
checked resource, authored stage/member and original admitted lookup budget
come from the Work; caller resource strings cannot replace them. These read
decisions do not grant issuer issue, mutation apply or Reviewer approval.

`catalog_binding` derives the typed Direct Local Catalog identity from this
actual adoption, account, installation and original Work. Target acceptance
requires the same opaque fence and complete derived Catalog binding, not just
matching public CIDs. Current checks bracket Account, capture and target
callbacks. No fresh physical start is inferred from any of these projections.

`prepare_grant_operation` constructs one bounded explicit operation with the
selected issuer's original finite expiry/use allowance and the target's exact
GET scope. It appends nothing and acquires no issuance permission.
`adopt_grant_operation` separately obtains the existing current issuer decision
bound to that exact operation CID. The same journal transaction checks the
live original Work, current target read, selected installation/issuer, current
started/cancelled/Checkpoint facts and exact scope before immutable append.
It retains the original operation, grant bytes and capacity reservation.

An opaque acknowledgement is returned only after commit, original custody
readback and final current checks. Unknown commit, corrupt/missing originals
or lost reservations return the existing typed refusal and never another
grant. Retrieving acknowledged grant material rechecks that same custody and
authority; it is not a Provider response or send receipt. Physical entry still
requires the independently installed secret binding, original credential-use
claim and transport entry checks. Restoring public operation identity never
recreates a Work token or grants permission to resend an unknown observation.

The operation's bounded `reference_record` is the existing exact original
grant/intent/fence packet, retained before adoption together with its original
operation CID. `admit_native_local_preparation_grant_reference` recomputes that
identity and requires the supplied original CID. Decoding gives an identity
reference, never an operational fence or acknowledgement. There is no new
wire envelope or alternate identity domain.

`lookup_preparation_grant_operation` requires the original Host/account/scope,
current `run × read` and the independently current operation-bound issuer
decision. It queries only the existing original grant journal. Current checks
bracket issuer acquisition and readback. The result distinguishes retained
original custody from an unresolved original and exposes no new grant ACK,
use claim or entry permit. It neither mutates Run revision nor renews expiry,
allowance or reservation. Missing issued custody remains a typed refusal;
an unresolved row is not proof that issuance or physical entry never occurred.

### Original preparation credential installation

The existing private-root filesystem Owner issues `PrivateFileProjection` at
explicit credential installation. It retains the original root and file facts,
including physical identity, ownership, mode, size and nanosecond modification
and change times. These facts are opaque; caller generation strings or a new
inspection at send cannot replace them. The projection is not an authorization
token or durable recovery acknowledgement.

The Preparation-only credential installation retains this projection alongside
the exact read operation. Its physical HTTP hook opens relative to the retained
root with `O_NOFOLLOW`, compares the actual descriptor and current named file
against the original installation, and checks again after reading and just
before transport entry. File replacement, rename, symlink, extra aliases,
privacy revocation and lost root namespace custody are refused. The secret is
bounded inside C and never projected into MoonBit or diagnostics. Normal Remote
and Resume bearer-file rotation and credential wire identities are unchanged.

Current issuer, grant revocation, Work/cancellation and use-claim checks remain
with the existing credential and Host Owners. A missing original projection
does not take the ordinary file-path fallback. Once a use is claimed, transport
failure retains the original unknown use; this hook neither issues another
grant nor resends it. Restoring a lost installation from current file contents
is not implemented by this projection. Host restoration must retain or verify
the original installation's existing custody before physical re-entry.

## Independent acceptance requirements

These expectations are fixed independently of implementation output. A contract
record or internal fixture is not public execution evidence.

| Counterexample or route | Required result |
| --- | --- |
| Untrusted project config or foreign selected account | Protected I/O count zero. |
| Missing adoption proof, lost custody or divergent file | Refusal; no initialization repair, grant regeneration or protected I/O. |
| Crash at intent persistence, exclusive creation or final adoption commit | Recover the exact matching original state or refuse ambiguity; no duplicate adoption. |
| Concurrent bootstrap or managed-root escape | No unauthorized dispatch or merged authority. |
| Source followed by multiple checked processing steps and Named Result | Independent expected rows/schema/order through the installed Native CLI; bounded read. |
| Process exit followed by original lookup/read/cancel | Original Submission/Run preserved; saved work not reexecuted; original operation loss remains distinguishable. |
| Local/Remote substitution, wrong Run/unit/attempt/Provider | Refuse before credential send. |
| Expired grant or stale/currently denied authority | Refuse before send; approval cannot override it. |
| Required Effect approval | Zero writes before approval; intended count after approval under the same Run. |
| Saved response or unknown Provider result after restart | Reuse confirmed originals; do not resend unknown work or report it as success. |
| Temporary cleanup failure | Same Owner/handle retained; retry, with no early capacity return or double release. |

Publish each implemented slice with fixed source SHA, actual artifact/digest,
commands and explicit executed/unverified coverage. Public npm publication,
Cloud deployment, secret rotation and production Provider writes are outside
this implementation authorization. Hosted CI remains stopped. Focused local
checks cover changed boundaries; heavy cross-target/proof/package campaigns
remain with the integration verification owner.

## Material delivery and final display

The Native read selection distinguishes the literal `stdout` and `material`
destinations. Parsing a material choice supplies only original configuration
DATA. It cannot issue a receiver, read permission or physical capacity. A
stdout binding and its original preimages never certify internal transfer.
Their existing bytes and CIDs remain unchanged.

Material acquisition requires the existing trusted installation's actual
same-Host Store, original read and workspace loan before protected read or
allocation. Bind that receiver to the original Run, Result, schema, ordering
and material generation under current data and egress policy. Intake bounds,
format choices, copied identities and a previous Allow are not substitutes.
Until this joined supplier exists, material remains explicitly unavailable;
there is no heap-backed or stdout-permission fallback.

A confirmed material transfer records only the original receiver's actual
acknowledgement. It does not certify table display. Final table stdout needs
its own original disclosure selection, current authorization and real
write/flush facts. A file destination separately needs the actual Writer.
Keep the session, input, decoder, checked values, escaped aliases and output
workspace through their respective acknowledgements. Failed or unknown read,
transfer, display or close retains the same original responsibility; it never
allocates another attempt or reconstructs a live loan from saved DATA.

## Finite original Run read roles

The explicit finite read alternative selects `run_policy_profile_cid`, `run_file`,
`retention_file` and `store_file` together. These literal names follow the existing
selected-file admission and identify actual adopted originals; they grant no
permission. Initial binding compares them with the opaque profile binding.
Read-evidence restoration uses each saved row's independent read-original CID
and that original's roles, then rechecks current Host authority, selected file
generations and the original accepted Run packet. Different read selections in
one Host retain separate roles. The absolute `expires_at` alternative contains
none of these fields and its historical bytes and grants remain unchanged.


## Explicit legacy lifetime upgrade

A legacy adoption keeps its absolute read and retention originals. The explicit
policy-upgrade operation stores a closed authenticated append in the existing
installation-original journal and increments its existing custody counter in the
same transaction. The installation pool remains eight records and 65,536 bytes;
the append reserves one 8,192-byte record before copying new material. A replay
uses the same immutable operation and selected original bytes. Lookup does not
issue a Policy, open a Result or create a Run. Missing originals or reservations
are refusals; they are not an opportunity to initialize or backfill state.

The append binds adoption, authority scope, operation ID, actual read/run/
retention/store configuration roles and content identities, the finite profile,
and the new read selection. Its accepted legacy set contains exact original
request/Run/Submission/admission-revision correspondence. An accepted Run without
a finite packet is eligible for the original absolute read only if that immutable
set and the original Submission Owner agree. A later missing packet cannot be
interpreted as a legacy Run. Fresh Submissions use the separately bound finite
profile; old Run, Result and grant deadlines and bytes stay unchanged.

Each read-history row resolves its own read-original CID. A selected-file read
uses its original configuration roles; an upgraded read uses the exact closed
append, authenticated through the original private epoch key, and its saved roles.
Neither name lookup nor possession of a profile/CID supplies current authority.
The existing current Account, Result Policy, grant issuer and delivery Owners
remain responsible for their separate checks. The journal's private active-
transaction fact permits only read-only custody verification to join its own
transaction; nested mutating operations remain rejected.

This metadata connection is not installed-product upgrade acceptance. Compatibility
between the originally adopted runtime and a newly installed package must be
admitted and retained separately before the packaged CLI can cross that boundary.

## One explicit runtime successor

The adopted finite successor is a separate `runtime-successor/0.1` revision-zero
append in the same installation-originals journal. It never rewrites the old
`policy-upgrade/0.1` packet, correspondence, signature, dates or read selections.
Its `actql-local-runtime-successor/0.1` closed body binds the current Account
configuration, original adoption/scope, exact operation, old upgrade CID/packet
digest, prior pair digest and original a3b runtime wire, independent current
complete-package identity and new finite pair. There is at most one successor;
this does not introduce a general migration registry or compatibility alias.

The Common metadata codec uses the existing 8,192-byte/64-node/depth-four record
codec with a 5,632-byte payload ceiling. Metadata content identity is not an
authenticated original or a physical/current witness. Nested package/runtime
wires must be independently revalidated by their existing Owners. JSON Schema
string length does not replace the Owner's UTF16 operation bound, UTF8 limits,
current Account authorization or workspace admission.

Native must verify the complete current product's opened members/generations,
the authenticated old correspondence and exact finite scalar compatibility
independently. It reserves the same 8,192 bytes/one object before copying and
commits the append and issued-counter CAS together. Count remains at most eight
and at most `settings.files.length + 1`; reservation ceilings do not increase.
Missing/changed packets, dependencies, reservations or unknown physical profiles
refuse. A saved successor cannot be repaired from current files or copied CIDs.

A narrow Common metadata reader may reconstruct only the historical old109/a3b
pair represented by the retained build-time complete-body proof. Its generator
revalidates the fixed proof and exact original/historical manifest, source,
platform, library/ABI/license/dependency closure and all six asset role/size/hash
bindings. The saved pair body must remain byte-identical. Callers cannot select
a proof CID, Boolean or latest default assets. The ordinary generic inspect and
restore paths retain their actual-body requirements. This logical metadata does
not issue physical custody, a formal corrective release choice, current
compatibility/authority, or missing Run/Prepared/data materials. Native still
performs the independent authentic packet/adoption/scope, current whole-package,
transaction/HMAC and current authorization checks. Missing originals remain
Unavailable; recompilation and recapture do not fill them.

Under that retained context, old operation lookup validates and returns the
unchanged original bytes/CID against its original a3b pair, separately from the
successor's current package. Response loss retains the same operation/Unknown
and cleanup responsibility; lookup alone can confirm its original commit.
Compatibility never renews an old grant/expiry or authorizes a resend, new Run,
Source/Model/Effect, signing use or automatic append. Initial/final current
authorization and every retained read-row's original policy checks remain.

## Physical directory census

The existing filesystem Root can compare a finite set of immediate names and
regular-file/directory kinds against the same opened directory. Expectations
follow the formal inventory's ASCII ordering, not the Core String shortlex
comparison. Each name uses the existing closed object-name grammar. The
65,536-byte frame and 8,192-node-derived entry bounds are intake ceilings only,
not workspace funding or an execution resource profile.

The census reads one entry at a time, rejects unknown names, extra empty
directories, missing/duplicate members and symbolic/non-regular file kinds, and
retains only bounded completion state for expected members. It does not publish
an arbitrary filename list. Enumeration uses a separate descriptor relative to
the original Root and preserves the Root's own directory offset.

An unconfirmed enumeration close remains the same Root's cleanup responsibility.
A consumed descriptor/stream is not closed again through a possibly reused
number or pointer. Closing the ordinary Root descriptor does not confirm that
enumeration's retirement; a sticky cleanup refusal remains visible. Finalization
does not provide a retirement ACK.

This comparison is a physical observation of opened-directory membership,
not an atomic snapshot, named-namespace restoration, file mode/content/hash
verification, admitted complete package or authority. Those original/current
facts remain separate requirements of the existing product and Account Owners.
The private-state 0700/ACL contract is unchanged.

## Private complete-product member descriptors

The private package-member descriptor projects the formal release inventory's
exact `path`, `bytes`, `mode` and `sha256` entries together with `sourceSha`,
`platform` and `packageName`. Its reader requires the selected source/platform/
package and exact canonical bytes. This metadata format is not a contract CID
domain, physical witness, release-cohort admission or compatibility Allow.
Independent source-bound release/runtime correspondence remains necessary.

`local-product-members.json` is the single root-level self-hash exclusion from
its own inventory. It is still a required physical member: its exact bytes,
opened generation and separately bound digest must be verified. No other path,
suffix, metadata file or directory is exempt. The platform descriptor digest
can be bound in launcher metadata before constructing the launcher inventory;
the complete product identity binds both descriptor digests independently.
Historical packets and descriptors are not rewritten to implement this order.

The descriptor's pure census projection contains only expected immediate names
and file/directory kinds. Physical enumeration must compare the complete bounded
set through the same OriginalRoot and reject unknown entries, symlinks, extra
empty directories and changed mode/hash/generation. Unknown directory contents
must not be accumulated without a bound. The descriptor's 65,536-byte/8,192-node
intake ceilings do not establish workspace funding or permit retaining extra
physical resources. Root/Reader cleanup remains owned until its actual ACK.

The existing launcher resolver selects exactly one optional platform package.
Hoisted and nested placement are distinguished as separate root relationships;
nested `node_modules/@actql/cli-<platform>` is not launcher-owned payload. Its
selected platform must be verified through its own OriginalRoot. This does not
exempt `node_modules` generally or admit unknown metadata, packages or symlinks.
Path classification alone establishes neither physical containment nor support
for every npm layout. Formal staging, Native physical census and installed
consumer acceptance are separate from this pure descriptor connection.

The Common runtime metadata Owner reads the same closed formal inventory as the
Node producer: exact source/platform/package labels, ordered unique ASCII paths,
integer byte counts/modes and digests, with only the descriptor's own exact root
path excluded. It rejects alternate bytes and exposes bounded indexed members,
not a mutable inventory array. These literal comparisons and intake checks do
not issue a physical witness, compatibility, workspace funding or authority.

## Original package-file observations

The filesystem Owner can capture an opaque transient observation of one regular
file relative to its existing opened Root. Only actual stat can construct it;
public generation fields, hashes and copied metadata cannot. The observation
keeps the same Root/name, original device/inode/size, mode, UID/GID/link count and
mtime/ctime. It detects mode changes and same-size modifications that the
legacy three-field generation does not describe.

Reads still use the existing Reader constructor and failure-custody carrier.
The observation compares the actual opened Reader and current named file to the
same original facts before returning it and after bounded consumption. A failed
comparison closes the original Reader once; missing close ACK keeps that Reader
in its existing failure carrier. No replacement stat or reader repairs it.
The package observation is distinct from private credential installation
projection; the latter's 0700/ACL checks, original wire and restore are unchanged.

This is physical metadata, not named Root restoration, content digest, current
Account authorization, compatibility or a complete package witness. The existing
product caller must separately perform those checks and account for retained
observation memory before capture. Syntax/descriptor fit does not supply funding.
The intended product integration replaces generation-only witness storage rather
than simultaneously retaining both representations; its holding/ARC evidence
must be checked at that connection. No new numeric profile is admitted here.

## Original named-directory observations

The existing-only Adoption entrance shares the original constructor but retains
partial acquisitions when it refuses. Its opaque failure keeps the original
reason, each actual source/parent/child/managed Root, the actual Lock and any
rejected Root/Lock or pending Reader constructor. Equal paths or ownership DATA
never collapse distinct acquired descriptors or authorize closing a borrowed
Root. This entrance cannot initialize a missing Host or repair missing intent.

Cleanup uses those same objects without reopening, rereading or retrying the
refused adoption. Original read cleanup and Root acknowledgements precede Lock
release; an unconfirmed close keeps the same failure and exclusive Lock held.
The original reason remains readable after successful cleanup. Successful
acquisition still returns the existing Session: its journal/current admission,
escaped aliases and outer funded read lifetime retain their separate Owners and
acknowledgements. The failure carrier itself supplies no read budget, permission,
Host transport, issuer or execution authority.

The existing-only journal entrance similarly keeps a rejected original database
with the same Session's Roots and Lock. It invokes the existing journal body
once; a repeat returns the original failure even after cleanup, without opening
another database or reinitializing missing custody. Session aliases close through
that same carrier, so the legacy lock-only close cannot bypass its obligations.
The original primary issue remains separate from a failed cleanup result.
Database close must acknowledge before Root retirement, and the Lock is last.
Reader or directory Unknown retains the original acquisition rather than making
another attempt. These acknowledgements cover the acquired descriptors only;
escaped Readers, provider aliases and the surrounding original read/loan still
require their own actual retirement.

The existing Root can also capture a transient opaque observation of its actual
opened directory, including device/inode, mode and UID/GID. Only the path already
retained by that Root is used to compare the named directory. A bounded no-follow
descriptor walk rejects aliases, replacement or changed original metadata; it
does not replace the Root, accept another caller path or restore a missing
historical original from fresh stat.

Each temporary directory descriptor is closed once with an observed result.
If close is unconfirmed, the same Root retains the namespace-cleanup fact and
refuses subsequent physical observations. Closing its ordinary directory fd
does not confirm those temporary descriptors' retirement. The consumed/unknown
fd is never reopened or closed again through a potentially reused number.
These facts compose with that Root's existing census and Reader custody.

This additive package namespace check does not weaken or reuse the private
credential projection's 0700/ACL eligibility, wire or restore. It is not Account
permission, compatibility, a grant or admission of any package contents. Full
product verification still separately checks every exact file observation,
descriptor/digest and bounded member census before and after current authority.
Path-walk scratch and simultaneous directory observations remain subject to the
existing caller's workspace/lifetime accounting, not inferred from path bounds.

## Descriptor-derived directory inputs

The Common packaging metadata Owner projects one exact payload directory from
the closed product descriptor. The root includes exactly one regular descriptor
file, and every declared child directory must contain a declared file. A path
cannot denote both a file and a directory. Immediate names use ASCII order,
independently of full-path order or Core String ordering. Indexed read-only
entries hide the retained array; construction still requires caller workspace.

This is the expected set for the existing physical census, not an observation
or funding claim. Unknown parents and unlisted empty directories are refused.
Only the root descriptor path is self-hash-excluded; the same basename below
a directory is an ordinary declared member. Exact selected npm dependency
placement remains separate and does not exempt arbitrary node_modules content.

### Rust storage within the original holding

The private Rust allocation path uses bounded size-class pages within the same
physical provider and admitted holding. Its page lists, live-slot tokens,
alignment padding and control metadata consume that holding. Large or highly
aligned Rust requests remain original extents classified as Rust storage.
Neither path introduces another capacity root, reservation or system fallback.

A live Rust page is not a generic exportable span: protection, sealing, lending
and generic retirement reject it. Slot retirement consumes its original token
under the holding's existing lock. The unsafe Rust caller remains responsible
for releasing only after its last alias; an equal/copied header is not a new
allocation. A final-slot retirement failure removes the page from reuse and
keeps the original pending extent until confirmed physical cleanup. Reallocation
acquires its replacement before releasing the old slot, so overlap is funded by
the same finite holding and failure preserves the original allocation.

Process-static Rust storage retains the original process/runtime lifetime.
Engine or thread close does not acknowledge that storage, original region
retirement or an external operation. A derived allocator/runtime identity and
successful compilation do not establish normal funding or final image, workspace
and Result acceptance.


#### Physical occupancy observation

The same provider may expose a read-only census of the current original
holding. Occupied and peak bytes count physical allocator pages, including its
control records and pending retirement. Allocation raises the counters only
for pages actually entered by that original provider. Only confirmed physical
retirement lowers occupied pages; peak never lowers or issues reusable credit.
These quantities are neither OS RSS nor the size of an outer reservation.

Generic extents, Rust slab pages, large Rust extents and pending-retirement
pages partition the occupied payload. Slab metadata, occupied slot capacity and
empty slot capacity are contained within those slab pages, not additional
charges or grants. Pending payload is not read after uncertain protection.
Fixed census counters themselves live in the same charged control records.
The original provider lock makes a census coherent with allocation/retirement;
foreign, unbound and inherited-process scopes cannot inspect it as current.

A phase census and its peak establish only this physical domain's observation.
They do not fund separate stacks, loader/VM domains, unrelated allocations,
external operations or a normal numerical profile. Observations cannot clear
RuntimeRetained, acknowledge a stop, export a heap alias or replace original
cleanup responsibility. Matching compiler diagnostics remain outside the
successful image response protocol.


#### Private physical Core preparation

The maintainer `physical_core_conformance_only` scope selects the existing
physical verifier. Its preparation separates verified module, compiled image,
Engine recipe and private library DATA from actual parent/domain admission.
The same closed image validator serves this preparation and the final component
producer. Preparation never constructs final `LocalComponents` or supplies an
`OriginalWorkerFunding` substitute. Compile-only evidence remains insufficient
for the final physical verifier. Preparation retains its original inputs on the
existing installed process record before current/projection calls. Only that
same registered process/domain/channel/frame can satisfy subsequent current
checks; response loss retains the original pending carrier. This connection
performs no spawn, stop or cleanup and does not turn current into a funding ACK.

Contract, Result, physical and workspace observations each carry the same closed
selected-precompiled-image cohort: original module/image, Engine configuration
and both native library digests. Each family must have nonzero cases; the final
producer also matches the cohort to the actual original image bytes. Raw-module
JIT reports or compiler-only facts cannot supply this correspondence, even when
the module bytes match. These receipt fields record execution correspondence;
they do not issue funding, permission or physical retirement acknowledgements.

The physical caller must consume the independently admitted original Native
parent/domain, child Ledger, control channel and holding before Config or any
image capture. A scope label, matching bytes, the compiler's holding or a local
resource-guard reservation cannot establish independent pre-root funding. The
actual supplier must retain Python, loader, process, descriptor and control
responsibility separately from runtime/Result/workspace overlap. Missing
funding refuses; it does not select a scalar Root or raw-module JIT path.

#### Original Rust buffer inspection

A trusted native caller may inspect physical containment of an original Rust
buffer while it retains that buffer's owning handle. The same provider checks
current holding/process, one live Rust slot or large allocation, and a range
contained within it. Slab control metadata, retired/pending storage, foreign
holdings and ranges crossing allocation boundaries refuse. This is a physical
range observation, not proof of Rust type, logical length, authorization or a
stale pointer after reuse; original allocation tokens still govern retirement.
Rust allocation headers remain with their existing Rust owner and are not
reinterpreted by C.

For the maintainer compiler, the official Wasmtime C API owns its original
serialized byte vector until the existing cleanup deletes that same vector.
Only that same lifetime supplies the buffer/length to physical inspection and
bounded image writing. No generic span, heap-page protection/lending, loader
fallback or copied-buffer owner is created. The original vector remains live
through write failure and is deleted in its original scope before holding
retirement. Generic Rust-page export refusals remain unchanged.

## Original journal capture transport

A trusted installed caller may transfer operational use of an already acquired
Native adoption Session to a capture, retaining the same SQLite and crypto
Libraries. Preparation performs no I/O. The caller publishes the opaque capture
in its original output slot before opening the journal. Opening is attempted
once; the capture records unconfirmed entry first, then retains the original
Host or failed-open carrier before allocating a reply. A missing outcome cannot
be replaced by another attempt. The caller must fence its other Session aliases;
the transport does not discover or adopt a Session from metadata or a path.

Current observation calls the retained Host's existing complete binding check.
Cleanup uses that same Host or failed-open carrier; the immutable opening cause
remains distinct from subsequent current or cleanup errors. Abandonment before
open closes the original Session and its owned directory descriptors. Only an
actual close acknowledgement permits retirement of the capture and reply DATA.
Escaped Readers, Session/Host aliases, provider references, Domains and workspace
loans require their separate acknowledgements and lifetime accounting.

The private C transport borrows managed inputs and returns owned managed output
references through initially empty, distinct slots. The same registered provider
supplies all callbacks. A foreign capture cannot retire a reply, a filled slot
cannot be overwritten, and a current/open reply cannot stand in for close.
Returned Session/Host/failure DATA references have a separate drop operation
which checks the same capture before releasing references; it cannot close the
underlying resources. Opaque references remain pointers to the original managed
objects, with no integer-handle registry, JSON restoration or direct compiler-
layout access.

This transport does not supply initial Root acquisition, an OriginalWorkspaceRead
or a selected SQLite Library Domain. Those scopes remain distinct. It neither
provides a joint scope nor makes an unbound Library or heap fallback admissible.
A complete normal installed caller must still supply those original resources,
current authority and outer lifetime obligations; absence remains unavailable.


## Existing adoption capture

The trusted physical caller retains a first-stage capture before entering any
Root acquisition. Preparation snapshots bounded selection DATA and allocates the
same partial-acquisition carrier used by Adoption. Existing-only open enters
once, publishing an unconfirmed outcome first, then retaining either the actual
Session or original failure before returning. An interrupted return cannot
become another acquisition or a cleanup acknowledgement. Scoped and legacy
constructors are separate entrances; a missing original read scope never falls
back to legacy allocation or initializes a missing Host.

The capture may retain one journal capture for that same Session. It publishes
the inner holder before handing it out, refuses replacement Libraries/options,
and delegates subsequent current observation to its complete binding fence.
Parent close requires the inner database and descriptor acknowledgements first.
Without an inner journal it closes only its original Session or partial failure.
The opening refusal remains available after cleanup; a later cleanup error does
not replace it. Descriptor retirement does not acknowledge escaped Readers,
Session/provider aliases or the caller's original Domain/read/workspace loan.
This holder supplies no physical scope, permission, transport binding or funded
normal installation profile.

### Same-pair adoption transport

The private adoption binding retains the actual Host, its nominal Read/SQLite
pair, the same original Read and a borrowed Native Crypto Library before any
Session open. Its preparation snapshots selection through the existing
existing-only capture; it neither loads Crypto nor initializes absent state.
The C callback declarations come from matching regular Native emission. Input
strings and ordered configuration names use bounded UTF-16 transport, with
distinct persistent output slots and owned managed aliases on return.

The binding enters the original Read for adoption stages. After the same capture
retains its Journal, that child owns the Read/SQLite phase sequence: no outer
Read scope may wrap its open, current or close. The Journal-open operation uses
only this retained child, never another preparation. Parent current observes
the child's whole binding; parent close waits for its database and descriptor
cleanup. A failed leave retains the same original phase for cleanup, and an
unconfirmed call cannot start another open or acknowledge retirement.

The Python transport registers its carrier on the original Read before invoking
the private trusted assembly's preparation port. That port must supply the
actual binding and retain its Crypto/provider custody; it is not an application
callback, numerical supplier or authority derived from path metadata. Known
local busy, thread and process refusals precede registration and foreign entry.
Lost calls, partial output slots or mismatched originals retain the same cleanup
carrier and fence the pair, Read and Library parents. Retained child aliases are
correlated without turning their addresses into handles or permissions.

Only the same Native close reply and descriptor acknowledgement allow the C
managed aliases and Python reverse registration to retire. This does not close
the borrowed Crypto Library, settle the parent domains, return a WorkspaceLoan,
or acknowledge the Host/backing/descriptor. Those original owners retain their
separate physical cleanup obligations. Missing operational Crypto, initial
funding or ordinary installed assembly remains unavailable; this transport
cannot fill those gaps or relax existing permission/current fences.

## Consuming an original Native read

The installed Arena Owner can claim an already prepared domain read once as an
`InstalledArenaOriginalReadConsumer`. It validates the original Host, registered
read, retained/execution envelope and original claim before allocating the
consuming view. The view retains that same read and WorkspaceLoan; an equal
descriptor, copied view or foreign Host cannot substitute for their nominal
identity. This does not issue permission or select a normal numerical profile.

Claiming transitions the existing Resource claim into its consuming phase. The
old available-pair port consequently becomes unavailable and is not reinterpreted
as another usable read. Consumer currentness uses the existing Resource
consumer snapshot/token/phase checks and the same physical domain. The first
physical entry consumes the existing start transition once; a failed entry does not reset
it or make another claim eligible. Leaving acknowledges only the original
physical scope, including during cleanup, rather than final material retirement.

The read retains its consumer through the existing close sequence: stop, actual
C context and escaped-alias retirement, WorkspaceLoan close, original claim
settlement, pair retirement and final context acknowledgement. Pending cleanup
keeps that same carrier and loan. This is the existing read's cleanup authority,
not a second controller or a raw Ledger export.

A downstream material receiver must separately bind the actual Host/Store,
original Result/schema/ordering/generation, current read policy and its complete
simultaneous envelope before protected read or allocation. Package Root/Reader
capacity, intake bounds and successful metadata comparison cannot supply this
capacity. Retiring one managed alias does not establish that all row, schema,
renderer or final Writer aliases have retired. Material transfer and final stdout
write/flush require their own original receipts; without the actual supplier and
complete profile the material path remains unavailable.

A consuming execution may use serial physical Read scopes separated by SQLite
work. Its logical Resource entry remains one-shot. Only a successful leave of
that same registered consumer permits physical resumption, with current Host,
domain, claim and WorkspaceLoan checked again. Failed or unconfirmed physical
entry/leave permanently keeps that view cleanup-only; a later available context
cannot revive it. The same pair retains the consuming view and never restores
its spent available-read port. Scope leave does not retire managed aliases or
acknowledge material, domain, Library or Host cleanup.

Small managed Moon allocations may share pages inside that same original Read
domain. The existing provider owns these pages; headers, alignment, splitting,
fragmentation and serial metadata consume their original physical capacity.
This path neither calls the Rust storage ABI nor supplies another reservation,
pool or allocator fallback. File buffers and large managed allocations retain
their original generic-extent route.

A live-span observation of managed storage covers only one requested live slot,
including an interior range within that slot. It cannot cover page metadata,
an adjacent slot or an unused tail. Shared pages cannot be generically lent,
protected, sealed or retired. Free classifies the original context and exact
allocation after scope leave; a different current context does not acquire its
custody. A page remains owned until its last managed allocation retires and the
original physical page retirement succeeds. Failed retirement remains on the
same context for its existing close path, independently of user, scope, domain,
loan and Host acknowledgements. Serial exhaustion refuses allocation rather
than wrapping or selecting another allocator.

A retained Native filesystem Root can be checked against the caller's actual
current original Read context without exporting that context or an address.
The check rejects legacy Roots, retired descriptors and a different active
domain even when their paths or ownership observations match. The existing
Adoption Session applies the same physical check to each Root it owns; this
neither substitutes for its full current/adoption fence nor combines Read and
SQLite stages into one ambient scope.

The original-pair Journal capture retains its existing-only Adoption Session
and the same Host/Read/SQLite pair before physical open. It borrows the SQLite
Library from that pair and brackets each original journal stage with its
respective physical scope. Runtime current callbacks retain their own Read
brackets; the Journal does not nest another Read around those callbacks.
A returned DB is retained before leaving its SQLite stage. On refusal, the same
partial-acquisition carrier preserves it, the original Roots and exclusive
lock. A stage failure and a failed leave remain independently represented;
cleanup may finish that original leave but cannot replay the protected stage.
Directory/DB close, managed-reference retirement, domain/loan and Host ACKs
remain distinct obligations of the existing Owners.

A refused Journal open may retain the existing read-only inspection's copied
database and scratch-file cleanup inside its original issue. Journal cleanup
must obtain that original inspection Owner's close acknowledgement before
releasing the adoption Roots or exclusive lock. Cleanup failure preserves both
the immutable semantic refusal and the current cleanup cause; it does not
repeat inspection, reopen the source database or authorize initialization.

The original-pair inspection separates physical queries from row interpretation.
The existing bounded snapshot is retained before leaving its Read preparation;
its copied DB opens in the same pair's SQLite scope. Each custody query leaves
the original Read scope, uses that same DB in SQLite, then resumes the original
Read before protocol-body UTF-8, canonical, Run, Policy or HMAC validation. The complete epoch,
Run, Effect, cancellation, submitted-intent and named-startup predicates and
transaction order are shared with the ordinary Journal entrance. A failed
exchange stops subsequent queries and retains its original scope failure;
transaction uncertainty remains independently fenced.
Physical transaction-fence observations and sticky fence writes also belong to
that same SQLite scope. Reading the scalar while the Library's original SQL
context is not current is conservatively fenced, rather than evidence that the
Database has a usable transaction. The private audit routes these operations
through the same Database and resumes Read before interpreting their result;
it never caches a false fence, resets a fence, or substitutes another handle.

The same inspection carrier retains any partial copy before a scope can fail.
Its DB close and scratch cleanup have separate physical acknowledgements;
scratch deletion cannot bypass a pending DB close. Refusal retains that carrier
with its primary issue until cleanup completes, before the original Roots and
lock can retire. Neither query routing nor scope resumption supplies another
logical claim, a current permit, or a numerical resource profile.


Fresh Local runtime construction binds the current producer Source, compiler,
platform/ABI, generated assets, selected library bytes and complete loader
closure. It does not require that an unrelated historical scalar implementation
remain byte-identical. Integrity of the frozen scalar descriptor/body proof is
checked separately from eligibility to use that proof operationally. Its old
fixtures, implementation hashes, pair identities and vectors remain unchanged.

The current fresh implementation admits no historical operational scalar pair.
Both the physical Native binding and the CLI's selected original-runtime check
refuse that path; a copied proof, source label, CID or caller Boolean cannot
select compatibility. A future historical implementation needs its own genuine
proof in the existing Owner. Same-runtime restoration still checks its exact
original assets and physical currentness. Missing, changed or unadmitted old
state never authorizes fresh initialization, replacement configuration, a new
Run or renewed authority.

### Original Crypto component custody

First installation acquires its selected finite Crypto envelope through the
existing physical Host and domain Owner before entering the original Read scope.
The installer declaration selects the envelope; it does not issue a Ledger,
business-Run capacity or signing authority. The control envelope covers its
bounded controller objects, not OpenSSL's independent heap or a Root/Writer loan.

The selected private component links its own hidden OpenSSL implementation and
installs all three allocation hooks before that implementation's first allocation.
It imports the same process provider, checks its actual current original context,
and obtains one extent from that holding. State, alignment, block headers,
fragmentation and old-plus-new realloc overlap remain inside that extent. Internal
free does not return the outer holding. No stock allocation fallback, second
extent, implicit growth or configuration of shared system/Python OpenSSL is allowed.
The recipe binds source, headers, static archive, license and actual deployment
requirements; a linker flag cannot lower the ABI of a precompiled archive.

The existing Signature Owner retains one original component receiver independently
of the outer and inner Library borrows. Its bind out-slot is set only by the
original component CAS winner, before any fallible context/extent initialization.
A refused duplicate owns only its own module reference and cannot invoke the first
receiver's component cleanup. A first, partially initialized binding retains its
original cleanup duty even when no usable Library exists.

The component and typed Library operations are affine to the constructor thread
and process. Foreign threads refuse before mutable state access even when they
entered the same original provider/Read context. Cached EVP, BIO, key, cipher and
hasher functions remain behind that typed entry. A separate close flight covers
OpenSSL callbacks, extent retirement and context release; the allocator lock is
not held across those callbacks. Cleanup may allocate only inside the same
original extent, including its simultaneous retirement overlap.

Each Library retires its own hashers and diagnostic buffers before acknowledging
its borrow. Closing a Library neither unloads the component nor acknowledges the
Host, domain, Root, Writer or parent loan. Only after all Library/operation users
retire can component cleanup acknowledge its extent/context and then its separate
module reference. Failed scope leave, partial initialization or unconfirmed close
keeps the same receiver and registration. GC, thread join and PID absence are not
physical acknowledgements. The parent Read/domain cannot retire while that
registration remains pending; reverse registration is cleared only after the
parent's own full retirement acknowledgement. Key bytes, PEM/DER results and
Writer aliases keep their own original resource and authority obligations.

A later Local Host Read/SQLite pair uses a separate, exact preparation entrance
for Crypto. The pair's original Read consumer must already own the active
HostRead phase and its physical original Read context must already be entered
on the current thread. The entrance checks both original domains and current
fences without entering a scope, claiming another read or switching contexts.
The complete consuming Read envelope includes the component heap, metadata,
diagnostics and all simultaneous aliases; the entrance supplies no profile,
capacity or authority. The general domain Crypto entrance continues to refuse
an original Read domain.

Component registration precedes the foreign load, including partial failure.
A pending component prevents retirement of its parent original Read before its
frame is stopped, so the original scope remains available for component cleanup.
Library, component, Read-context, domain, loan and Host acknowledgements remain
separate. Neither successful preparation nor leaving a serial HostRead phase
acknowledges component retirement or authorizes a SQLite phase to borrow it.

The Local Host pair prepares its component registration in the already covered
outer control lifetime, after the original Read claim and before the first Read
entry. The physical predicate refuses any entered Read or owned scope; this
preparation neither switches contexts nor creates a control allocation supplier.
The active Read entrance consumes only that same registered slot, once. This
keeps the original nominal/copy/foreign and closed-cleanup identity checks intact.

Allocating this registration inside Read while retaining it from the outer
domain would make parent Read retirement depend on freeing its own registration.
An early detachment cannot replace the original nominal identity with a copied
closed flag. The outer control placement therefore preserves the general
registration order: component, Library and own-scope cleanup must complete, then
Read, domain and parent acknowledgements retire separately. The original domain
keeps the spent registration until its final acknowledgement, preventing another
load. A closed physical component carrier or other managed value allocated inside
Read still keeps that actual context busy while any external alias survives;
releasing it only permits another same-original cleanup attempt, never new work.

The private Python Read/Crypto transport keeps the existing Host resource pair,
original Read and component in persistent typed out-slots. Component registration
uses the outer control lifetime before the first Read entry. Loading consumes that
same registration once inside its actual entered Read. A Library is admitted only
through that original component; a matching pointer-shaped value or copied
carrier cannot substitute for the original registration and current checks.

Each Library and partially initialized Library retains its own close duty. A
refused Library acquisition with no Library carrier releases only that reply's
managed references. It cannot close the component. Component retirement waits for
all Library acknowledgments, and transport reference release is separate from
Read leave, context, domain, parent loan, descriptor and Host retirement. Unknown
retains the same slots and prevents resending the foreign operation. Python entry
refusals occur before registration or a foreign call and do not manufacture a
foreign-operation Unknown.

When the original Read is already entered by the caller, the component-only
close path preserves that exact frame and its parent read use. It performs the
original component close and retains partial cleanup, but does not invoke the
legacy domain-owning cleanup's stop/enter/leave sequence. Consequently the
same-frame DATA retirement can check the original current Read after the child
ACK without reviving a stopped use or interpreting it as a parent ACK. Older
domain-owning callers retain their separate cleanup sequence.

When a retained adoption Journal finishes its cleanup stages, the same pair and
Read use are logically stopped. Remaining Libraries and their component retire
only in that original entered cleanup frame. A separate typed observation checks
the original Host, pair, claimed Read, component, backing and physical context;
it revalidates the existing unreturned cleanup use without restoring normal
current. Only Library/component close and their corresponding close-result DATA
release consume that observation. Load, Library acquisition, HMAC, verification
and ordinary dispatch retain their normal-current requirements. The Library's
own acknowledgment precedes component retirement, and neither acknowledges the
Read, domains, loan, Host or descriptor. Failed or unknown cleanup retains the
same receiver and all outstanding aliases.


### Serialized command-preparation Journal WAL

The finite Native command-preparation Journal is selected only through its
original adoption Session and retained Lock. Its writer selects EXCLUSIVE
locking before schema, version or WAL access, then verifies the acquired
heap-backed WAL index in the same selected SQLite component. The selection does
not apply to generic SQLite, concurrent Journal users, Node or Cloud.

Retained inspection precedes the writer. Its existing inspection Owner creates
and retains a unique empty SHM alongside the exact committed DB-plus-WAL copy.
The selected read-only constructor uses SQLite's `readonly_shm` recovery path
and verifies the private heap index and absence of shared-memory mappings.
It does not use immutable access, omit the copied WAL, write the copied database,
change generic inspection, or substitute a mode string for physical custody.
The original snapshot identity and cleanup remain with the inspection Owner.

The component reserves each original VFS descriptor carrier within its existing
heap before opening the descriptor. A failed or interrupted one-shot close
retains that descriptor's consumed attempt and diagnosis; it prevents component
retirement and the selected Journal's close acknowledgment. It is never retried
by numeric descriptor. A successful SQLite close alone cannot discharge this
physical responsibility. Database, Library, snapshot, domain and adoption Lock
acknowledgments remain separate and child-first. Heap exhaustion, lock refusal,
partial initialization and COMMIT uncertainty retain their original carriers;
there is no NORMAL-mode fallback, fresh acquisition, replay or capacity increase.


The command profile keeps its later Native storage inventory separate from the
initial argv/Command/parser envelope. Its one configured Crypto heap serves
both Signature Libraries; its one configured SQLite heap contains DB/schema,
statement/cache, bindings/results, original descriptor metadata and the private
WAL index. Recovery and old/new pointer-array overlap are included within that
same heap. Heap capacity is not added again for each phase or borrower.

The private quote distinguishes a derived demand bound from a selected finite
SQLite facility. The latter supplies the same actual backed heap before first
initialization; it does not promise that every bounded input fits. Known WAL,
recovery, realloc and scan-copy coexistence remains a necessary minimum, not
worst-case demand. Residual heap capacity cannot fill an unknown demand term.
MEMSYS5 control and fragmentation are not usable payload. Exhaustion refuses
under the original cleanup semantics without fallback, enlargement or a fresh
open. This selection supplies neither external holdings nor input/work bounds;
the complete external envelope and an actual ordinary command remain required.

A snapshot bound constrains WAL frames, not the index to one region. The first
region holds 4062 frames, later regions 4096; each region requests 32768 bytes.
MEMSYS5 rounds requests within the selected heap and consumes its own control
bytes. The original inspection connection and copy must acknowledge cleanup
before the writer may use the serial phase bound. Pending cleanup retains the
same profile, scope, original FD/errno and all aliases; it does not refill the
Read or permit a second acquisition.

The closed command's Read selection also distinguishes full managed/native
demand bounds from finite supplied capacity. A facility candidate installs its
one-shot occupied-page ceiling on the same original lease before context or
payload allocation. Generic buffers, managed slabs, control metadata and pending
allocations consume that same ceiling without fallback or phase reset. The
whole backing remains charged once by its outer owner. The same H binds the
existing one-shot consuming claim; bootstrap, workspace and read reservations
remain distinct. Crypto heap and inspection coexistence are necessary subsets,
not additional capacity or a guarantee that every input fits. An exhausted
attempt keeps its original failure and cleanup duties. Default allocations
outside the entered original Read remain outside this facility, and all initial
and external holding requirements remain mandatory. This selection covers only
static Native command preparation, never business Source/Compute/Model work.

The profile validates the actual parsed Journal limits against its captured
pre-acquisition inventory. Native managed graphs, same-domain native buffers,
SQLite external receivers, shared control and process/platform holdings have
separate source-bound terms. Loader, mapped-image, pthread/TLS and native stack
storage outside the domain cannot be paid by that domain's unused capacity.
Computing their byte requirement is distinct from acquiring their original
process/installer holding. Until that existing Owner provides the actual
platform entrance, positive bounds remain insufficient and command preparation
refuses before physical acquisition. No scalar, source label or successful
component test supplies that missing original.

The trusted early entry captures the original OS-created main-thread stack
before argument/control work, retaining its complete reported extent with the
original process and thread. Current use requires that same thread, process,
OS extent and an actual current stack address within it. Foreign threads,
fork-inherited records and changed extents cannot consume that original. This
process-lived holding has no child-close or refill operation. Its size is
supplied stack capacity, not a measured call-chain high-water mark, another
allocator's backing or a guarantee that every possible call chain fits. The
subordinate stack record does not admit the complete initial envelope: loader,
TLS, FILE and all other external controls retain their separate requirements.


The same early entry retains a source-bound managed allocation-volume sum for
its captured argc, original byte total and four original allocator-class terms.
The selected immutable Command grammar, its parser, help/error output and fixed
module graph contribute separate terms. Constructor tuples/captures, reference
Array carriers, builders and suggestion pairs are counted once. This volume is
not a reservation or proof of allocator pages, fragmentation, metadata, stack,
SIMDUTF internals, platform holdings or later command graphs. Recording it does
not admit initial coverage or create a platform original.

The selected command's trusted initial operational control covers the finite
loader, dependency-image and TLS/synchronization lifetime of its pinned SQLite
and Crypto components, together with the selected platform bookkeeping for
directory, ACL and path operations. These are separate terms from each other
and from actual Read-backed storage. Each helper requires its actual entry
original and complete finite envelope before its first covered call. This
includes the first `dlopen` and its initializers. The Runtime's
hashed member observation retains its original Root/stat association; its path,
digest and nominal Runtime association do not issue that initial original.
A selected load consumes one original attempt, records even a failed load, and
checks actual handle/symbol-image correspondence before initialization or use.
Missing entry coverage cannot select a legacy diagnostic load instead.

Normal component use keeps both the original domain-current fence and the
selected load/member fence. Cleanup retains the same entered original child
predicate after normal use is unavailable; it cannot reopen, sign or acquire a
replacement. Library/component shutdown and module-reference release remain
separate acknowledgements. Dropping a successfully released module's member
alias does not replenish the once-counted process/thread-lived initial terms,
acknowledge every image/TLS retirement, or release the parent Read or backing.

The same initial control also covers the selected pinned allocator's finite
bootstrap, arena-registration, heap-descriptor and process/thread metadata.
These external parent/backing terms are distinct from the exclusive managed
payload and from Read, SQLite and Crypto storage. Before allocator initialization,
the actual entry retains its original process/thread and complete source-bound
selection. Its one-shot physical binding acquires one actual mapping containing
disjoint parent-metadata and exclusive-payload regions plus retained alignment
space. It selects bounded allocator options before initialization: no automatic
reservation, general arena growth, OS allocation fallback or destructive exit
shortcut. It retains the previous values with the original and never restores
them merely because a child or default heap closes. It then captures the actual
parent default, registers the two non-overlapping regions and verifies that the
new heap descriptor occupies the metadata region before selecting that heap
for managed module initialization. Both registration records must fit the
pinned allocator's existing static registration storage before use.
An absent or incomplete selection cannot perform allocator setup.
The profile selects pinned finite allocator options and refuses ambient allocator
options before setup, including case variants and unsupported option names.
Its bounded startup environment observation allocates no storage and rewrites
no environment value. On refusal, the entry must stop before subsequent automatic allocator
or module initializers; returning into those initializers cannot establish a
pre-acquisition refusal.

Partial setup retains that same receiver and any acquired reservation or heap;
a duplicate or refused receiver inherits none of its cleanup responsibility.
Normal current checks require the original thread, unchanged entry selection,
actual reservation, unchanged selected options and default heap. Cleanup may
restore only its own previous default, never an unrelated replacement. This restoration has a separate
acknowledgment: escaped managed aliases, heap descriptors, arena registration and
their complete original mapping remain retained, without credit or another setup.
No heap destruction, child close or process exit supplies their retirement ACK.

The command Runtime retains its stronger filesystem selection through current
checks. Its selected Darwin/APFS census uses `getattrlistbulk` with one fixed
65536-byte buffer and the existing bounded expected-name bitmap, both allocated
through the original Read. It does not construct a libc DIR or request its
union-directory prefetch and sort. The same original directory is checked for
APFS and absence of union stacking before enumeration; other selections and an
unsupported bulk operation refuse without switching to the generic census.
Existing generic census callers keep their original behavior. Exact names,
no-follow file kinds and before/after directory identity remain mandatory.

The selected census retains its separate descriptor before enumeration and
consumes its close exactly once. Active enumeration prevents parent Root close.
An unconfirmed descriptor close stays with that same Root, even after the Root
descriptor itself closes; its numeric descriptor cannot be retried or inferred
released from a sibling acknowledgment. Read/context/backing retirement remains
separate from either descriptor close.

Within the selected command entry, private Root and bootstrap-parent ACL
observations use a fixed 4096-byte kernel attribute buffer on the same supported
APFS selection. No libc filesec/ACL object or growing retrieval buffer is
constructed. The complete external ACL representation is checked before the
existing empty-ACL or deny-only rule is applied; malformed, truncated and
unsupported observations refuse. Generic ACL callers retain their original
platform path. The caller's bounded stack storage belongs to initial control,
not unused Read capacity.

Journal inspection uses the same entry's bounded original scratch selection,
captured before physical acquisition. It never re-reads the current environment
to choose another directory. The copied committed DB/WAL and scratch namespace
retain their existing identity and cleanup responsibilities. Captured path text
is input correspondence; it cannot issue the initial platform holding or pay for
path-helper internals, ACL objects, Read buffers or other allocations.

The executable entry retains its bounded raw argument bytes, runtime context
and scratch selection before generated managed module initialization. The later
parser entrance checks the same argument bytes and its requested bounds;
changed arguments cannot replace that original observation. Context and scratch
selection use retained bytes rather than later environment pointers. This
static initial-control storage remains distinct from an admitted managed arena
and from the physical Host, Read and component originals.
The selected product caller consumes those same retained context bytes; an
invalid or missing selected original cannot fall back to a replacement
environment value. The explicitly unselected entrance retains its separate
compatibility behavior.

After the complete initial selection is current, the selected entry binds
stdout and stderr before allocator setup can emit diagnostics. Both fixed
buffers remain inside that same process-lived entry. The actual managed
original remains a separate operational conjunct. The entry observes the
supported libc's actual buffer address and length; an earlier successful status or equal FILE pointer
cannot hide changed backing. Setup is one-shot, including partial failure,
and preserves each original result and errno. These buffers do not supply libc
FILE/lock/TLS bookkeeping, output permission or a retirement acknowledgement.
The existing actual write and flush checks remain separate, and no covered
caller reconfigures the streams or replenishes this initial storage.

Before the first buffer setter, the selected entry checks both standard FILEs
against the selected Darwin libc's original array, descriptors and pristine
write-only state. Prior buffers, output or replacement FILEs refuse before
either setter, rather than asking libc to release or rebind earlier storage.
The entry retains their original auxiliary-record, cookie and operation
bindings and checks them during current use, independently of buffer identity.
The generic buffer-binding helper remains separate. These process-lived FILE
observations cannot supply libc lock/TLS coverage or admit the whole initial
envelope; those holdings remain mandatory before the selected setup.

Selected inspection resolves its source and scratch directories with bounded
descriptor-based kernel path observations. It keeps the original containment
comparison, refuses unsupported filesystems without a realpath fallback and
retains each temporary directory descriptor before observation. That
descriptor's consumed close is separate from the DB/WAL, copy and private-index
descriptors. An unconfirmed path close retains the same inspection receiver and
prevents another path acquisition or successful cleanup; its number is never
retried. Generic inspection keeps its existing canonical-path behavior.

## Selected Linux mapped backing

The selected local Linux arm64 process-domain consumer may compile the existing
physical backing provider with `ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN` and
`_GNU_SOURCE`. This is an explicit private backend selection, not a resource
issuer or a numerical profile. The actual trusted supervisor/process-domain
admission and the original mapped backing remain separate conjunctive inputs.
A kernel limit cannot construct an extent or replace the private regular FD.

The existing provider retains exact FD size, owner/mode, generation and recipe,
first-initialization checks, relative allocation and payload bounds, original
loan/view/domain identity, and child-first cleanup. Failed unmap or protection
keeps the same original carrier; returning a view does not return its parent
loan, and closing the provider does not close its caller-owned descriptor.
Copied, foreign, retired and mismatched originals retain their existing refusals.

This selection covers the same POSIX mapping/storage ownership mechanism only.
It does not emit the Rust allocation entrypoints or select the Darwin
compiled-image hashing path, a Linux compiler or
Engine image, Rust/VM admission, an installed Python supplier, or normal funding.
The existing Darwin selection and its physical semantics remain unchanged.

## Command-preparation Read facility containment

The selected Native command may distinguish a finite supplied Read facility
from a complete input-graph demand bound. Existing managed and native demand
fields retain their original meaning. The finite selection applies only to
Runtime loading and static Project, Task and Journal preparation; it does not
supply business Read, Source, Compute, Model, Effect or another Host.

Before its first Read context or payload allocation, the original domain can
consume one physical allocation-ceiling selection. The same allocator enforces
that ceiling against all occupied pages, including its control table, managed
slabs, generic extents and failed physical retirement. An invalid or late
selection consumes the attempt and refuses further allocation. It cannot be
replaced after exhaustion, scope leave or logical success. Releasing an actual
extent may permit its ordinary reuse within that same ceiling; it neither
changes the ceiling nor retires or replenishes the parent holding.

The mapping itself retains its original full extent and physical cleanup duty.
This ceiling is not another pool, reservation, domain, Ledger or capacity issuer.
The existing claim, workspace, bootstrap and child reservations remain distinct
and current. All earlier and later allocation routes outside the entered Read,
external control, loader, TLS, stack and filesystem holdings still require their
own actual coverage. Required primitive and inspection minima, input/work bounds
and the original exhaustion and cleanup semantics remain mandatory. Component
containment alone does not establish ordinary command success or normal funding.
