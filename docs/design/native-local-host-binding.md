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
The missing pre-approval target-observation fence remains a separate scoped
ordering question; it is not supplied by inventing a future resume claim.

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
