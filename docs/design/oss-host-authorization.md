# OSS Host authorization behavior

## Local Result read authorization

Result identity and the authenticated principal do not replace the current
Account tuple. Local payload, description and delivery-attempt reads evaluate
the actual installed connection, `result/<name>` and `read` through the existing
Common Account owner. One public operation observes and evaluates each actual
permission tuple once, retaining its immutable facts on that operation's owned
request. Internal getters, trusted Store reads and awaits consume those facts;
they do not create a new authorization boundary. A new public operation observes
the selected configuration again, including current Deny. Changed, missing or
invalid bytes never reuse an earlier operation's Allow. Delegate still
requires the existing configured answer and post-application-callback current
check, and cannot manufacture a Checkpoint or
approval. Standard Local bootstrap adoption remains the distinct initialization
responsibility required by `policy-routing.standard-local-bootstrap`; absence
of an adopted configuration is not an Allow.

## Local Run observation authorization

The public Local Host entry checks the current `run` / `read` permission on its
actual control connection before Run status, wait, attach, plan/inspection,
owner observations or request/submission lookup reads their Journal. Each
public operation evaluates that tuple once. Internal revision loops and trusted
Store observations consume the admitted decision, not another Account check.
Pure checking/static planning and named Result delivery do not borrow this
permission: `result/<actual name>` / `read` remains its distinct original tuple.

Both read entrances retain the same installed Account identity and observe its
current configuration for each new public operation. If this same owner already
observes a changed Account during another operation, a pending operation cannot
reuse a decision for the old Account value. That cheap revision comparison does
not read or evaluate an unchanged policy again. Delegate still uses the original
application answer and post-callback current check; it creates no approval or
cleanup acknowledgment. Internal cleanup remains independent of public read
permission.

## Standard Local Account initialization

The ordinary exclusive Host initializer materializes Common's complete
standard Local profile using the actual principal, control connection,
configured connections and registered Task/provider pairs. These subjects
have stable code-unit ordering, independent of process locale. An explicit
Account configuration replaces this routing; its invalid or unreadable state
never selects bootstrap instead. No Reviewer signer is created by adoption.

The actual fresh root-format creation result may start the existing durable
initialization intent before later Host setup. A valid same intent may resume
that initialization. A legacy two-field format marker alone does not establish
either condition. The same prepared Store exclusion protects the intent,
materialized configuration and durable Host adoption reference. Adoption is
confirmed before any protected dispatch uses the profile. File and directory
sync failures retain their original uncertainty and cleanup duties.

The retained profile material and initialization reference are not current
permission. Every protected operation still observes the selected Account;
operator restrictions, including Deny, are neither merged nor overwritten.
After materialization a missing configuration is refused, and an adopted Host
with a missing intent, material, configuration or Store is not initialized
again. Reopening retains the same Account identity and durable originals,
without depending on cross-process pointer identity or restoring old grants.

## Original Checkpoint ID answers and SDK reference views

An original-answer callback remains responsible for key custody and current
authority, but cannot change the requested action. Before resolution, the SDK
admits the returned artifact shapes projected from the existing registered
Resolution/Evidence contracts and compares their decision, subject, Checkpoint,
required artifact, review and approval bindings to the captured original
Summary. Self-addressed identities are checked without changing the signed
bytes. A mismatch retains those exact returned bytes for inspection and refuses
resolution; it neither signs again nor treats the bytes as a retry permission.

The SDK's `approve(id)` and `reject(id)` use the existing authorized exact-ID
Checkpoint lookup with one result. They do not scan pages, select the first
pending Checkpoint, resolve an alias or submit another Run. The admitted full
Summary supplies the original subject, required artifact, review and claims to
the existing signed-answer/resolution path. Lookup or an ID grants no authority;
the Host still authenticates the actor and checks current policy, original
Checkpoint/Run, approval scope, trusted key and saved answer correspondence.

An explicit application signer retains its original callback, receiver and
selected metadata across lookup. An installed Local provider may instead offer
an original-answer operation, not a generic signing callback. It must separately
bind the supplied Summary DATA to its actual original key, request, signing use
and current authority. Absence is unavailable, never Host-key fallback, unsigned
approval or key creation. Its pending Promise belongs to the existing Client
lease/Host handling sets until it settles; closing does not forget that duty.
An uncertain signing operation retains its own original claim and cleanup.

Only the original signed answer is delivered through the existing resolve
operation. A lost resolution reply exposes those exact signed bytes under the
existing `ResolutionUnknown` contract. There is no automatic re-sign or resend,
and neither cancellation nor Promise completion proves physical key retirement.

An SDK Run-state observation adds readonly, nonenumerable `id` only to an
actually captured and validated Checkpoint reference. It equals that same
immutable reference's `checkpoint_id`. Wire bytes, canonical preimages, signed
and saved data and outgoing packets do not gain this property. The SDK declares
its presentation type separately from the closed wire. Ordinary `wait()` may
return a legitimate outcome without a Checkpoint; optionality stays explicit,
with no placeholder, assertion or implicitly throwing accessor. The reference
is not a review, item list or approval evidence; applications retrieve the
original semantic review separately when needed.

The one-Summary lookup bounds its response, not its physical funding. Captured
signer metadata/callbacks, lookup wire and decoded Summary, signed artifact and
preimage Strings, captured signed-item/transport copies, pending Promises and
exact response-loss items overlap within the original Client/Host inventory.
Freezing or dropping a reference is neither physical retirement nor numerical
funding. A physical key/use supplier must cover its own additional lifetime.

## Original public Host signer selections

The Node Host's private Local-signing metadata view delegates exact grant/use
wire admission, identities, finite limits and full expected-scope comparison to
the existing Credential Owner. It retains that runtime's opaque values behind
view-local references; copied or foreign references cannot cross the seam.
Callbacks and their runtime receiver are captured once. Expected scope is an
explicit original argument, never inferred as current permission from the
candidate grant. The view issues no grant and claims no use ordinal.

Retiring this metadata view cuts its own references and refuses escaped
operations. It does not stop signing, forget a pending claim, acknowledge key
cleanup or discharge Unknown. The installation must retain physical key,
Account/issuer, request/Checkpoint/Run, durable original-use and outcome duties
independently. Its private maps/tokens/callbacks, decoded metadata and writer
overlap still belong to the original Host/Run resource inventory; no numerical
coverage follows from bounded metadata or reference retirement.

The existing Common Host configuration boundary projects the `signers` portion
of an explicitly selected `actql-host/0.1` original. It retains the exact input
wire and private-constructor selections for each original name, principal, key
ID, two key-file locators and declared Checkpoint kinds. The existing
Checkpoint Owner decodes kind names. Paths and data strings are not resolved,
normalized or rewritten by this projection, and it issues no new CID.

This is a bounded structural projection, not complete Host configuration
admission. `account_config`, `run_policy` and `effect_policy` still require their
own original admission and current checks. Project discovery cannot supply this
Host original or add signers. Absent `signers` and an explicitly empty map stay
distinct; neither produces an implicit signer, default key or signing grant.
Exact name selection never chooses the first available signer as a fallback.

The trusted Host installer must bind the same selected configuration and key
files to its original adoption/generation, authenticated principal and current
Account. A parsed path, public key, equal wire or copied selection does not
establish key custody, public/private correspondence or resolve permission.
Default Local key creation belongs to the original initialization, not a
recovery read that discovers a missing key. Host-attestation keys cannot stand
in for reviewer authority. Signing still requires the original Checkpoint,
Run/request, approval scope, exact preimage, original use claim and independently
current role/key checks; Unknown never allocates a replacement use.

An Effect Checkpoint, whether issued by genuine Account delegation or an
explicit requested stop, ends strictly before the same admitted Run's original
exclusive deadline. The Host projects that immutable lifetime from the retained
Run Definition, caps its existing Checkpoint TTL at the last preceding
millisecond, and refuses an empty window after asynchronous preparation. This
does not renew the Run, replace a saved Checkpoint or relax Common's lifetime
reader; approval and signing still require the current original authority.

Read limits bound UTF-8 input, parser nodes/depth and selected signer count.
They do not fund the original String, byte conversion, parser workspace,
selection records, key-file reads, signing work or their overlap. Those costs
and reference retirement remain with the original Host/Run resource lifetime.
The private Node/RelA bridges expose only this DATA projection, not an approval
or a physical signing endpoint.

## Original sealed Effect review evidence

The existing Common Preview/publication Owner projects an admitted private
Preview into the normative restricted, encrypted review artifact. It checks
the same original Run, complete member/row identity chain and Authoring Context
before copying scope, required permissions and row evidence. Strength is copied
from each original member, and guard/change/before/after states retain their
original absent, unavailable and present distinctions. An authored field target
is not replaced by one row's concrete ResourceRef. A concrete original target
uses only the existing closed ResourceRef alternative.

The structural row extensions preserve old absent-field encodings. New issuance
and approval admission additionally compare the complete projection with its
original Preview and trusted Host scope/claim/redaction-policy originals. An old
artifact missing evidence is not upgraded from its shape, CID, a row's values or
current configuration. Metadata remains author-supplied context, not authority.

Common owns canonical self identity and semantic correspondence. The Host keeps
the original opaque Preview and wire, current authorization, existing encrypted
Store holding, Checkpoint and continuation. A review's self CID excludes only
its own root field; a Store byte digest includes the complete wire and is not
that self CID. Approval binds the review actually shown and cannot discharge
another Preview, scope, claim set or redaction policy. Neither projection nor
physical persistence issues an Account grant, apply permit or cleanup ACK.

The Python and Node Clients verify self-addressed Effect review bytes in the
existing exact DATA-key domain (`actql-review-projection/0.1`), including nested
row keys. They remove only the root `review_projection_cid` for that digest and
require the received complete wire to be canonical. Model review integrity
keeps its existing identifier-key domain (`actql-run-review-projection/0.1`);
legacy complete-byte digests remain a distinct transport-integrity path. This
check neither readmits a private Preview nor supplies its semantic correspondence,
current authorization, signing authority or resolve permission.

The existing private continuation ledger keeps those two identities on the
same review holding: its historical `semantic_cid` still addresses complete
plaintext bytes, while optional `artifact_cid` names the Common self-addressed
review. The latter is allowed only for the review role. It is not a second
index, a new custody issuer or permission to read an arbitrary Store object.
The original Run/request, installation key, holding derivation, retained state,
full-byte digest and Common review/Checkpoint correspondence remain required.
The original continuation bytes and their requested-stop binding do not change.
Historical unassociated holdings keep their old byte-addressed behavior; no
pending Checkpoint is upgraded or reissued. The added metadata String, serialized
entry, bounded parser node and saved/read response overlap remain in the same
Host/Run inventory; structural parser allowance is not numerical funding.

The projection overlaps the original private wire, bounded parser/readmission
workspace, original identity inventories, member/row traversal, output writer,
canonical body, sealed wire and returned DATA aliases. Original per-Run/Host
reservations must cover that overlap; bounds or reference retirement are not
funding, physical release or GC evidence. Original failure, Unknown, cancellation
and cleanup custody remain with their existing Owners. No historical pending
Run is rewritten or replayed by this connection.

Status: design draft, not implemented behavior or a new conformance profile.
The [agreed authorization model](host-authorization.md) owns the two-layer
responsibility decision. This document describes its OSS Host realization.
Unconfirmed product choices are explicitly marked below; existing pinned
protocols, CLI schemas and secure Local defaults are not silently replaced.

## Product boundary

The OSS Local Host runs without ActQL Cloud: local account configuration,
Connector credentials, decision input, private artifacts and durable Run state
are sufficient. Cloud login, a policy server and an organization directory are
not prerequisites. Individual Connectors may still need their provider's
authentication. Local-only capability is not a promise that arbitrary remote
providers work offline.

The intended experience is: local computation works immediately; persistence and
keys require no manual setup; external connection setup and grant selection can
be completed in one flow. These are product design goals, not SDK/API support
claims. First-use initialization is separate from package installation.

## Supplied inputs versus acquisition

Pure transformation/aggregation of caller-supplied in-memory values needs no
Connector grant. A file explicitly supplied by the operator with CLI `--input`
is caller-supplied input, like stdin, not a Program-requested Connector read.
The Host may read/capture that specific input for this invocation without an
additional Connector grant. It does not thereby authorize directory traversal,
other files, subsequent Connector access, output writes or data egress.

The Host still enforces input admission, resource budgets, data protections,
path/alias checks and immutable capture before durable continuation. Subsequent
external operations remain subject to account grants. An embedded application
must establish its caller's authority to supply locators; a Program cannot
promote its own file path to trusted operator input. Stdin or an explicitly
supplied file does not confer authority to modify Host configuration.

Reading a file through a Program's local Connector is acquisition and requires
a matching grant. An input filename that happens to lie outside the managed
workspace is not a blanket grant to that location. Result delivery continues
to use its separately specified destination/read/egress checks.

## Reusing admitted Account originals

Wire admission retains its existing bounded UTF-8 input privately with the
typed Account. Binding that same Account to adopted Host material compares the
exact original bytes instead of decoding, admitting and hashing them again.
The correspondence query neither evaluates a permission nor exposes the
retained backing. Typed admission without a wire original and different wire
spellings keep the existing validation path; semantic equality alone does not
select reuse. Existing Account CIDs and wire admission rules are unchanged.

The retained representation reports this original byte buffer and its length
separately from compiled entries and Strings. It extends that already allocated
input's lifetime to the Account lifetime; it is not free storage, a capacity
grant or a cleanup acknowledgement. A new operation still observes current
Account state, and Run and named-Result permissions remain distinct.

## Local initialization

| Scope | Initial behavior |
| --- | --- |
| Caller-supplied values and pure computation | No Connector grant required. |
| Host-internal Run Store and keys | Automatically prepare on first Host use; private evidence remains encrypted. These internal resources are not exposed as general Connector write targets. |
| Host-managed local work area | A documented, versioned initial profile may generate explicit, inspectable grants limited to that area and local execution account. |
| Arbitrary files and remote providers | No grant inferred from setup. Operator-supplied input is the narrow exception described above; Connector acquisition requires configured authority. |

Ship the profile as published content with an identifier, version and content
CID. The exact operation set, local-resource selector, root-containment checks
and profile body/CID must be specified and independently tested before shipping;
this document does not invent accepted config syntax or a placeholder CID.
The profile cannot mean all files, all registered connections or future remote
providers. Bind the generated configuration to the particular Local account
and managed work-area identity. Symlink/path aliases must not escape that scope.

On first Host use, materialize the profile as an actual configuration file and
record in durable Host/Run Store metadata which profile was adopted, its exact
version/CID, when it was adopted, and the target configuration/account/work area
and generated configuration identity. Leave the profile provenance in the
configuration as well. Operators can inspect, restrict or remove the generated
grants. Missing configuration alone never means first use.

| State | Bootstrap behavior |
| --- | --- |
| Verified fresh Local environment, no adoption record or existing configuration | Initialize once from the documented profile. |
| Adoption recorded, configuration present | Use the operator's current admitted configuration, not a refreshed profile copy. |
| Adoption recorded, configuration missing | Do not regenerate grants. Report configuration missing for operations needing it; pure supplied-value computation does not gain a Connector dependency. |
| Configuration exists without a completed adoption record | Do not overwrite or merge grants automatically; recover a matching recorded initialization intent or require explicit setup/recovery. |
| Host/profile version changes | Keep the adopted grants and profile identity. Expansion requires explicit operator adoption with a visible configuration change. |
| Store/adoption evidence missing in an existing environment | Do not infer freshness from a missing file or silently reset authority; require explicit recovery/reinitialization. |

Config-file creation and a store transaction are not assumed atomic together.
Persist a one-time initialization intent before writing the config, create
without overwriting existing content, and finalize adoption against the exact
created config identity. Concurrent initializers must share the same fenced
initialization claim. Interrupted/ambiguous initialization must not dispatch
Connector work or restore deleted permissions while guessing what happened.
Freshness is established by the trusted initialization operation exclusively
creating the selected managed area and recording its intent, with no conflicting
existing or unfinished state. No earlier bootstrap marker, special preload or
proof that a pathname has never existed is required. A destroyed Store in an
existing environment still cannot prove freshness. Config creation and Store
commit remain separate and interruption is recovered against the same intent.
No install-time hooks, automatic profile reapplication or key replacement on
decryption failure are implied.

Registering a Connector establishes connectivity, not permission to delete or
otherwise operate through it. The same setup flow may offer explicit grant
selection and write those grants, but registration/authentication alone does
not grant all operations. This preserves convenient one-flow onboarding without
making connection success an authority decision.

### Explicit Local Mock setup

The adopted [initial Local Mock authorization](../spec/execution.md#initial-local-mock-authorization)
uses the same Account, initialization, signing and Checkpoint Owners. An explicit
Mock choice by the trusted CLI or SDK caller consents to its first restricted
adoption; selecting a string inside a Program or merely discovering an untrusted
repository's Mock setting does not. No second confirmation of that same setup
or manual Reviewer/key preparation is required.

The initial scope allows the selected Mock Sources, Task/answers and necessary
Local control/Result operations. Its Mock UPDATE delegates to explicit signed
approval for the same Preview; coincident minimum-approval and stop-before-commit
restrictions need not create duplicate reviews. Host authentication establishes
the Local principal through the OS user or embedding application's trusted
context, with no mandatory Cloud identity service. Signer absence denies
approval/update, not independently permitted reads and no-I/O Mock inference.

Bind authority to the actual Mock backend, installation, Local principal,
Project/managed area and resource contracts. Equal aliases or a CID cannot
transfer it to live services. Avoid live Credential resolution and Provider
initialization, and fail missing Mock data explicitly without live fallback.
Contract-compatible row/answer edits need no regrant for new Runs. Existing
Runs recover their saved inputs, answers and Preview. Restart reconstitutes
handles from validated durable state instead of requiring the old pointer.

Publish the shared profile's real ID, initial version and canonical content CID
separately from each concrete installation's generated Account configuration.
The current admitted operator configuration controls current permission; initial
provenance is history. Deny/restriction remains effective, while expansion needs
explicit authorized configuration change. Exclusive first setup may automatically
register that Local Reviewer and generate its real purpose-confined key through
the existing distinct Owners. It does not approve, reuse a Host attestation key
as a Reviewer, or recover missing adopted keys by regeneration.

The [ordinary Host trust boundary](embedded-host-trust-boundary.md) applies to
setup and execution. Account adoption is not a physical-memory grant, but the
normal Host may acquire its own real resources through trusted platform APIs.
No startup-history or complete runtime-allocation proof is a prerequisite.
The published profile and physical adapters remain implementation work until
their ordinary package path passes; this decision alone is not execution evidence.

## CLI and embedded use

There are two uses of the same Core, not two authorization implementations:

- CLI Host: one local execution account can represent the operator. It owns
  account/config selection, decision presentation/input and persistence.
- Embedded Host: the application supplies trusted execution-account context and
  a delegated-decision adapter. Its own users and business rules stay outside
  Core. It supplies Host I/O/storage ports or uses the Local implementation.

Neither mode changes Core admission, binding, checkpoint or recovery semantics.
The reusable adapter interface does not require implementing Cloud governance.

## Configuration admission and trust

Reuse the explicit Local configuration selection mechanism; do not embed grants
in Program source or infer them from Connector manifests. Configuration assigns
the execution account and scopes outcomes by connection, resource and operation.
Do not place plaintext provider secrets in decision requests or review output.

Resolve and validate configuration before protected work. Conflicting overlapping
outcomes are errors regardless of entry order. Validate configuration structure
and selectors, not only the first rule that happens to match one operation.
Exact file schema, selector syntax, resource-universe validation and diagnostic
codes are pending coordinated specification work.

Explicit set exclusion is agreed: first subtract each rule's exclusions, then
check its effective scope against other rules. "Delegate except X" plus "deny X"
is valid because the effective scopes are disjoint. Remaining overlaps with
different outcomes are configuration errors, independent of rule order or
specificity. Concrete exclusion syntax is not yet an accepted config format.

Broad rules avoid enumerating principal × connection × resource × operation.
The agreed all-target selector includes future additions in its selected
dimension. An account can allow all resources and operations on explicitly
selected connections; this does not automatically select newly added connections.
Choosing all connections explicitly does include future connections. Finite
selectors are available when additions must require another grant.

No matching effective rule in the new configuration means deny. Broad matching
rules count: users need not add one entry per resource or operation. No-match is
applied only after exclusion and matching, not as an overlapping deny rule.
Report "no matching grant" separately from an explicit deny. This adopts a
default for account configuration. Explicit first-use profile materialization
is governed by [Local initialization](#local-initialization), not by no-match.

Conceptual configurations (not accepted file syntax):

| Use | Configuration intent |
| --- | --- |
| Simple Local | This execution account: allow every resource/operation on selected registered connections. |
| Cloud application | This service account: delegate the broad selected scope except X; deny X explicitly to detect later conflicting grants as configuration errors. |
| Controlled additions | Enumerate selected connections/resources/operations; additions outside them receive no-match deny. |

These broad examples are explicit operator choices, not the bounded Local
initial profile. Unknown/unconfigured
account identity cannot acquire a configured account's scope by self-declaration.

Check selector conflicts symbolically after exclusion, independently of discovery.
Delegate all except {X} and deny {X, Y} conflict even if Y is not yet registered.
Do not admit them by testing only the current resource inventory. A new resource
must not turn an admitted configuration into a newly conflicting one.
Evaluate overlap on full principal/connection/resource/operation tuple sets.
Tuple exclusions can produce non-Cartesian scopes, so intersecting projections
on every dimension does not by itself establish a conflict.

Explicit deny X makes a later overlapping allow/delegate a configuration error;
mere no-match denial does not. Adding a rule for a previously unmatched X may
therefore authorize it. Administrators can explicitly edit/remove a deny; this
is protection against contradictory settings, not an unchangeable prohibition.

Existing CLI documentation discovers configuration up the directory tree. That
is configuration discovery, not proof that the file is trusted. The Local Host
must identify the selected file/account to the operator, and its documented
trust boundary must make clear that execution of an untrusted repository does
not authorize that repository to supply elevated grants or trusted signer keys.
The adopted Native Local bootstrap uses explicit operator adoption into private
Host state, rather than discovery as trust. Its initialization, recovery and
identity requirements are specified in
[Native Local Host binding](native-local-host-binding.md). Adoption is not
implemented merely by selecting a file; existing discovery defaults do not
silently confer authority.

Configuration identity and applicability participate in authorization evidence,
not Program Definition identity. Resume rechecks applicable current authority;
editing a file cannot relabel old evidence as a new decision. Nor does changing
a rule to allow silently close an existing unresolved Checkpoint.

## Normal execution

1. Select trusted Host context, execution account, configuration and state store.
2. Check the Program and required execution capabilities. Invalid Programs do
   not become valid under an allow entry.
3. At each applicable external boundary, Core applies the account configuration.
4. Allow continues without calling a delegated-decision adapter. Deny blocks
   that work; initial denial and later denial retain their distinct audit/Run
   treatment. Delegate hands the bound subject to the adapter.
5. The Host realizes the resulting dispatch or persistence intent. It does not
   independently reconstruct the next stage or alter the approved target set.

Pure computation and necessary evidence construction are not automatically a
human-review step. Conversely, reads, inference and egress can themselves need
authorization; an Effect decision does not retroactively authorize acquisition.

<a id="local-host-boundary-mapping"></a>

## Local Host boundary mapping (informative)

This table is guidance for the in-repository Reference/Local Host. It is not a
new normative Core dimension; another Host chooses its own connection and
resource identifiers. Core sees only the principal × connection × resource ×
operation tuple of [Account authorization routing](../spec/execution.md#policy-routing).
The operation dimension carries only the basic Read/Write/Infer/Effect
classification the [Run protocol](../spec/protocols/run.md#account-config)
requires: `read`, `write`, `infer` or `effect`. The kind of boundary stays in the
decision subject and the Checkpoint kind; it is never encoded as an operation
name. Advanced governance such as data inspection, model egress, query cost,
business risk, approver selection or batched approval remains the Host's
delegated-decision policy.

| Boundary | Connection | Resource | Operation | Decision subject | Deferred Checkpoint kind (subject) |
| --- | --- | --- | --- | --- | --- |
| Preparation, before operator-supplied path capture and Run creation | Source connection (the Local example uses the database locator) | Source resource (`schema.table`) | `read` | `preparation`; CID of the invocation request | `run_scope` (`prepare_attempt`) |
| Acquisition, before any provider session | Source connection | Source resource | `read` | `acquisition`; Prepared Invocation CID when known | `read_access` (`prepare_attempt` before the Run, otherwise `run_unit`) |
| Model catalog or metadata inspection | Model connection | Model resource | `read` | Read scope | `read_access` (where review is required) |
| Fixed Model call inventory, before a new provider send | Model connection | Model resource | `infer` | `activation`; Model Invocation Scope CID | `model_invocation` (`run_unit`) |
| Task activation on a Host-declared protected Site | Site key | Realization key | `write` | `activation` | `cost_scope` (`run_unit`) |
| Managed or remote transfer and output egress | Recipient Site key | Source Site key or output scope | `write` | `transfer` | `data_egress` (`run_unit`) |
| Remote Site dispatch | Remote Site | Site registration | `write` | `activation` | `cost_scope` (`run_unit`) |
| Effect Set commit | Effect target connection | Effect target resource | `effect` | `effect_commit`; Effect Set Preview CID | `effect_set` (`run_unit`) |

The principal is always the trusted Host context principal. Pure computation
over captured inputs on an unprotected in-process Site is covered without an
evaluation or a Host call. The Local Host binds its resume revalidation to the
principal, authorization context and admitted configuration CID, and to the
invocation environment; a changed configuration therefore fails resume
revalidation rather than reinterpreting an earlier approval.

Model invocation approval covers an immutable ordered call set. Its durable
send boundary is per call: after restart the owner reuses saved responses,
retains possibly sent calls as unknown without resend, and may progress only
proven-unsent calls under current invocation approval, infer authority and
egress permission. Expiry or cancellation blocks unsent calls without erasing
sent-call observation and cleanup. This extends the existing Model call owner;
it does not add a parallel scheduler or journal. The normative scope, provider
binding and original-evidence rules are in the
[Run protocol](../spec/protocols/run.md#model-invocation-approval).

Finite `read` selectors and adopted bootstrap profile content remain unchanged.
Invoking a Model requires an explicit finite `infer` grant or the existing
current-and-future semantics of `{all: true}`. Normal rotation of a credential
secret alone does not change the admitted nonsecret provider binding; changes
to tenant, security principal, route or request shaping do.

A deferred preparation or acquisition decision becomes a `prepare_attempt`
Checkpoint. Preparation is two-phase: the account outcome and any immediate
Host answer are decided on the invocation request before any path is read, so
a denial reads and captures nothing. Only a deferred preparation then captures
the operator-supplied Program, Environment and Parameter files as private
content-addressed artifacts, records the prepared invocation and continuation,
and seals the `run_scope` Checkpoint with that prepared invocation as its
required artifact; its decision-subject binding still names the request, and
resume requires both. No source is read before the Checkpoint, so there are
no source observations to reuse. The
resumed continuation reads only the captured bytes, reuses the permits and
approvals already admitted for the same attempt, and creates its Run directly
in `running` once capture completes. As its own delegated-decision policy, an
approved run-scope Checkpoint of prepared invocation X also answers the
acquisition of X's declared source in the same attempt under the same entry,
configuration, context and tuple; it answers nothing else. When the resumed
continuation reuses approvals the attempt answered earlier, each approval's own
permission is checked at the Host trusted time, not only the approval of the
Checkpoint being resumed.

An immediate Host permit the attempt received before it deferred is the Host's
own answer, not a reviewer approval. At resume it is reused only for the same
exact subject (entry, configuration, context, tuple, boundary and subject CID)
and only when the resuming Host supplies no decision function; when one is
supplied it answers that subject again, so a current reject or defer holds and
no provider session starts. It never extends to another attempt, another
subject or new protected work.

A resumed tuple the account now allows asks no approval, but the continuation
still resumes only through the common ownership admission (live claim, current
generation and lease, committed approval still valid, unchanged configuration,
single protected start per claim generation). The gate takes the configuration
CID from the admitted configuration itself and records it next to every
Checkpoint; a Host-supplied CID that differs fails installation.

Known limitations of the Local Host profile. The captured inputs and Host
records are held as encrypted private evidence, but the plaintext holding and
ledger records next to them name each private item by its content CID. A
low-entropy value (for example a small Parameters file) could therefore be
guessed offline by hashing candidates and comparing CIDs, even though the value
itself is only stored encrypted. Effect Set approval attestations carry no
expiry of their own: only the Checkpoint's answer deadline limits when they can
be committed, and a committed Effect Set approval stays admissible for the
resumed commit until its intent completes. Run-scope approvals, in contrast,
authorize new work only strictly before their own `expires_at`.

## Remote Host Run acceptance and the public Client (informative)

The installed Remote Host (`openInstalledRemoteHttpHost` with an
`authorization` installation) protects Run acceptance on its own Site. For
each request it evaluates the Host-resolved tuple (Site key,
`source-free-values`, `write`) before any Run Definition exists.
- `write` classifies the request to run on that Site; it is not an Effect.
- The decision subject is the Host-resolved request: the installation scope,
  the request identity and intent, the Site and the realization. The caller
  supplies none of these values.
- allow runs as before with no Checkpoint and no Host policy call.
- deny and a missing configuration refuse with their ACTQL code and record
  nothing.
- Without an `authorization` installation, the Site is unprotected and pure
  compute is covered, as for the embedded Local Host.

A deferred decision is held as a `prepare_attempt` `run_scope` Checkpoint:
- Preparation is two-phase. The account outcome and any immediate Host answer
  are decided on the request subject. Only a deferral captures the submitted
  document, parameters and result names as encrypted private evidence. It
  then seals a prepared invocation bound to that capture and writes an
  `actql-run-review-projection/0.1` review.
- The public Client sees a typed held request (submit and `lookupRequest`),
  never a fictitious RunRef.

The Client wire adds three operations. Each one is authorized separately.
- `checkpoints` lists a bounded page for the request owner, trusted
  reviewers and review readers.
- `checkpoint-review` returns the body only to the configured
  `reviewReaders`. It returns only the exact projection the Checkpoint
  names, and checks the stored size against the bound before loading.
- `resolve` accepts answers only from a trusted reviewer whose configured
  principal is the authenticated caller. Each signed answer is admitted by
  the common journal on its own.

The Host resumes approved requests when it starts, and after an answer
unless `resumeAfterAnswer` is false. The sweep never loses a wake: a wake
during a drain triggers another pass. A drain pages through every resumable
preparation. A busy or lapsed claim, or a transient failure, is retried
after the lease. The resume path:
1. Claims the durable intent. A claim whose revalidation fails (for example
   after a configuration change) ends the preparation. A Run already defined
   for it fails before dispatch.
2. Reconciles a Run whose physical start an earlier claim already reserved:
   the intent completes with it, and nothing is authorized or sent again.
3. Otherwise passes `gate.resume` with the common admission (live claim,
   committed approval still valid, same configuration, exact sealed artifact
   and decision subject). A refusal fails any defined Run before dispatch.
4. Admits (or looks up) the Run Definition. It enters the admission
   synchronously immediately before the physical start reservation; a later
   claim generation only reconciles the same request identity. Right after
   the reservation it completes the intent with the Run.
5. From then on, the Run is only observed (`listPreparationRuns`):
   - a terminal Run ends the journal Run;
   - a Run whose start is reserved but unfinished stays unknown and is never
     sent again.
6. Releases the continuation's evidence once the Run is terminal and keeps it
   while the Run is not terminal.

`close()` stops new resumes, waits for running dispatches and records their
ends, settles retention, and only then releases the journals and the Store.

The held-request index names only request IDs. It is written with a
directory sync and rebuilt from the captured submission when it is missing
or unreadable. `observe(step)` is Host instrumentation of the protected
steps; it never changes a decision.

The request owner cancels a request by its ID (`cancel-request`), with or
without a Run:
- The cancellation is recorded durably on the held request's prepare attempt
  before it is acknowledged.
- A waiting request ends cancelled at once, with its Checkpoint closed; a
  later answer is `cancelled`.
- A resuming request is left for its resume owner. The resume re-reads the
  durable cancellation after its claim, after admitting the Run Definition,
  and synchronously immediately before the physical start.
- When the request has a Run, created before or concurrently, the
  cancellation is applied to that Run through its own cancellation, which
  the physical start reservation observes atomically.
- A Run whose physical start was reserved first keeps its stop and cleanup
  owners. The held request's journal Run ends, and its evidence is released,
  only once the Run is observed terminal.
- Reviewers and review readers cannot cancel. Aborting a review read is not a
  cancel.

A Program with real input on a Host with an installed source profile is
also held before its source read, at the same prepare attempt and before any
Run exists:
- The read tuple comes from the Host's checked source, never from the
  request: the source connection, the source resource and `read`. The source
  profile's own account configuration and context decide it.
- allow reads with no Checkpoint. deny refuses the request before anything is
  read. delegate asks the Host decision; a permit is used once for this
  attempt's exact tuple, a reject refuses, and a defer holds.
- A deferral writes a `read_access` Checkpoint (`prepare_attempt`). Its
  sealed artifact is an acquisition intent
  (`actql-remote-acquisition-intent/0.1`) binding the request, the prepare
  attempt, the checked source, the read tuple and the source configuration
  CID. The review projection shows the same document with the source and the
  tuple.
- When the run itself was held first, the resumed `run_scope` approval takes
  the read decision in the same resume and may write the `read_access`
  Checkpoint next; the earlier approval is checked again when the read
  resumes.
- On resume the common admission is passed for the `acquisition` boundary.
  The physical read's own authorization check is then answered only for the
  exact admitted tuple, only while every approval is still current and the
  request is not cancelled.
- The read runs after the Run's physical start reservation. A Host that
  stops after the read started leaves the Run unknown and never reads again.
- Owner cancellation is the same as for a held run: a waiting read ends
  cancelled and nothing is read.

This profile has these limits:
- Only the installed DuckDB source profile (one captured source) is
  connected. `run_unit` Checkpoints on this Host are not connected here.
- One Host process owns a state directory. A second one is refused by the
  Store owner.

### Original source preparation in the portable Run Host

SQL and AQL enter the same Run Host ABI as structured Programs through an
original submitted intent and the installation's trusted query publication.
The existing frontend binds that publication to the same checked Environment,
retains the parsed Program and authored provenance, and selects the existing
Pure or Effect preparation from the complete checked inventory. A publication
is name-binding metadata, not acquisition, permission or physical capacity.
Missing installed target originals remain unavailable.

The preparation retains the original source, format, declarations and values
separately from the lowerer's ordinary Program projection. Request identity
uses that original submitted intent, never the source-free sentinel. The
existing JSON Run material codec consumes only the Owner's retained Program
projection; it does not replace the original submitted source. Legacy
structured preparation and material bytes remain unchanged.

For a new public read-only SQL/AQL Source without an authored RESULT, the
existing frontend configures the actual primary export as `main` before
constructing Program identity. It does not add an SDK alias or another Result.
Internal preparations selecting the historical answer recipe remain explicit.
New saved source-preparation metadata identifies the public-primary recipe;
the original four-field metadata retains its historical recipe when re-admitted.
Neither representation authorizes a Run: the independently retained request and
material/definition correspondence must still match. Existing durable request
names and cold Run observations return their saved Result names without compiling
or dispatching a replacement. The finite Mock Account scope names only supported
`result/main` and `result/answer` subjects; recognizing an older profile never
adds either permission to its saved Account.

A durable Host stores the original source metadata alongside the same Run's
authenticated material record. Recovery re-admits that saved publication and
Environment rather than rediscovering current aliases. It must retain the
same request, checked identity, compiled plan, authorization and Run definition.
Source Effect material admission additionally requires the typed original
source preparation and the independently retained expected request, then
checks the complete canonical material projection. Shape or CID equality
alone does not supply this original binding, current authority or a cleanup ACK.

An Effect's source-free SERIALIZE component also retains the explicit Host
data-policy body selected before compilation. Prepared-original capture and
saved Run materials project its paired `source_free_result_policy_cid` and
`source_free_result_policy_json` from that same component, not from current Host
configuration. Restoration admits the exact source-free policy on the restored
checked Program before recomputing the Plan, then verifies the independently
retained Plan or Run identity, original request and canonical materials. Missing,
partial, malformed or wrong-purpose pairs refuse; recovery never supplies a
default policy. Acquired Source and Model dependency policy retain their own
closure. Other historical materials omit these fields and keep their bytes.
This policy DATA neither authorizes an Effect nor acknowledges Content or
physical cleanup.

Initial and retained-input task dispatch use that same original Source
preparation when the request contains authored-source identity. Common checks
the preparation's nominal checked computation and reconstructs the request
from its admitted intent before comparing the independently retained request.
The absent-Source path still requires the original source-free sentinel. A
non-sentinel CID alone, another preparation of equal source, or another
source request cannot select this branch. Existing Program/parameter, Run,
task, attempt and retained-input/current-custody checks remain in force. The
Run Host facade keeps this Source token private in its original preparation
membership; callers do not provide a raw token or manufacture a replacement.

## Delegated-decision adapter

The logical request contains or references the admitted execution account,
decision subject, scope, operation, relevant Plan/Preview/context identities and
the evidence that the recipient is permitted to inspect. Concrete targets may
only be available after authorized acquisition. Do not expose secrets or private
payloads merely because an adapter can answer a decision.

The adapter's conceptual results are permit, reject or defer. These names are
design vocabulary, not a new wire enum or API signature. The coordinated Run
protocol specification must define the immediate-answer envelope and map defer to
the existing Checkpoint/Resolution mechanism.

| Adapter outcome | Execution behavior |
| --- | --- |
| Permit now | Authenticate and validate the answer's scope/context; continue without a dummy Checkpoint. Retain the applicable decision evidence. |
| Reject now | Do not dispatch the affected unit; retain earlier work and unknown outcomes. |
| Defer | Durably seal the decision subject and continuation; expose the existing waiting state, then release the execution process if requested. |
| Error, timeout, malformed answer | Never infer permit or intentional reject. Report a technical decision failure under the eventual failure mapping; do not dispatch. |

Core, not the callback's return type alone, determines whether permission is
admissible. The adapter is installed/configured by the Host, never supplied as
executable code by an ActQL Program. Callback failure/retry must not resubmit
provider mutations. No unlimited callback retry loop is implied.

## CLI handling of deferred decisions

The existing management vocabulary is sufficient: run, status, approve,
reject and result. Do not expose raw Prepared Invocations or require operators
to assemble signed protocol JSON by hand.

- A waiting response identifies the Run/Checkpoint and next available action;
  restricted evidence is retrieved separately with read authorization.
- Approval selects a configured authorized signer and binds the stored subject,
  not a re-evaluated Program or an edited local copy of the preview.
- Resolution storage, checkpoint closure and the unique resume intent use the
  existing atomic transition. Duplicate identical answers are idempotent;
  conflicting answers cannot both win.
- Rejection does not roll back earlier Effects. Unknown outcomes still need
  reconciliation; a human answer cannot turn them into known failure/success.
- Status polling does not approve, dispatch or redeliver Results. A failed
  Result delivery is retried independently of the Program and its Effects.
- `--stop-before commit` remains an explicit inspection request, not an account
  deny override or a way to skip provider requirements.

Agreed initial CLI behavior: save the Checkpoint and return, with explicit
approve/reject later. Neither an interactive prompt nor an external HTTP service
is required. Embedded Hosts retain the immediate-answer adapter described above.
An interactive prompt may be a
future convenience over the same persisted request, not a second authority path.
TTY presence, EOF or piped stdin must never count as approval. Existing exit-code
and JSON response contracts are unchanged by this proposal.

## External decision access without Cloud

The stored decision request should be retrievable through an authorized Host
interface; the response must return through authenticated Resolution admission.
This allows another local process or an embedded application to service requests
without an organization-routing product.

Transport is not yet selected. Initial OSS need not include an HTTP listener,
webhook receiver, directory watcher, shell-command hook or arbitrary script
execution. A copied file is not trusted simply because it appears in a directory;
any later file exchange needs exact subject binding, authentication, duplicate
handling and access protection. Do not present a transport placeholder as an
implemented remote authorization feature.

## Durability and recovery

Preserve encrypted private evidence, explicit retention, trusted keys, worker
fencing and logical request identity from the existing Local product boundary.
No implicit TTL, automatic evidence deletion, memory-only fallback or cloud
dependency is introduced. Store construction and key setup remain Host work.

| Interruption | Required recovery behavior |
| --- | --- |
| Before a deferred request is committed | No protected dispatch; no false claim of a durable waiting Checkpoint. |
| After Checkpoint commit, before CLI prints | Recover the saved request from Run state; do not recompute the target. |
| After verified Resolution commit, before resume | Claim the saved unique resume intent with current fencing. |
| After provider apply, before recording response | Retain unknown/reconciliation semantics; do not turn the decision into permission for blind resend. |
| Configuration/context changes while waiting | Revalidate; changed scope needs applicable new authority, not reuse of stale approval. |
| Two processes answer or resume concurrently | Existing CAS/atomic transitions admit one consistent resolution/owner. |

## Pending product decisions

Explicit trusted Local configuration adoption and a distinct Direct Local
credential scope are now adopted; see
[Native Local Host binding](native-local-host-binding.md). Concrete config
schema, immediate decision envelope and technical failure mapping must follow
those bindings before their public implementation is considered complete.
All-target scope, explicit exclusion, conflict rejection and no-match deny are
agreed semantics, no longer pending product choices. Initial grants are not
inferred from the convenience examples above: a documented initial profile may
be written once with durable adoption evidence. Publish its exact contents and
CID, and implement the adopted freshness, store/config recovery and containment
checks before shipping it. Empty authority is valid and Provider rights remain
explicit. The adoption decision is not evidence that those mechanisms already
exist.

## Acceptance checklist

These are design acceptance cases, not executed implementation tests:

- Local allow works without an authorization callback or Cloud connection.
- Local deny cannot be overridden by approve or a permissive adapter.
- Embedded immediate permit/reject needs no dummy Checkpoint.
- Deferred CLI execution can exit, restart, inspect and resolve the same subject.
- Noninteractive execution does not hang waiting for terminal input or auto-allow.
- Missing/invalid delegated answers never dispatch protected work.
- Unknown account, conflicting rules and malformed settings never gain authority.
- A broad grant covers non-enumerated resources/operations within its scope;
  future members match explicit all-target dimensions but not finite selectors.
- After exclusions, unmatched work is denied with a distinct no-match reason;
  disjoint delegate-except-X and deny-X entries do not conflict.
- Connector technical permission derivation still rejects insufficient provider
  capability, independently of ActQL grants and application-user authorization.
- Existing private-storage, read-scope and crash/recovery tests remain applicable.
- Configuration tests include conflicts on not-yet-discovered resources and
  edits distinguishing explicit denial from no-match denial.
- Configuration/wire tests bind evidence to exact contracts; docs tests alone
  cannot establish working authorization.
- Pure supplied-value queries and explicit --input capture need no Connector
  grant; Program-requested local Connector reads still do.
- First use writes only the documented bounded profile and records adoption;
  package installation itself does not create accounts, keys or grants.
- Removing/restricting the generated config and upgrading Host/profile never
  restores or expands grants. Existing config is not overwritten during setup.
- Crash/concurrent initialization and missing adoption evidence do not create a
  second grant installation; config/store partial updates are handled explicitly.
- Managed-root escapes and attempts to access Host-internal keys through a local
  Connector are rejected; registration alone never grants provider operations.
