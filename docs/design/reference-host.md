# Reference Host

Informative implementation guide, not an additional conformance profile.

## Authorization

The agreed [Host authorization design](host-authorization.md) uses execution-account settings and
`allow / deny / delegate`. Local can use one execution account; Cloud can
delegate application-user authorization without registering every user in Core.
Immediate delegation answers need no dummy Checkpoint; deferred answers use the
existing durable continuation. Human approval and application routing belong to
the Host. Conflicting account settings are errors, not a rule-priority system.

Encrypted evidence, secure defaults, retention and recovery guarantees remain
unchanged.

An admitted Account configuration does not itself select the optional signed
Checkpoint service. Account-only ordinary installations still evaluate the
same Host-resolved request tuple and current principal/configuration, and may
execute Account-Allow reads without Reviewer or Checkpoint signer settings.
Omitted signing settings mean that capability is absent; explicitly supplied
partial or malformed Checkpoint settings remain installation errors. Delegate
and operations requiring an approval, claim or requested-stop Checkpoint stay
unavailable without their real signing and durable continuation support. This
does not create an Account grant or replace Store integrity keys with Reviewer
keys; existing saved Preview, Run and Unknown recovery remains unchanged.
For a newly selected Run, an original submitted request for a commit stop
requires the actual Host's Checkpoint capability before new Run preparation or
publication. Missing support returns the existing typed preparation refusal;
it does not start Source/Compute work merely to discover the missing signer.
The Journal's existing-Run lookup does not issue a replacement Run or invoke
that new-Run capability check. An Account-only Host has no held Checkpoint
settlement service; the original Run Journal retains its physical-stop duties.

Optional Source diagnostics use the installed Host observer and the same
durable Run reference, including acquired Effect computation. A Source start
means the original adapter is being called after its current admission; using
an already retained capture or refusing that admission is not another start.
Diagnostic delivery never supplies read authority, permission or a physical
cleanup acknowledgement.

The installed Gmail labels entrance selects its reader through the same
original Source initialization and Host services as the standard JSON page
readers. Its existing profile grammar remains unchanged. One complete response
supplies both the total-response and single-page bounds; its admitted value
text bounds include the declared id String. The positive unused cursor field
does not imply pagination or allocate a cursor. These rejection bounds select
an implementation recipe, while the checked original Request still funds the
actual reader before construction. They are not a caller-supplied capacity.
Both the shared page reader and explicit physical label reader use one request
builder and Catalog projection, preserving exact mailbox percent encoding,
all declared cells and the complete-response refusal. The label installation
has no second transport/cleanup factory; Source retirement observes the same
managed reader and binding. Durable Credential-use Unknown remains independent
of physical transport retirement. Nested Gmail thread and Slack sequences
require their own complete constructor/output/failed-child recipe; a label or
ordinary JSON page quote cannot substitute for those retained sequences.

The [OSS authorization behavior draft](oss-host-authorization.md) details Local
configuration, immediate/deferred adapters, CLI resolution and crash recovery.
Its pending product choices are not changes to current defaults.

## Adopted local product boundary

The official Local Host target includes durable execution, encrypted private
evidence, scoped authorization and secure key/store/policy defaults without
asking ordinary users to paste secrets during setup. There is no ephemeral API
that silently abandons those guarantees. Private storage and the logical-item
ledger are part of the Host execution contract.

The Host retains logical request fingerprints and item reservations, fences
workers, reuses original Preview/dispatch keys during recovery and reconciles
uncertainty before resend. SQLite or a Cloud store is an implementation choice,
not provider exactly-once evidence. Engine and contract pins survive review waits.
Stages can span several tasks; task scheduling does not redefine stage success.

Resolved allow can authorize independent multi-Effect stages without human
checkpoints or mandatory risk claims. If a Host requires a risk claim for
delegation, authenticate and bind it to the decision's exact scope. Target drift tolerance
issues a new Preview and renewal authorization under explicit finite Host rules.
Private inspection independently checks data-read scope even for approvers;
keys themselves are never inspectable. SDK progress distinguishes accepted,
provider-completed and Program-completed states. Single-row/value access checks
exact arity and does not truncate Results.

## Follow-up connection and recovery defaults

The revised target runs stages through the common Run Graph scheduler, with
ordinary local-unit admission and separately authenticated graph membership.
Changing a downstream notification preserves unchanged upstream templates;
launching a new revision still needs admission, and success reuse needs an
explicit recovery link. Semantic risk and cumulative actual spend are useful
Host routing inputs, not mandatory restrictions on application authorization.
Decision reuse and optimization must preserve the bound scope, context and
validity of the actual decision inputs.

The proposed mail-attachment connection preset issues unlabelled captures as
confidential when the published policy permits that default. Stronger parent
policy wins; unknown labels/missing defaults fail. Configure an admitted model
destination/account/region/training policy once at connection setup, not by
asking for classification per PDF. The supplied fake preset is not proof that
live Gmail/model integrations meet these terms; live setup remains explicit.

Operator recovery UI offers “exceptionally commit this captured range”, not
“mark successful”. Show exact unmet duties, outcomes, loss/delay risks and
abandon/handoff destinations. It requires separate current operator authority,
fencing, signed state-bound claim and durable ownership transfer before ack.
Unknown retains reconciliation obligations; business allow cannot release it.
Source batch ownership prevents refetch under a fresh request id as recovery.
Stamp bookkeeping writes appear separately beside business writes and their
combined permissions are checked without switching to a stronger service identity.

## Collection integration admission

The Host snapshots the Program and options before asynchronous authorization,
requires concrete bindings, and admits an immutable private request. This
contains canonical bindings,
the exact Check Environment, bound identities, checked Plan, input materializations
and provenance. A Host receiving or rechecking this request verifies the
bound environment and request before dispatch;
a different environment or changed input/binding is a mismatch, not permission
to start a different invocation. The helper does not replace current authorization.

Local schema snapshots use `actql-local-input-schema/0.1` and retain the actual
checked schema. [Local Relation snapshots](../spec/protocols/contracts.md#local-relation-snapshot)
pair completeness with a materialization CID when a capture is claimed, retaining
the IntegrationBinding CID when applicable; static-only schema evidence omits
those claims without implying empty or complete data.
Compilation checks recursive assignability to the authored declarations and
uses the stronger schema as checking evidence without rewriting Program source.

## Durable local execution

The [Execution specification](../spec/execution.md) owns capture, admission,
replay and outcome guarantees. The [Run protocol](../spec/protocols/run.md)
owns Checkpoint and Resolution envelopes. The [Artifacts protocol](../spec/protocols/artifacts.md)
owns retained Result delivery and reference availability.

The local Host realizes durable decisions and continuation claims through its
storage interface. It commits verified Resolution storage, Checkpoint closure and the resume intent
together. Claim identity prevents a stale worker from completing a newer claim.
This does not make an external provider mutation exactly-once: unknown outcomes
still require reconciliation.

Result delivery uses its own durable request/attempt ledger. A completed
delivery is not dispatched again by status polling. Uncertain publication
remains unresolved; it is not treated as a safe failed retry.

Collection's finite serial Host API reserves remaining consumption before
dispatch and uses a Host-provided durable compare-and-swap callback. The
callback is an implementation port for the [Collection protocol](../spec/protocols/collection.md),
not a requirement to implement a general Run Graph scheduler.

An installed provider operation may additionally retain its exact first
request in the existing Run request Journal. Its live operation scope is
issued only after the same Run's first physical-start CAS returns confirmed
success. The original checked compilation, Program, Run Definition, request,
Journal and Store receiver remain one pair; neither a lookup result nor a
restored physical-start record can issue another scope. The existing Store's
active guard checks lifetime only, not capacity or permission.

Each checked Source occurrence retains one original preparation and RowRun
binding under that scope. The BigQuery adapter must prove its live JobRead
belongs to that same RowRun/acquisition through the existing Common Read
Owner, and its first request/record/wire must match that original. The Journal
commits the exact record under the original Run and task occurrence before
entering the existing driver's one-shot send callback. Current Source,
Account, Credential and physical resource checks remain separate.

The Infer material inverse keeps the legacy single-task compiler unchanged.
For a composed Program it selects exactly one original checked Model occurrence
and rebuilds the installed graph together with both producers and enclosing
Results. The complete graph and saved Run identity must agree; ambiguous Model
inventories and substituted dependency graphs refuse. Result policy is the
whole original checked publication policy, not a source-free unknown substitute.
The journal retains its kind, CID and bytes, and restore compares all three to
the policy derived from the restored original compilation. Neither this material
nor its policy grants current Source, Model, resource or continuation authority.

A prior record or a lost COMMIT reply never authorizes another POST. Cold
lookup yields unresolved original DATA only; it does not reconstruct a live
Job, Source, Run, permission or reservation. Missing storage bounds or Common
original bindings remain unavailable. Original Strings, row bindings, SQLite
statement/WAL work and pending failures overlap their existing owner lifetimes;
record persistence, return and garbage collection are not cleanup ACKs.

This editorial split does not relax the existing transaction requirements.
Replacing them with storage-independent transition guarantees requires a
separately reviewed semantic change and failure/concurrency evidence.


### Indexed submission retention usage

The existing Node request Journal maintains retained count and UTF-8 wire-byte
usage for submitted intents and explicit restart links in its own SQLite
database. Native triggers update these private metadata rows atomically with
the original insertion, deletion or wire mutation; they do not create another
authority or accounting Ledger. Formal intent retirement still increments the
existing retired counter, and retained count plus retired count must equal
original issued count. Restart retention remains distinct and cannot refund an
issued link. Existing record and byte quotas, target identity, current
authorization and transaction outcomes are unchanged.

The same Journal also maintains retained request and cancellation row counts.
Their insert/delete triggers run inside the original acceptance/cancellation
transaction and retained counts must equal the existing cumulative issued
counts. A lost row therefore fences new admission; it cannot refill quota.
Admission and cancellation read these singleton originals and selected rows,
not a count over unrelated history. An acceptance reuses its already observed
same-transaction retained count at the capacity decision. Name startup checks
the exact schema/triggers and original counters without another global census;
name use still checks issued/retained custody and authenticates its target.

A bounded one-time legacy adoption derives usage from the original
issuance/retirement prefix and detects extra or missing rows. The private
SQLite `user_version` transition commits in the same transaction as those
tables, triggers and singleton rows; it is not a public wire version. No
subsequent filesystem marker is needed to complete that adoption. Complete
metadata from the prior two-step format preserves its already derived intent
and restart usage without reaggregating those bodies or changing issuance or
retirement. The additive request/cancellation-count extension counts only each
original issued prefix once, with one lookahead row to detect lost coverage,
and commits both new singleton tables/triggers and its private header in the
same transaction. It adds no per-Run durable transition. An
absent or partial old derived marker neither issues authority nor blocks that
bounded completion. Missing adopted tables, rows or triggers still refuse.
Later ordinary opens and admissions
read only the singleton usage rows and selected original, not aggregate
historical request, cancellation, intent, name or restart bodies. This removes
those SQL censuses. An ordinary Local Host also passes its existing same-root
Store exclusion original to the Journal before native open. Under that
exclusion, supported SQLite is the format authority: admission checks bounded
schema/version metadata and singleton custody using the actual retained native
connection, without copying all DB/WAL bytes or scanning historical bodies.
Configured file extents, supported schema, selected-row authentication and
native partial-open/close duties still apply. Internally owned SHM/WAL creation
is normal SQLite resource management, not business authority. Standalone
inspection without that same nominal exclusion retains the isolated strict
snapshot path; deep whole-store inspection is not an ordinary-open prerequisite.
Failed row changes roll back their usage;
an unknown COMMIT remains unknown and cannot certify another insertion or a
safe resend. This does not replace the original Run/intent reconstruction or
any real native close acknowledgement.

## Original query evaluation time

Query invocation time belongs to the admitted Run, not to policy metadata or
the current observation clock. Checking, lowering and structural compilation
do not read a clock. For a genuinely new time-dependent invocation, the Host
retains its actual sampler and receiver and captures one value after request
lookup, before dependent acquisition and compilation. The existing Run
definition binds that exact value as `created_at`. An older policy creation
time is not a fresh invocation sample, and selecting query time does not
extend `valid_until` or establish current authorization.

The existing invocation preparation retains the original checked Program,
request and admitted Timestamp sample. Final binding checks the same nominal
compilation and Run definition, verifies the unchanged sample, and retains one
opaque evaluation context. Source predicate preparation and downstream frames
consume that same context, including lazy expressions when demanded. A static
acquisition shape keeps its query-time dependency unresolved; it cannot pass
physical material admission. Missing or foreign request/preparation bindings
remain unbound rather than becoming literal substitutions or hidden Parameters.

The physical QueryRequirement and its completed observation retain the same
admitted Run Definition CID in their existing owner when query time is required.
The authored filter remains unchanged, so equal filter or request CIDs cannot
substitute a different invocation's capture. Structural acquisition shapes do
not contain this Run-dependent physical projection; it is never fed back into
the Plan or Template that defines the same Run. Unrelated legacy requirements
omit the member and retain their complete canonical preimages.

The request Journal confirms the original definition before dependent
dispatch. Lookup, a racing issuer, approval continuation and recovery consume
the winning saved definition; none samples a replacement time or issues a
second Run to resolve missing material. The existing materials codec retains
`created_at`, so legacy absent-operation bytes need no new member. Query time
is computation data only: expiry, retention, rollback, current Account policy,
physical resources and cleanup acknowledgements keep their separate owners.

## Ordinary Host initialization and preparation

The adopted [ordinary Embedded Host boundary](../spec/execution.md#initial-node-control-preparation)
trusts the embedding application, supported runtime, standard libraries and OS.
The [decision and migration rationale](embedded-host-trust-boundary.md) replaces
the earlier startup-wide initial-control proof model. That model's special
preload, process-once generation and runtime-internal envelope are not ordinary
product prerequisites. Stronger explicit physical facilities keep their actual
contracts when selected; their diagnostic implementation is not the public
Host factory.

Normal public initialization validates the documented options, snapshots its
internal configuration, loads the selected packaged Core, and acquires the
state directory, Store, crypto and resources needed by that Host instance.
Trusted callback acquisition needs no prior accounting of an arbitrary closure
graph. Encoded configuration and external requests retain their bounded
read/decode/parse/type checks. Package integrity and API/ABI compatibility remain
relevant; one compiler pin, exact runtime patch, load-cache ancestry, pristine
stdout or absent diagnostic options is not an ordinary initialization authority.

Configured Model Providers follow the same ordinary factory boundary. The Host
retains its actual Provider callback and loaded SDK module originals, checks
the same installation and Store while they are borrowed, and retires those
references with the Host. Early import or eager compilation history is not
required. An explicitly selected diagnostic startup may still check its own
history; normal initialization neither manufactures nor borrows that proof.
Provider registration alone supplies no Model I/O admission, quantity budget,
current authorization or permission to send. Model preparation and dispatch
retain their original Common Scope, same-Run limits and physical child cleanup.

Each Host owns its active/closing/closed lifecycle. Independent Hosts and reopen
are supported within the same process, subject to actual directory locks and
resource limits. A shared module/runtime cache does not become a Host child
that must be unloaded before close. A new Host cannot reset a retained Run's
budget, request identity, send state or adoption history.

The final installed Check Environment and query-name publication retain their
pure Common preparation for that Host's lifetime. Declaration admission and
catalog/index construction happen once for those same immutable originals,
not again for each query. Source and JSON Effect preparation share that original;
a changed or request-specific Environment receives its own preparation rather
than borrowing the base installation's facts. Query inputs, work limits,
current permissions, target selection and durable Run transitions remain separate.

The existing Host slot binds the original runtime namespace, Environment and
publication to that same Host. Use checks only its local identity and closing
state; it does not repeat catalog admission or Account evaluation. Final Host
retirement cuts its private publication association and aliases after the existing
child shutdown duties, including partial-failure retries. It does not invalidate
other holders of the pure immutable Environment or manufacture a physical ACK.
The same boundary invokes the installed preparation consumer's captured
retirement method with its original receiver before releasing the Host slot.
That consumer drops its retained Source/Effect catalog and installation aliases;
a closed Client's surviving closures cannot keep that cache through this holder.
Pending child cleanup retains the original holder and its same release retry.
The lifetime getter closes over those installed originals in their initialization
scope, rather than resolving runtime or publication names outside that scope.

The existing Host and Resource Owners acquire actual buffers, files, database
connections and selected workers. They bind each operation to its checked Run,
limits and current permissions, without claiming that a declared byte total
funds the VM or that a foreign Native arena backs JS allocation. Runtime-owned
parser values, closures and JIT allocations belong to the trusted platform.
Managed data, queue, batch, retained-result and call limits still apply to their
actual subjects; measurements and failure behavior describe the remaining
runtime overhead instead of promising a whole-process RSS ceiling.

Partially acquired physical children retain their real owner, receiver and
retry/status until close or stop completes. In-flight native and zero-copy users
prevent release of their shared memory. Ordinary copied managed values can be
retired by releasing Host references; no GC or return of runtime caches to the
OS is required. A specific native arena's busy result cannot be hidden by
calling its still-live values ordinary managed memory: either release those
users correctly or allocate the values in an appropriate ordinary runtime
domain. Do not manufacture a physical acknowledgement.

A confirmed business result, pending cleanup and uncertain external delivery
remain separate. Cleanup problems do not erase durable success, grant a resend,
or silently release an active physical child. Current Account, Preview,
approval, key and saved-material checks remain in their existing Owners.

Mock follows those same normal facilities and execution Owners. Explicit
trusted Mock selection adopts its restricted initial Account profile and
prepares the Local Reviewer/key through the existing initialization paths.
It never selects a live Credential/Provider fallback or automatically approves
an Effect. The Host reconstructs restart handles from durable installation and
current authority; it does not demand a pointer survive process termination.

### Interface responsibilities during migration

These references describe the ordinary target and the remaining private helpers.
Existing operation-specific source and test references retain their meaning;
legacy startup helpers are not ordinary initialization prerequisites or a
same-process security boundary. Migration is not established by this inventory.

Preparation responsibility belongs to the existing Host instance and its
selected packaged Core/assets. Optional legacy helper selection cannot confer
additional authority or require a process-wide startup witness.

Input/output admission snapshots the documented configuration and selected
callbacks before asynchronous use; external encoded inputs keep bounded parsing
and their existing semantic contracts. An internal helper's restricted input
is not a new public options restriction.

Instance identity, original callback and receiver correspondence prevent
accidental substitution across Host, installation and Run operations. Durable
restart validates stored installation/current authority and reconstructs handles;
loaded-package integrity is not principal or operation authority.

Reference ownership follows the actual Host record and its real children.
Registry leases for the same Host share its retirement record. Captured methods,
receivers and opaque handles remain with their existing Owner; ordinary copied
managed values end Host retention by releasing its references.

Synchronization snapshots each selected method and receiver before asynchronous
use and checks the applicable Host/resource current state after fallible awaits
before exposing another lease or dispatch. It does not authenticate earlier
imports or the interpreter's execution history.

Failure retains the primary error and each partially acquired resource's real
cleanup duty. Missing optional compatibility startup selection does not prevent
ordinary initialization; unavailable required resources fail explicitly without
live fallback or fabricated allocation/release acknowledgements.

Cancellation requests stop and keeps unfinished tasks and shared native users
with their original cleanup carrier. Cancellation, a settled Promise or logical
retirement is not an acknowledgement that a live physical child was released.

Resource coverage distinguishes managed work/data limits and actual owned
buffer/file/DB/socket holdings from platform-owned module/runtime/library caches.
Selected asset read/hash/decode buffers retain their real lifetime; scalar
bounds, image metadata or content identity do not issue capacity or release.

Extension keeps supported ordinary options and normal factory acquisition
available independently of a private compatibility helper. Another backend,
operation or authority still uses its existing explicit contracts and Owners;
a helper restriction never becomes a language ban or an implicit grant.

Verification separates private helper/source checks from fixed ordinary package
acceptance. The latter exercises public options, SELECT/close, reopen and
independent Hosts, actual limit/cleanup failures and protected Mock operations;
no prior component check or retired startup proof establishes that acceptance.

## Installed Effect cleanup

The installed Effect Site retains target-read authorization, input pins,
physical execution, prepared-payload release and provider-stage disposal as
separate cleanup duties. Its completion is their conjunction. Revoking further
use does not prove that a callback, borrow or physical release has finished.
Consumer pins are released before Compute reclamation; completed child duties
are not invoked again while another child remains pending.

Target-read gates expose their existing authorization owner's synchronous
`close`, `cleanup` and `cleanupPending` facts. An in-flight delegated decision
can outlive timeout or abort, so `close() === false` remains pending until that
same owner confirms completion. A close-only child must be synchronously
retryable: a normal return other than `false` confirms release; `false` or an
exception retains that child for another close attempt. Cleanup never reruns
Compute, provider dispatch or authorization. Construction failure transfers any
already-held, unfinished gates through the existing cleanup-handle protocol.
The dispatch owner may record physical stop and retire custody only after every
retained child confirms completion.

## Standard Local configuration

A standard Local project uses `actql.config.json` for Program-facing project
configuration and `host.json` for Host-owned connections, credentials and
policy references. `actql init` creates a selected project template; creating
files does not start a Run, acquire business data, call a model or apply an
Effect. The public [configuration reference](../reference/configuration.md)
owns these filenames and user-facing options.

Absent `account_config` uses the explicit, durably adopted standard Local
bootstrap defined by [execution policy routing](../spec/execution.md#policy-routing).
Reads from configured connections and registered INFER tasks are allowed;
Effects delegate to `effect_policy`, defaulting to `review`. An explicit
account deny always prevents dispatch. Project configuration never grants
itself authority, and an invalid configured policy never falls back to these
defaults. Mock fixture replacement remains explicit and cannot substitute
fixture credentials or permissions into a real connection.

### Bundled mock catalogue declarations

The documented churn-risk mock installation has an explicit product catalogue
for Salesforce `Account` and Snowflake `usage_30d`. The Host selects that
catalogue under the original mock Project/Profile and installation generation;
it does not identify a contract from a Task, filename, row count or observed
values. Hand-authored equivalent projects and changed fixture rows use the same
declared schemas. Other resources require their own supplied catalogue.

`mock-churn-risk-catalogue.mjs` supplies immutable field-map schema wires,
their complete existing schema CIDs, positive query aliases and candidate-key
facts to the existing Common Relation declaration constructor. It does not
calculate a semantic CID, parse rows or check logical types in JavaScript.
Common validates the schema originals and constructs the Catalog, SourceViews,
contracts and evidence members. The `salesforce.accounts` read alias refers to
the original `Account` resource; it does not rename the UPDATE target or issue
an Effect Mapping.

The single owned `mock_churn_risk_catalogue.json` DATA source supplies both
that immutable Node asset and the generated typed Common input. The portable
Common factory admits the same declarations through the existing Relation
owner. Its opaque catalogue keeps private source and alias arrays; count/index
getters return the same original declarations for each logical name. Another
factory invocation creates different originals, even when their complete
Catalog bytes match. Native consumers reuse this factory rather than copying
schema wires, pins or alias tables into a second implementation.

Temporary typed inputs, view/alias arrays, schema parsing and hashing overlap
the two returned declarations and private catalogue arrays. Returned tuples and
declaration references retain their own caller lifetime. Factory construction,
alias membership and dropping a DATA reference do not establish an installed
generation, Source capacity, current permission or physical cleanup.

The declared Snowflake `active_users` type is logical Int64. Its physical
JSON codec must preserve full signed64 values without a binary64 round trip;
an admitted Number is not implicitly promoted. Salesforce `Risk_Reason__c`
is declared nullable Text even when all initial fixture values are null.
Candidate keys are `id` and `account_id` respectively. The actual fixture's
explicit key must be retained and validated against these contracts, never
replaced with the bundled key after missing or invalid input. Every known
field and row remains subject to original Source admission.

The descriptors supply no acquisition override: the existing empty bound
request, finite scan and projection-only contract remain with Common. Selecting
these declarations supplies neither an Account grant nor resources, business
Run custody, a Model profile, approval, target versions or cold restoration.
Those original responsibilities remain independently required. The immutable
module objects, schema/facts Strings and aliases remain retained alongside the
Common parsed declarations, encoding/hash workspace and Host installation;
module lifetime and bounds do not make that storage free or physically closed.

The existing Row Source owner also derives the mock Account UPDATE Mapping
from that same original declaration. It checks the selected implementation
generation, complete fixed field contracts, original View/facts correspondence
and `id` candidate key before calling its existing RelationUpdate constructor.
The private Node bridge forwards that original and returns Common's Mapping
body. It does not relabel a create Mapping or rebuild a CID in JavaScript.
The original Host still supplies the positive `salesforce.Account` target alias
and its installation provenance; a readable Source alias cannot supply it.
`salesforce:record:update` remains an operation requirement, not a current grant,
and the Mapping requires review. Neither construction nor successful checking
observes a target version, writes a row or confirms an approval.

#### Original physical Mock records

The existing Row Source owner accepts the full original Mock JSON document
under both installed Relation declarations. It consumes the selected RowRun's
own pending byte ticket before decoding, and requires the same acquisition,
prepared input schema and original declared view. A foreign declaration,
copied view, another attempt's ticket or repeated admission cannot substitute.
The ticket accounts for bytes; equal length is not original-body provenance.
The Host must retain the actual body, file/current observation and operation
correspondence independently.

Strict preserving parsing retains exact field spelling and numeric byte spans.
The two connection/resource objects are closed, each explicit file key must
match its original declared candidate key, and duplicate physical keys refuse.
Both complete tables, every row and every declared field are admitted before
any selected row is appended. Missing fields remain distinct from explicit
nullable values. A projected-out column or unconsumed relation cannot hide an
invalid physical value in this selected document.

For the original Int64 contract, the physical profile takes an ASCII integer
number token from that same parser span and original bytes. It never converts
the parser's binary64 value to Int64, and does not accept an external String,
fraction, exponent token, negative zero or overflow as an integer observation.
Canonical decimal String encoding is an internal schema-directed Value wire,
not a relabelled physical Text cell. Selected values use the checked input's
exact Contract objects and enter its existing typed-row receiver. Query request,
Parameter, residual filtering and eventual capture remain with the same
acquisition; no Source completion or current grant follows from decoding.

The shared full-file holding, each Run's independent ticket, parser String and
Nodes/spans, decoded tree, both schema/key originals, temporary checked cells,
selected row arrays, integer text/cursor conversion and append workspace may
overlap. Byte/node/depth/row/work bounds remain independent and are not funding.
Failure aborts only the same attempt. Data-reference retirement, ticket
consumption and successful row append are not physical cleanup acknowledgements.

The standard RowRun page entry retains its 400,000-node and depth-32 defaults.
An installed Source may narrow that page envelope on the same pending RowRun
through `begin_row_run_with_page_limits`; it cannot widen those defaults or
replace the original acquisition, schema, attempt or reference issuer. Invalid
bounds abort only that attempt. The Host must bind the selected limits to its
actual Source original. Explicit byte, node, depth, row and work limits remain
DATA, independent of the Resource reservation and current read permission.
A successful small document does not prove that the Source phase covers every
combination of its permitted input bounds. Exhaustion still refuses without
capture, replacement publication or a cleanup acknowledgement.

### Purpose-confined initial Local signing issuer

The original explicit Local initialization/adoption may retain an internal
issuance responsibility for the same physical Store and installed key
generation. This is a narrow operational admission inside the existing trusted
Host/installation and Credential boundary. It is not an authority inferred from
Host adoption, parsed signer metadata, public-key identity or possession of a
PEM, and it does not change the explicit Native issuer-file/Account route.

The initialization/adoption originals must authenticate the actual issuer
identity and an explicit finite signing expiry/use policy. Missing originals
stay unavailable, including on cold open. Do not derive a policy from the
Submission epoch, assume a use count or create a synthetic issuer selection.
Named selection cannot silently become the default. The machine-user identity
comes from the actual trusted installation/current actor, not a caller label.

The selected new default policy allows one physical use for an exact
purpose-bound operation and at most 300000 milliseconds from the first durable
issue's actual trusted sample. The existing packaged default-asset generator
supplies a distinct closed original, not an execution profile. Retain it at
explicit first initialization. Common formats the issuer identity as
`local-signing/` plus that original initialization intent CID, not a later Host
CID or a new identity domain. These DATA projections cannot authenticate the
original installation or create an operational issuer.

The first durable issue persists its actual sample and absolute expiry, capped
by any earlier original key/authorization validity. Checked time arithmetic
refuses invalid/uncertain/expired observations and overflow. Reopen, history,
repeated answer and Unknown do not renew that original. A missing legacy policy
cannot be backfilled by calling the packaged getter. Configured named signers
do not use this default-only policy.

Confine issuance to the existing original request/Submission/Run/attempt/unit,
Checkpoint/kind, purpose, key configuration/generation, preimage and finite use.
Current actor, Reviewer/Host-attestation purpose, Run read, Account and key/sign
authority remain independent requirements. This connection grants no generic
credential issue, Source/Model/Effect or dispatch authority. Authenticate and
persist the original grant and durably claim the original use before signing,
with current rechecks around callbacks. Uncertain commits/signatures retain the
same original duty; no replacement key/grant/use, re-signing or resend. Recovery
and saved-outcome reads cannot initialize missing originals or issue again.

The [Local signing contract](../../spec/contracts/local-signing-credential.md)
owns this distinction and the unchanged grant/use bytes. A metadata/key
component test is not evidence of initialized default or installed approval.

## Selected Node Source and managed Compute original

Source-read managed admission and Common managed Compute admission are separate
operational scopes of the existing Host and Resource owners. Neither borrows
initial-control credits. The actual selected ordinary package prefix retains
the original startup, runtime/module, installation and generation and declares
the complete joint disposition before covered input acquisition or preparation.
A matching image, scalar budget, callback, CID or accounting Ledger cannot issue
that disposition. Selected managed-runtime assumptions are not OS reservations,
universal V8/RSS guarantees or requirements for individual V8-object leases.

The joint recipe counts the shared process heap, compiler and native/module
domains once through their actual process and escaped-reference lifetimes.
Preparation, original wire, decoded rows, captured inputs, sequences, DAGs,
provider/import/output workspace, value/key frames, callbacks, failures and
pending cleanup overlap that same domain. Both Source capture holdings remain
beside the managed outputs. Standard direct capture settles its execution
reservation after capture; a serial Source-to-DAG path may therefore use the
actual maximum execution overlap, not a second whole-runtime allowance. Extended
provider captures cannot inherit that settlement argument. Insufficient or
uncovered scopes remain unavailable; no source or provider ceiling is reduced
to manufacture a fitting execution.

One original Run record is retained before the first packet snapshot. Its later
claim binds the actual original SDK request and opaque checked preparation; it
does not issue capacity retrospectively. The fixed Root compares the exact
prepared reference before returning its one imported-child port. Resource keeps
the typed preparation and checks physical identity again at the Host consumer.
The private JS ABI representation is used only for that reference comparison:
it has no public constructor, raw-field reader or admission semantics.

The installed managed Run exposes a read-only observation of its own live
Ledger: the six declared limit fields followed by the ten usage fields, including
reserved retention/execution, held bytes and peak retention. The private Node
bridge returns a fresh bounded Int64 array on every observation. A caller cannot
mutate the original accounting through a returned snapshot. Observation does not
check or confer current permission, reserve work, report or stop the child, or
acknowledge cleanup. Pending originals remain observable; foreign or retired
handles refuse rather than returning fabricated zero usage. These counters cover
that managed Ledger, not total process memory, Store storage or native/FD cleanup.

Source-free managed Compute uses a separately selected original in this same
Root, before the SDK's first packet traversal or snapshot. It does not create
a dummy Source installation, file, response backing or Source child. The same
Host's actual Journal request/control facility must already be retained and
open; its captured crypto originals cover request/epoch control only, not
Compute capacity. Neither facility can replace the other's operational purpose.

The fixed Host namespace follows the original pending request to its exact
checked preparation. The same Local sequence and receiving-port inventory
quotes source-free retained-output demand; it does not create another Ledger.
The existing imported admission then supplies the original Run Ledger, with
the same mutable-resource/park fence, usage reporting and partial cleanup.
Source-free preparations reject supplied Source capacities and transport
amounts, and cannot obtain a Source read. The supported two-Source path keeps
its original acquisition correspondence. Other unsupported backend shapes are
not invalid public Programs and do not silently fall back to accounting limits.

For an ordinary source-free Compute Run, the existing Host Run record retains
the typed generated sequences used to quote its six managed limits. The actual
Run and configured Compute Host consume those same sequences instead of
reparsing the unchanged registry, Values and fragment bodies during each
internal phase. This preparation is immutable data, not Resource admission or
permission. It remains bound to the original checked Program and exact contract
bodies; foreign or changed originals refuse without regenerating a replacement.
The scalar quote returns a bounded copy, and the sequence aliases retire with
the same Run after its actual children finish.

The same Run holder can retain a pure preparation refusal before Resource
admission. It binds the actual typed `Unsupported` result's error to its exact
prepared Program, original request and installed control. The private projection
checks that same failed holder, its current installation and the absence of a
Resource original, admission, begun Run or pending cleanup. An equal error code,
copied failure, different request or retired holder cannot issue this projection.
Later Resource or begin failures keep their original Unknown and cleanup path.
The original successful retirement also clears this managed refusal reference.

This projection describes the preparation boundary, not a Journal ACK. The
submission owner still retains its same callback candidate and applies current
authorization, disclosure and actual durable outcome rules. A lost Journal reply
remains Unknown; a visible row, error string or client Boolean cannot certify
nonacceptance. No second lowering or serialization is needed to classify the
original preparation result.

The installation's admitted AoA contract closure has a different lifetime from
a Run. Its private Host owner interprets the exact registry, Values,
expression-fragment and ordered-derive bodies once and retains the resulting
nominal `ClientInstalledSequenceContracts`. Source, keyed acquisition, Content,
Infer and managed Compute preparation require this same admitted bundle; no
process-global cache, absent-original branch or request-time parser supplies a
replacement. The retained source-free preparation additionally checks the
physical installed original, not merely equal contract text. The remaining
explicit contract-body arguments are checked against that bundle, never used
as alternative admission inputs. An absent optional fragment or ordered body
selects no such capability from the bundle; it does not reject a Values-only
prefix merely because its installation also admitted additional capabilities.

The bundle is immutable contract data, not permission, Resource capacity,
Ledger identity or a cleanup ACK. Each caller still supplies its own checked
Program, parameters, graph, limits and original Run. The Host binds the bundle
to its initial control and runtime, retains it while child cleanup is pending,
and cuts it during successful Host reference retirement. A new Host owns its
own admission even when its contract bytes equal another Host's bytes.

The Host retains the original admission before beginning the Run. A failed
begin keeps that same admission's unpublished or started cleanup, never a
replacement attempt. The source-free dispatcher opens its configured Compute
Host through this opaque Run and rechecks the original Ledger after sequence
selection. It cannot use the legacy scalar constructor on refusal. Successful
cleanup callbacks and receivers are captured before another child can await;
the original Run retires only after dispatch/DAG cleanup, before its installation
scope closes. Unknown retirement retains both duties and their aliases.

Both private views retain their fixed purpose-specific startup callbacks.
Currentness for a Source view cannot authenticate a Compute view or vice versa.
Shared process/module domains remain one original, with packet, preparation,
DAG, result aliases and pending cleanup overlapping their actual lifetimes.
Closing either view does not replenish that domain. Physical buffers, Result
or Content storage, Model, Effect and external I/O keep their separate actual
suppliers; a source-free quote or successful claim does not supply them.

The selected query entry acquires the same Source/Compute producer before its
first raw option read, not merely before the later `startSource` call. Its
private synchronous continuation consumes that receipt once; SDK-owned query
defaults cannot issue another snapshot. The initial supported query has absent
options and absent or null parameters. Unsupported original graphs are refused
without getters or enumeration, while unselected public grammar stays unchanged.

The bounded original raw snapshot and SDK submission are different DATA
representations: AQL input becomes `{text, format, parameterDeclarations?}`,
parameters default to null, and the SDK adds its original submission/attempt
control. The Root verifies that projection under the same nominal receipt,
retains the deeply frozen body, and rechecks it at intent and request binding.
A copied receipt or equal body cannot establish the original installation or
request lineage. Snapshot, projection copies and traversal workspace coexist
with the original packet/body, query continuation and failure aliases in the
same selected phase; no copy or Promise retirement refills the shared domain.

The in-process Host lease preserves both private connections: query intake
uses the same pending producer inventory as direct Source submission, while
Result read/current operations forward to their independently captured pair.
Sealing refuses new query/read work but still permits the same producer's
alias-retirement retry. A pending producer prevents both its lease and a last
sibling lease from finalizing the Host; Result forwarding supplies no Source
admission, Result permission or physical close acknowledgement.

The ordinary selected Node Host has a separate finite Local Result/publication
service. Its actual package prefix retains the same startup/runtime/module and
filesystem, crypto, Buffer, WebCrypto and Journal native originals before the
covered namespace and facility acquisition. The fixed namespace checks those
same imports and derives the Store authority and publication control from the
actual Host/root/principal and same Common instance. Matching support DATA,
capacity counters or a callback alone cannot issue this service.

The Host binds the Result control original after its actual Journal opens and
before exposing the SDK receiver. This covers an eager query collection's first
raw argument capture, not only a later Host request. The private SDK captures
the original read/current pair, checks before schema/option traversal or UUID
creation, and retains an opaque one-shot continuation across the query wait.
Internal defaults do not become a second caller intake or admission. The first
selected recipe supports absent read arguments; unsupported valid schemas or
options stay backend Unavailable before traversal, not invalid public input.

Store construction remains lazy and adopts the same prepared publication
exclusion. Its separate finite service includes retained initial/Journal and
selected Source/Compute originals, publication encodings, Store metadata and
payloads, Result readers/frames, actual native/managed controls, failed
constructors and escaped aliases. Shared process/module domains are counted
once. Historical Host/Store/read attempts are bounded without refill; request
and encoded-history demand is distinct from an actual backed amount or an
allocation-success guarantee. The existing actual Store capacity checks and
all independent physical close duties remain mandatory.

Before a first durable business Submission/Run admission, the existing Host
derives its finite Result candidate from the original checked Program and same
admitted managed Run. Existing epoch/name control and read-only/ready lookup
retain their Journal responsibility; an already accepted physical start is
never repaired by a new Run or replacement resource admission. Key creation,
first-initialization, Account, Result and business-I/O authorization remain
separate. A selected no-key Result Store does not load or manufacture the
legacy private Evidence key; a later key-dependent operation keeps its original
missing-key refusal. Content, Model, Effect and other physical suppliers are
not acquired by constructing shared service controls.

The original Store is retained before post-constructor current checks. Partial
opening failure keeps the same cleanup carrier while the acquired Journal
drains independently; their shared token survives until both original ACKs.
Cleanup does not require current admission. If a failure carrier completes the
same duty before its returned view observes it, that view receives the retained
original close observation, never another physical close or revived service.
Process-lived module/native and escaped managed aliases are not reclaimed by
that Store ACK, Promise completion or an empty DATA projection.

###### Ordinary generated Content Run

The ordinary Host prepares a source-free checked serialization Run before its
durable admission. The existing Content prefix provider and workspace derive
its managed limits; normal platform allocation supplies the actual memory.
The existing Content owner retains one Ledger with that exact prepared Program
and compiled Run, and consumes it once before prefix construction. A copied
plan, failed preparation or later currentness refusal cannot issue another
Ledger or fall back to the legacy execution-time constructor. A previously
started durable Run is observed, not regenerated under a new preparation.
Acquired or Model-composed shapes require their own connected same-Run path;
their absence is a backend gap, not an authored-language restriction.

For a selected Local keyed Content path, the ordinary Source installation
retains a separate Content-purpose Resource original before durable business
admission. Its checked preparation combines the Direct capture, bounded keyed
requests, lookup assembly and Content prefix on one Run Ledger. Source-only
and Mock Model originals cannot be converted into this purpose. The actual
Direct acquisition is rechecked against that same prepared Program and its
original RowRun before the Ledger is borrowed; there is no standalone Ledger
fallback. Each keyed request receives its own nominal child, with cumulative
history that close cannot refill. The installed Source retains its acquired
native reader before a fallible current check, and its physical recovery must
finish before capture cleanup and the parent original can retire. Received
file bytes consume their original RowRun observation ticket before the next
encoded row is charged. Neither a lookup counter nor a captured path grants
read authority or acknowledges physical cleanup. Model-composed Content and
other unsupported backend shapes remain separate connections, not language
restrictions.

The Host retains the first checked keyed selection in its original Content
preparation and forwards that same handle through the Source recipe and later
dispatch. Reselecting an equivalent operation is not the original child bound
to the managed Run. The Local Source explicitly selects Run-owned Content
capture before file I/O. Its read grant uses the same Account gate's captured
current-decision fence and receiver, not a second evaluator or a copied Allow.

Task splitting does not replace this original inventory: the JOIN and Serialize
may have different task ordinals. The checked same-owner dependency path, not
ordinal equality, binds the selected barrier. Prefix preparation retains its
original acquisition contexts and executes only the range after the completed
Direct capture, using the same sealed keyed inputs without Source replay.

The original response schema identifies one typed Content column. An absent
MIME refinement permits the actual MIME validated by the existing capture
owner; a present refinement must match it exactly. Initial capture and saved
reference restoration use the same schema compatibility check. Restoration
keeps the original reported MIME and complete reference evidence instead of
issuing a replacement candidate from an expected type string.

The Local Connector resolves keyed Content through the original captured
listing path and exact Resource/version pair, then obtains a current original
Account read decision. It does not reverse a Resource CID into a path, scan a
replacement listing or borrow metadata permission for content. The same native
Root child is retained before construction/current checks; failed physical
cleanup is reachable independently of Core capture retirement. Native reads
use one bounded exact-size output buffer and at most one 64 KiB temporary
chunk, rather than an unbounded collection of short-read control records.
That output overlaps the Store writer's append snapshot and the encoded row
workspace in the original declared Content demand. Raw bytes and encoded rows
consume distinct ordered observation tickets; neither ticket grants access or
acknowledges the other owner's cleanup.

This preparation grants no key, Account, Content reference or Result authority.
Private derivation evidence still requires its original purpose-confined key;
a no-key Result Store cannot infer key initialization from a missing file.
The ordinary Host selects its real 32-byte random AEAD key during the existing
Store initialization, without a Mock Account, Reviewer or signer prerequisite.
The same initializer's actual Root creation and prepared Store admission must
positively establish first initialization; absent Store and key directories in
an existing installation cannot supply it. Key selection completes before the
ordinary client is exposed, even if no query will open the lazy Store.
An owner-only immutable intent precedes the key write, and adoption records the
same key generation and Store contract after the actual Store opens. Reopen
validates and durably reconciles those originals without rewriting the key.
Missing or corrupt adopted/interrupted material refuses rather than rekeying.
An old no-key Store without positive first-adoption metadata keeps plain Result
support but cannot infer a Content key capability from absence. Key setup adds
no Account, Effect, approval or egress right and changes no evidence AAD.

The actual Store writer, generated bytes, private evidence and publication keep
their original custody. Cleanup stops and settles the same prefix only after
its physical writer and holding duties acknowledge retirement. Retrying cleanup
does not repeat generation or an uncertain commit. Managed limit arithmetic is
not physical capacity, an allocation-success guarantee or another child's ACK.
The Journal can close independently of a failed initialization FD, but the same
Store exclusion remains held until that FD and the actual Store acknowledge
their separate cleanup. A close-only retry neither repeats a partial write or
sync nor regenerates a key or Content object.

The Host retains the unstarted admission before fallible start/take, and takes
one original Run Ledger. The Source reads and the generated managed DAG
borrow that same Ledger internally. The existing physical Ledger equality at
capture transfer remains mandatory. Independent Source-only children, equal
limits, copied prepared values or a fresh scalar Ledger cannot replace it.
Currentness and the existing mutable-resource/park fence both apply before
preparation and after callbacks. Account and read/send authority stay separate.

The shared Source/Compute limit projection follows the checked capture-prefix
count, including a single installed RowSource. Declaration, capture, transport
and workspace arrays must match that original count; each capture must retain
the corresponding checked QueryRequirement. All captured inputs stay retained
beside the generated Compute suffix. The source-free entry requires empty
Source arrays rather than silently treating a missing acquisition as free.
This projection remains managed demand, not a physical supplier or read grant.
The separate local Mock Model purpose retains its own supported shape and
early original Scope; extending plain Source bookkeeping does not issue it.

An ordinary Project Local Source retains its exact connection declaration and
the same issued Project/runtime before installing the actual rooted reader.
The checked QueryRequirement selects a declaration for each capture occurrence;
the number of configured connections is not the Run's capture count. Repeated
reads of one declaration have distinct occurrence and child custody. The same
joint service can also admit a checked source-free Compute graph with empty
Source arrays, without creating another parent or borrowing listing bytes.
Captured original reader close/status callbacks and their receivers survive
currentness refusal. A pending child does not suppress independent sibling
cleanup, and every actual reader must acknowledge retirement before its Run
and installation retire. Managed reference retirement is not a native ACK.
Changing original connection bytes changes installation reuse identity; equal
Source labels cannot replace the retained declaration. Explicit Mock setup is
separate and never follows merely from installing a normal Local Source.

A Local Source feeding an Effect consumes the same adopted Effect Run,
Prepared, Request and read selected by the shared Source owner. The Local
record retains child provenance, not another Run admission. The shared typed
selection and the Host's original child consumer check that handoff; Local
does not repeat the Core current callback between them. The original
post-acquisition and post-await current fences remain. A consumed occurrence
is refused before another getter can return its existing read, so a failed
second preparation cannot retire the first read or its pending native child.

The selected ordinary Local factory supplies the existing finite
`lookup_execution` policy from those same installed Local limits before
admitting the Host Environment. The retained Project Source preparation must
belong to the same runtime and remain current. This is a managed service
ceiling, not physical backing, Account/egress/Model authority or a cleanup ACK.
An explicit valid Host lookup policy takes precedence; an explicit invalid or
refused policy must not become the omitted-default case. Generic, unselected
and Mock-only paths retain unresolved absence and Common's `MissingPolicy`
refusal when no actual lookup policy was configured. The selected Local ceiling
uses one attempt per request and the declared file, page, byte and duration
limits; historical network-field names do not issue a network plan or retry.

Partial initialization retains the same admission even when no Run view was
returned. If Resource proves that neither the imported child nor its origin
published a Ledger, cleanup reports a distinct unpublished-initialization
outcome to the original Root, never fabricated zero usage. If a Ledger exists,
cleanup preserves its actual usage, parked state, delegated resources,
reservations, holdings, uncertain transfers and pending report. Logical stop
cannot settle those obligations prematurely. Unknown stays with the original
carrier; neither a retry nor process/Promise completion issues a replacement.

If a separately supplied read purpose needs the first bootstrap on that same
Run, Resource retains the reservation inside the already owned admission
before post-reservation currentness or Scope construction. The reservation is
one-shot and must precede every ordinary child, including spent zero-byte
identities. A failed Scope constructor leaves that exact token reachable via
admission cleanup; an installed census still requires all of its original
children to retire before bootstrap settlement. This does not relax the park
fence, clear uncertain usage, reset serials or acknowledge external backing.
The admission's resident optional reference and attempt latch, bootstrap,
census and constructor overlap belong to the selected phase even when absent.

A local no-I/O OriginalMock Model purpose is a separate fixed Root selection,
not a conversion of the Source/Compute purpose. Its Resource admission retains
that distinction even when the actual imported Ledger ABI and limits match.
The Host retains the original admission before starting the one Run, verifies
the exact prepared Program, request, compiled Run, Definition and infer graph,
and installs the existing Model read Scope with the first retained bootstrap
before Source children. Failed Scope construction or post-current checks stay
under the same admission cleanup; they cannot issue a replacement Run or late
census. Neither this binding nor its opaque returned Scope supplies the actual
Model service, a generic/async Provider, permission, or an allocation-success
guarantee. Missing separately selected Root supply remains unavailable without
falling back to Source/Compute ports.
Reserving these bytes supplies neither a missing operational purpose nor
Model or Account authority. The Host's normal Run retirement uses the same
admission cleanup rather than separately stopping around this retained duty.

After the original Model read has handed off, a producer on the same Run may
complete its reserved input into an independently retained output. Publication
currentness recognizes that Resource-recorded completion only on the same
reservation and its still-live original inventory holding (or a completed empty
output). The original bootstrap, read token, other input holdings and delegation
snapshots remain exact. Initial read admission and durable snapshot comparison
do not accept a changed snapshot. Observing completed output neither refunds
pending producer scratch nor acknowledges its separate physical cleanup; park,
stop, foreign owners and retired output still refuse publication use.

An owning consumer may read each original reservation's current retained and
execution amounts without mutating the shared Ledger or invoking currentness.
Foreign Ledger/token pairs refuse even after settlement. A closed reservation
reports no reserved bytes, but separate holdings, escaped aliases and physical
ACKs remain independent; attempt and wire history are not inferred from this
read. The consumer's own finite inventory and original purpose still govern
its admission, rather than treating aggregate shared-Run usage as its budget.

Original file handles and distinct response ArrayBuffers keep their physical
supplier and cleanup duties. Logical Run stop, Source retirement or a sibling
ACK does not acknowledge their release, and escaped bytes remain charged.
Host/Journal/Store initialization, external SQLite or other engines, Model,
Effect, signing, Result/Content publication and transport require their own
actual scopes and authority; the selected Source/managed-Compute admission does
not fund them implicitly.

The Journal's selected facility must precede the first covered Host-format or
Journal filesystem operation, not merely database construction. It retains the
same Host, installation, generation, principal and original paths. Database
wrappers and their original close/native-open-state observations are retained
before fallible open, including isolated inspection copies. Copy/source FDs are
not retired before the database's own close is confirmed. Cleanup retries are
close-only, retain first/latest diagnostics and observe an existing synchronous
close flight rather than reentering it.

Selected primary, observation and isolated-copy constructors receive closed
null-prototype internal option packets; native property lookup must not acquire
inherited callbacks. Selected Journal and copy path canonicalization uses the
captured `realpathSync.native` operation, whose identity and descriptor are part
of the original facility's currentness checks. This avoids the ordinary JS
symlink walk's intermediate path and Map/Set history, not its separate libc,
libuv, managed result, allocator or stack obligations. The same native operation
and option packets issue no admission or physical ACK; unselected paths retain
their existing constructor and canonicalization behavior.

An optional private Journal database-byte ceiling is an implementation support
bound, not admission or a new format rule. It bounds original DB/WAL extent
before copy/inspection and the same connection's main database growth before
schema work. Unselected callers retain their existing behavior. That ceiling
does not bound native heap, aggregate WAL growth, other connections or shared
library state; those remain separate terms in the selected facility's complete
simultaneous disposition. Unsupported originals are refused without reclassifying
valid input as a language error, and no cleanup observation supplies authority.

The selected request-Journal connection also has finite lifetime compilation
and execution support conditions. Original SQL preparation, execution, UTF8
measurement and statement methods are captured with their receivers. Native
failures and refused attempts do not refill those counters. Positional scalar
operand count and extent are checked before native binding. These conditions
are not a heap reservation or permission and leave unselected callers unchanged.

For a selected connection, exact `ROLLBACK` of its already-active transaction
remains cleanup rather than new admitted SQL work. It uses the same captured
native receiver without spending or refilling work/currentness credit; the
synchronous reentry and pending-cursor fences still apply. An actual native
rollback failure and transaction-state uncertainty remain failures under the
existing transaction Owner. `BEGIN`, `COMMIT`, other SQL and a rollback without
an active transaction retain their ordinary work/currentness admission.

When those execution support conditions are selected, the same connection
latches a synchronous prepare/execute call before invoking its original
currentness or native callbacks. Reentry cannot begin another SQL call inside
that original operation. A current boundary outside an active SQL call is not
retroactively classified as native overlap. Settling the synchronous latch on
return or failure is not a database, allocator or physical-close ACK: an
unresolved original cursor still blocks new SQL and stays under database-close
custody. This connection-local support condition supplies no capacity or new
process-wide lock.

Selected metadata reads use the original SQLite iterator instead of native
`All()`'s complete result vector. They retain at most the supported row count
and one lookahead row. Statements and unresolved cursors remain under the same
actual connection; a failed cursor close prevents new SQL and cannot retire
its original. Only the database's confirmed close can finalize that remaining
native custody. Isolated cold inspection applies the same conditions and keeps
its native statements alongside the original copy/FD cleanup carrier. The
read-only inspection connection and subsequent writable connection are separate
sequential originals, not a refill of one live connection or two whole-process
allowances. Native single-row conversion, schema/connection/cache/transaction
workspace and the optional observation connection still require their complete
selected facility coverage before acquisition.

A conditional native result estimate may use the same fixed authored SQL's
output lists, exact admitted own-schema wildcard expansion and selected pragma
definitions. It must not extrapolate a measured result width to future queries
or confuse a representation ceiling with that narrower source argument. The
original SQL/schema and receiving graph remain dependencies of the estimate;
changing them requires renewed correspondence. Neither estimate selects a
public column limit or supplies allocator, managed-result or physical capacity.

The physical request-Journal Owner also observes custody for its own actual
factory results. This private nominal observation separates logical Journal
closure from the confirmed native database close and records whether the
separate observation connection was attempted and whether that same secondary
connection's original close has completed. Its historical attempted flag is
never reset by cleanup. A copied Journal, a caller's
Boolean or a successful semantic transaction cannot provide this observation.
It issues no capacity or authority and does not certify the optional observation
connection from the primary connection's close. The secondary wrapper and its
close/native-open-state operations are retained before fallible open, so a
partially opened secondary connection follows the same close-only duty.

The selected Root captures the actual Journal constructor and nominal custody
observer from its delivered Host namespace. It retains a returned Journal and
its original close operation before any post-constructor current check. A
refusal at that check therefore keeps the same native child reachable through
the existing cleanup carrier. Constructor failures retain their original
cleanup handle and captured status/retry receiver; cleanup cannot issue a
replacement Journal. A close flight is published before callbacks, and only an
explicit original pending-false observation can retire that constructor duty.
The complete separate Journal disposition must precede this preparation: the
captured namespace operations and initial-control or Source recipe are not its
issuer. Primary native close cannot settle a separately attempted observation
connection; Root retirement additionally requires that child's own confirmed
native close and never releases process-lived module/native backing.

When the selected Journal recipe relies on the existing Publication Store's
physical exclusion, that exclusion is acquired after Host-format admission and
before the Journal's native constructor. It does not fund the earlier format
work: the separate complete operational facility already precedes that work.
The Root publishes one opening flight, retains the returned prepared ownership
before the next current check, and waits for the same flight during cleanup.
A refusal after acquisition cannot discard the owner or start another Journal.

The Root forwards that same nominal prepared original once through its captured
private adapter and Host receiver to the existing Store factory's prepared
argument. It does not reconstruct ownership from paths or tokens, issue another
owner, or supply Store/key/payload authority. Ordinary unselected writable Hosts
also acquire this existing Store exclusion before opening their same-root
Journal, then pass that exact original to Store adoption. Moving this custody
does not select an operational resource recipe for those callers. Fresh-prefix handling remains
limited to the same prepared original; global unknown-format refusal remains.

Journal and Store cleanup attempts remain independent. Store payload cleanup
does not release shared exclusion while the same Journal's primary, secondary
or constructor cleanup is unresolved. Conversely, Journal close cannot certify
the adopted Store's payload cleanup. Only both original physical duties allow
the existing Store owner to release its token. Captured dependency observations
must explicitly return an own-data pending-false result; replacement callbacks,
exceptions or ambiguous observations cannot settle it. Cleanup retries retain
the same owner and cannot disturb a successor after its original staged release.

Every prepared selected Host defers Publication services, including an ordinary
Host with no selected Source profile. Connection negotiation uses its existing
Journal; it does not construct a Publication Store or acquire an evidence key.
The first validated and currently authorized non-connect request enters the same
single-flight initializer. Its missing Publication preparation still refuses
before key or Store work; Journal preparation is not payload funding. A Source
lineage callback or private Source symbol is present only for a Source-selected
installation. Unprepared Hosts retain their existing eager initialization.
Shutdown waits for any original initialization flight and retains its sticky
failure and cleanup before closing the same Journal and shared exclusion.

A failed Store constructor can retain a cleanup child whose ownership release
depends on the acquired Journal. For that same pre-service constructor failure,
Host initialization drains the original Journal independently of the dependent
child. It does not wait for that child before attempting Journal close, release
the exclusion early, or reopen initialization. Other initialization cleanup
ordering remains unchanged. Host Journal close remains retryable until both
primary and optional secondary native connections have acknowledged close.
An optional database-extent selection is applied and checked separately on each
connection; one Pager's limit does not constrain another Pager or fund native
heap, WAL, external writers or retained output.

The same selected Journal can additionally impose a finite writable WAL-frame
lifetime. This is a support boundary, not physical storage, mapped-memory or
native-heap backing. The primary and optional observation connection share one
counter under that Journal; opening the latter does not issue another allowance.
Before cold native acquisition it retains a conservative frame allowance for
the bounded original DB/WAL source. The actual native page geometry then selects
the same bounded page-number set for both connections. Before native writable SQL,
the counter consumes a conservative transaction allowance for dirty pages,
possible final commit repetition and FULL-sync sector padding. Batch SQL counts
every semicolon plus its final statement, deliberately overestimating literal,
comment and trigger-body separators rather than introducing another SQL parser.
Only this Owner's fixed prepared metadata SQL reaches these private connections;
they register no application SQL functions, extensions or writable virtual tables.
A leading [`SELECT`](https://www.sqlite.org/lang_select.html) therefore retains
all SQL/input/current/cursor limits but
does not consume writable WAL history. This is not a general SQL authorization
classifier or an exemption for caller SQL. Unknown statements and PRAGMAs keep
the conservative writer debit. Before admitting more writable work, its check
also leaves one original terminal COMMIT allowance; that check itself neither
spends nor refunds it. COMMIT consumes the existing terminal allowance.
Failed attempts, rollback, checkpoint and one child's close never refill it.
Refusal leaves the original connection and its independent cleanup reachable.
This condition depends on the same original cooperative writer exclusion; it
does not constrain arbitrary external writers. The actual facility must cover
the full selected frame, index-region, array-growth and failure lifetime before
work. A frame count, support counter or successful close cannot issue that
facility or acknowledge process-lived native backing.

For its execution-bounded SQLite recipe, each original connection selects
connection-local memory temporary storage before the Journal's schema/control
statements, including the schema-loading `max_page_count` pragma. The observed
page geometry configures the same non-refilling WAL counter first; subsequent
temporary and extent operations retain their conservative charges. The pinned
`TEMP_STORE=1` compile choice and effective `temp_store`
selection are both checked; unsupported or ineffective selection refuses with
the acquired original connection still owned by its existing cleanup. An
unselected connection keeps its prior temporary-storage behavior. The selected
own-DDL cold inspection applies the same checked selection to its original
read-only isolated-copy connection before schema queries. It retains that
connection's captured operations and cleanup through failed configuration;
read-only source custody is unchanged. This selection
removes the transient-file branch from this recipe, not its native allocations:
the fixed CHECK-IN index still has a distinct Btree, Pager, cache, cursor and
KeyInfo lifetime beside the main database. Its native requests and allocator
classes, old/new growth, failure custody and managed aliases remain in the same
complete disposition before acquisition. Selecting memory or reading a PRAGMA
is not heap backing, an operational issuer or a release acknowledgement.

That disposition includes the actual selected SQLite allocator's necessary
zone/class/control metadata. It binds the same selected runtime and facility,
installation and generation before covered work; a default-zone probe, CPU
count, scalar limit or unused Buffer does not identify or back that original.
The shared allocator controls and escaped native/module state are retained
once for their process lifetime, not refilled by a connection or Host close.
This is the finite Journal facility, not a universal allocator lease or another
business, Model or Effect allowance.

Its supported request/history envelope is distinct from backed numerical
capacity. A demand sum over separate original allocations can exceed the size
of any single native request; the private request vector retains that sum as
exact BigInt demand, not as a reserved heap or a successful allocation. Native
request and SQLite representation bounds still apply to their individual
operations. The actual same-startup service must cover the complete selected
co-phase before use, including allocator controls and failed attempts; request
arithmetic does not issue that service. Allocation failure retains the same
original cleanup, and neither failure nor close refills process-lived terms.

The ordinary prefix retains a separate fixed Journal service recipe before
loading the SQLite builtin or Host namespace. The recipe selects the existing
database/source extent, live prepared-statement/SQL text, per-call parameter/result,
schema and WAL support bounds together. It retains the same shared control
declaration by reference; it does not duplicate that declaration's heap or
native amounts. Recipe retention alone does not issue the operational service.
The actual prefix must still bind the complete co-phase and original facility
before native acquisition.

Within the selected synchronous Journal connection, exact immutable SQL reuses
the same captured bounded statement original. Before preparing another original,
its live statement count and retained SQL extent must fit the selected envelope.
A native call that returns no original creates no logical retained entry; a
returned original remains held through later wrapper validation failure. Reuse
neither acquires another statement nor returns credit. Each execution rebinds
its actual parameters and retains the current, cursor, WAL and per-call limits.
The same connection keeps its native originals until real close, then retires
their managed aliases and refuses further use. No completed execution consumes
a later request's lifetime allowance.

The private service original is retained by the selected prefix before its
builtin acquisition, then bound to the returned actual SQLite constructor and
method chain, original filesystem/crypto modules and checked Host namespace.
The native operation descriptors are captured before namespace initialization;
the namespace's later baseline cannot replace these earlier method originals.
Its temporary-directory function and bounded original environment are captured
before namespace callbacks. The same retained directory is used by image load
and cold inspection. A detected service-original change retires it permanently;
restoring a property cannot issue another service. The original process/module
terms remain retained after the Host's native children acknowledge close.

One nominal Host installation/generation may claim this original before its
first subject/root-format operation. Its fixed argument selection captures that
same entry's current callback. The cold native/copy phase must acknowledge its
original physical cleanup before the writable phase; retained decoded records
and process-lived terms remain beside both phases. Primary and observation
connections sum within the writable phase. The service covers its selected
stock native request/realloc/cache/control implementation and catchable refusal,
without converting request demand into reserved capacity or promising that all
maxima allocate together. Store payload, Result, Source, Compute and other
business purposes still require their respective original admissions.

Its argument selector preserves the Host's original update control and the
Root's current callback, nominal directory inspector and retained temporary
directory. Caller-provided limits, accessor/Proxy packets and caller clock
closures cannot replace this fixed selection. The selected service uses the
Journal's ordinary clock defaults; unselected private diagnostic clock behavior
is unchanged. The same arguments apply the bounded own-DDL cold inspection and
each actual writable connection, whose physical cleanup remains independent.

Native wrapper and result-conversion history is separate from simultaneous
live cardinality. The selected bounded cursor includes lookahead, terminal
`next` and one original `return`; each may construct new protocol vectors even
without a returned row. Cover cumulative wrapper, membership, vector/root-entry
and result-backing requests. Retried payload allocations are attempts, not four
successful originals. A client-side free-call upper neither accounts for the
allocator's own cache eviction and metadata allocations nor acknowledges any
region retirement. Those internal histories and shared baseline remain in the
same complete service; they cannot be replaced by the peak live-vector count.

The actual selected public prefix also retains its filesystem/crypto bindings
before Host namespace initialization. The existing Journal facility-current
operation compares those same functions, used filesystem constants, directory
read/close and Hash/Hmac operations with the namespace consumer. A foreign
receipt or accessor is refused without dispatch; a detected operation change
does not revive after restoration. The legacy constructor-pair-only call is
unchanged, while the actual prefix supplies its earlier captured bindings.
These references do not supply native extent, earlier acquisition coverage,
an operational disposition, key/first-init permission or a physical ACK. The
selected filesystem/library branch, native instance custody and complete
simultaneous facility amount remain separate obligations.

The selected Darwin Journal directory path uses an instance-bound native
descriptor, APFS/non-union admission and a fixed kernel attribute buffer, rather
than asking libc to construct a potentially eager directory stream. Entry,
name-byte and work ceilings apply before returning names. The same descriptor
and path identity remain current through enumeration; the existing full-name
snapshot and cold-copy checks consume that private inspector without falling
back after a selected refusal. An unselected Journal retains its existing path.
The native module, loader and all native/managed aliases require their own
pre-use correspondence and complete facility coverage; the inspector's private
membership or bounds do not issue that admission.

The same inspector captures a finite cumulative acquisition allowance before
its first callback. Each accepted invocation consumes one attempt before
currentness or native open, including known refusal and failed construction.
Successful close does not refill it. This bounds construction history as well
as one live enumeration: native wrappers, buffers and returned immutable names
may outlive descriptor close until their separate original lifetimes retire.
Mutating a later limits record cannot increase the captured allowance. These
private recipe conditions do not change unselected Journal or public limits.

Selected Host root-format admission consumes a one-entry view of that same
native module, with its own two-attempt construction history. It does not use
stock `Dir`, enumerate the rest of a directory or decode an unrelated name
merely to establish nonemptiness. The existing fixed marker and legacy-name
probes retain their precedence, without a new full-directory cardinality or
Unicode format rule. The Root binds the original namespace operation and same
Host subject before the call, retains its single flight and partial cleanup
through close, and refuses a second admission or Journal work during that
flight. Unselected format admission keeps its existing path. The original
native 64-KiB buffer, returned first-entry bytes, wrappers, callbacks and marker
FD/work overlap belong to the same complete pre-use facility; the bounded
view and a successful marker write are not that operational supplier.

The selected Store exclusion uses a separate nominal view of that same retained
native module before Journal construction. Its explicit entry/work/history
allowance is included beside the Journal view, not credited twice from one
allowance. Store adoption retains the same cumulative reader rather than
resetting its counters. A whole bounded native scan and its returned names
precede Store's cumulative processed-entry/UTF8 checks; both holdings and this
refusal overlap belong in the original facility envelope. Unselected Store
bootstrap and later independently scoped Store operations are unchanged.

Physical directory close is consumed once before entering the native call.
A failed or uncertain result retains the same original and pending duty; retry
only observes that outcome and never closes a possibly reused numeric FD.
Neither JavaScript alias retirement nor native finalization supplies a close
acknowledgement. The loaded module and shared allocator/library domains remain
charged for their actual lifetimes after a successful child close.

Fixed Journal marker descriptors also consume their captured numeric-FD close
once. A thrown or ambiguous result retains its original Unknown observation;
cleanup retry does not close the same integer again, which may now belong to
another descriptor. This differs from a retained object with an explicit
retryable close protocol. A successful marker close and the original marker
classification remain unchanged; restoration or EBADF is not an Unknown ACK.
The isolated-copy Owner applies the same one-shot rule to its pinned source,
copy writer and schema-reader numeric descriptors. It retains a failed close
and the original inspection cause without touching a reused descriptor on
retry. Its separately retained native database still follows that original
wrapper's retryable close protocol before file/copy retirement.

The private directory image loader keeps native binary facts separate from JS
Source. After independent pre-use module/filesystem coverage, it verifies the
selected package image, creates one nonescaping private copy and retains its
same read descriptor. It closes the only writable descriptor and checks the
copy hash before the ordinary named-image load, then verifies that same inode
and hash before unlinking and closing it. This selected Darwin load does not
disable code-signing or platform policy. No filename or writable descriptor is
published during the load/unlink sequence. Actual startup ownership and the
selected originals remain obligations; matching public DATA cannot supply them.
The temporary directory is an explicit bounded input from that disposition,
not an ambient environment read performed by the loader as its own supplier.
The same Root retains that path before native-image acquisition and passes it
through the original Journal argument selector into isolated format inspection.
The selected Journal refuses a missing or substituted path before ownership or
database acquisition; its copy uses that retained input rather than reacquiring
ambient `TMPDIR`. Unsupported supplied paths refuse without fallback. Unselected
inspection callers keep their existing temporary-directory behavior. The path
alias coexists with the image, Journal, source and copy duties until their
original close observations; alias retirement is not physical backing or ACK.

The same startup also captures the asynchronous filesystem operations used by
the prepared Store exclusion, separately from synchronous Journal filesystem
operations. The fixed namespace checks those same originals before subject or
ownership acquisition. A detected replacement does not revive on restoration;
the correspondence table itself grants neither a facility nor authority.
The selected Node SQLite iterator entry also reads the global `Iterator` and
its `prototype` before returning a native cursor. The prefix captures that
own-DATA constructor/prototype pair without invoking accessors or Proxy traps;
the namespace compares the same originals and their descriptors before selected
native use. A later getter or substituted pair refuses without invoking it,
and restoration cannot revive detected invalidation. No global property is
frozen by this check. The retained descriptors, constructor/prototype aliases
and currentness records share the original module/Host lifetime; they are not
additional capacity, a proof of arbitrary earlier runtime history, or a physical
ACK. Returned cursors remain under their original connection's cleanup duty.
Selected ownership retirement reads its original token through the bounded
metadata reader, never an unrestricted `readFile`. That reader captures the
original FileHandle close and receiver before stat/read callbacks. A failed
reader remains with the same ownership through its captured cleanup; no new
read or owner removal precedes that original FD acknowledgement. This duty is
distinct from Journal close, Store payload close and exclusion retirement.

The loader keeps the original native instance, captured operations and runtime
current fence. Detected loader replacement does not revive after restoration.
An initialization attempt, including a failure after native entry, is never
replaced by another load. Partial file cleanup retains its own one-shot close
outcomes independently of the process-lived loaded image and native allocator
domain. Importing the loader control module does not acquire native bytes or
issue the missing complete operational disposition.

Journal calls have no historical issuance or session-work ceiling. Each new
operation checks the same installed original before argument work, and its
actual input, SQL text, aggregate operand bytes and returned rows remain bounded
at their consumers. Validation failure consumes no future request's allowance.
The original receiver and method are captured from the authored Journal record;
asynchronous admission remains asynchronous. Close and observation-close remain
available without a work credit or currentness check.

The delivered method record remains a nominal member of the original Journal
custody observer; copying it is not independent custody. Its forwarding closures
and escaped method aliases coexist for their real lifetimes. Distinct returned
native statements and their SQL count against the live connection's retained
statement/text envelope until actual connection close. A transient exec string
is bounded per call, not accumulated as retained history. A native prepare that
returns no statement creates no logical retained statement entry; this does not
claim that native allocator backing has been freed. Returned native originals
remain retained even if later wrapper validation fails. Only confirmed native
close permits alias retirement, after which the wrapper cannot admit new work.

These logical controls do not fund native or managed backing, create permission,
or reset shared allocation domains. The selected opaque Host service still owns
its independent physical obligations. In particular, the existing conservative
WAL support counter remains a distinct unresolved lifetime restriction: database
page limits do not bound live WAL/SHM extent, and no checkpoint/truncate witness
currently permits safe replacement by a live-extent budget. Removing ordinary
call counters does not silently remove or refill that physical-support envelope.

Selected cold inspection may additionally bound the SQLite schema table's
declared row payload and traversal before native SQLite opens the isolated
copy. The resource reader follows table-btree pages and the same last valid
committed WAL prefix; an uncommitted or invalid-checksum trailer cannot hide
an earlier schema. It streams bounded buffers and a bounded frame index rather
than materializing schema SQL or a complete file. The same copy Owner retains
its read descriptors through this inspection and original cleanup. This is a
backend preparation support condition, not a new Journal format, SQL decoder,
physical capacity issuer or semantic admission. SQLite still performs format
and SQL checking; native schema construction and all other facility terms must
remain in the complete phase disposition.

A selected finite native recipe may additionally support only byte-exact DDL
programs already belonging to its original Journal implementation. The same
bounded binary resource reader can extract that record field, including bounded
overflow pages and the committed WAL overlay, without interpreting SQL. Native
automatic-index entries with no SQL introduce no additional program. An extra
view, alternate spelling or unsupported schema stays backend Unavailable before
native schema expansion; it is not declared invalid in the language or in an
unselected Journal. The original native SQLite checks still follow. Support
DATA narrows the selected recipe and never issues capacity or custody. Its
original allowlist Strings, bounded record backings, overflow buffer and all
FD/current/cleanup overlap belong in that same complete phase.

For this selected own-DDL path, the same copied schema records also identify
the saved table and index root pages, including automatic indexes with NULL
SQL. A bounded binary walk follows those Btree pages through the same committed
WAL view and checks declared cell payload lengths before native open. It does
not allocate or decode row values. This is necessary because a native large
column cache may allocate from the declared length before a later overflow
read discovers corruption; a file-size check at that later read is not an
earlier allocation bound. The existing source-byte ceiling bounds the selected
record declarations. An unsupported declaration refuses preparation rather
than changing SQLite's format or SQL semantics. Unselected inspection remains
unchanged. The additional root/worklist array, visited-page set, bounded page
reads and retained copy/source duties coexist with the schema buffers and WAL
index in the complete facility phase; this preflight issues no backing or ACK.

Installation-time Mock answer documents are bounded Host-preparation
definitions, not Model execution capacity. The selected control recipe includes
the additional original Task reread and answer document for each selected Task,
their UTF8/read/parse/checked-value/normalization work and retained definition,
typed Provider, clock and callback aliases. These extra originals are declared
before the selected images and acquisition; they do not reuse the earlier Task
wire allowance. The same Host/runtime/current predicate and original preparation
lifetime apply through partial failure and escaped aliases. Creating a typed
mock Provider does not fund its requests, Entry, quantity, output, invocation or
transport; those remain separately admitted Model duties.

### Values compilation component reuse

A single source-free Values compilation constructs its checked graph, AoA
identity, fragment, bound template and executable Plan once. Private compiler
parts retain the original checked Program together with those typed immutable
components; subsequent assembly consumes them without serializing and admitting
the same component again. Standalone public issuers retain their existing
behaviour, bounds and canonical bytes. Compiler-local reuse neither carries
authorization into another operation nor turns equal serialized identities into
the same checked original. The compiled Run still belongs to its original
prepared Program and retains its existing preparation, fact and encoding limits.

### Original pre-admission refusal consumption

The installed finite-candidate callback retains its exact candidate and the
original requested identity from its one request projection. Only its own
captured data method may read the existing same-call managed preparation
refusal, using the callback's original receiver. The read removes that
operation's forwarding alias before consulting the current Host holder.

The submission adapter requires synchronous `true` from that paired method.
An absent, inherited, accessor, foreign or asynchronous projection does not
certify refusal. A retained cleanup duty remains uncertain even if a malformed
port reports success. The original pre-Resource `Unsupported` may enter the
existing Journal refusal path; an exception code alone cannot do so. Anonymous
and named intents retain their existing `not_accepted` and
`preparation_failed` outcomes, current authorization and disclosure checks.
The original preparation-error path and uncertain Journal/dispatch outcomes
remain separate. This does not create a second evaluator, permission or ACK.

### Effect cancellation observation lifetime

One original Effect computation retains one existing Journal cancellation
observer through its target reads and acquired Source continuation. Each probe
still physically selects the complete current row. Only an exactly unchanged
row reuses immutable Run admission; changed, missing or failed reads keep the
existing admission and refusal rules. Revision equality alone is insufficient.
An independent restored target-read continuation obtains its own observer.

The original target-selection checks run before the cancellation probe, and
resume/current gates retain their original positions. This holder retains no
Account decision, dispatch permission or acknowledgement. Pending children keep
their original callbacks through cleanup; no unconditional completion finally
invalidates the same continuation. Journal closure still refuses later probes.
## Standard Source response custody callback

The standard reader supplies one frozen object with exactly one own DATA
method, `retain(response)`. A consumer captures that original method and
receiver before its first await. Omission preserves the legacy path; a Proxy,
accessor, mutable holder or extra own field is refused without invoking it.
`captureSourceResponseCustody` in the existing Host common layer owns this
single consuming grammar, including return validation for all consumers.

The callback receives the exact original response before charge or projection
and must return synchronous Unit. The valid path returns `undefined` without
allocating a Promise. A non-Unit returned value, including an async callback's
Promise of Unit, is joined before refusing a fulfilled result with the
consumer's original protocol error. A rejected borrow instead propagates its
exact original rejection unchanged, retaining any outcome and pending cleanup
carrier; the helper does not inspect or clone it. Consumers await a returned
value only when it is not `undefined`. An original synchronous callback throw
also stays primary. Connector-specific protocol error selection remains with
the consumer's supplied error factory.

This helper performs no I/O, permission, charge, outcome classification or
cleanup. Selecting the callback supplies no capacity or retirement ACK, and
joining an invalid return does not settle its owner's physical duties.

## Installed Effect operation definition DATA

The existing `createInstalledRowEffect` constructor can retain an optional
`managedPlanDefinition` from the same installed provider. For the current Mock
UPDATE and Local files COMMAND profiles, this is a frozen own-DATA object with
exactly `kind`, `memberOperations` and `rowOperations`. Both arrays and their
`{role, operation}` entries are frozen. Mock declares the ordered target-read
and write roles; Local COMMAND declares only its write role. The constructor
retains the original descriptor and rejects proxies, accessors, iterators,
mutable objects and incompatible role order before its first I/O await.
Omission preserves the existing constructor contract for other profiles.

These names select declared operation roles, not a physical-call census,
capacity, a grant or an admitted plan. The existing Mapping, Command, driver,
Site, collection issuer and Source preparations remain their same originals.
A cached before/version observation can be reused only under its existing
exact-description/current rules; the descriptor never authorizes a new read,
replaces the captured observation or supplies evidence of a physical stop.

The standard service owns `prepareManagedPlan`, full retained capture and
material inventory, framework phase occurrences, initial admission, the same
Run parent and later current/cleanup boundaries. It must bind this DATA to the
actual checked member and installation before selecting its typed extents.
Missing complete supply is not an empty inventory or permission to use a
Compute-only quote. Preserving previously supported Model and Content callers
requires their original scopes and providers in the same admitted plan.


## Installed JSON Source service originals

The standard installed Host retains one service association between each
original connector installation and its selected runtime. Before opening a
Site, the Source loader supplies that same service object and installation to
the connector. Codec policy DATA and the typed reader representation describe
rejection and construction bounds; they do not admit a Run, authorize a read,
or fund other connector-specific constructor graphs.

The common Credential reader borrows the original Site's bound credential,
transport, read authorization and current check. Each exact received response
enters the reader's custody before accounting or projection. A pending read,
response alias, provider child or credential binding prevents retirement. A
later cleanup attempt calls only the same captured reader retry method; it
cannot replace a physical close acknowledgement or issue another request.

The generic Row Source exposes its capture representation through the existing
original acquisition and typed provider-capacity association. Managed Run
binding preserves that selection. A planned provider read starts through the
same original Source read and parent Ledger, while Credential authorization
remains independently required. Copied installation DATA, changed runtime
identity, changed policy selection and stale current checks cannot substitute
for any of these originals.


The installed Row Effect retains its implementation's original typed operation
recipe before Request completion/adoption. An optional internal
`requestConstruction.operationIndex` selects one declared per-row occurrence;
it neither derives a slot from a row number nor provides a complete recipe by
itself. The enclosing checked preparation and request must be the same originals
as the selected managed Run. Its native occurrence reservation precedes the
provider constructor, and the existing capture retains the same request child
before awaiting preparation. Constructor-only bounds do not fund metadata,
transport, response, recovery or failed physical children.

Request construction returning does not retire its output. The same capture
keeps the debit while its apply route, refresh, dispatch or original request
aliases can still use it. Original cleanup first closes that route to new work,
waits for active calls to finish, and severs its captured request/current arrays;
only then can the existing child settle its body reservation. Its spent
occurrence/control inventory remains on the original Run until that Run retires.
A forbidden asynchronous constructor remains joined through settlement before
refusal and cleanup; neither Promise settlement nor a numeric quote is a
physical cleanup acknowledgement.

The same implementation recipe can select bounded `credentialOperations` by
the fixed phases `capture-check`, `apply-check`, `resume-check`, `write-check`
and `write`.
Each selects its own declared row operation index; the constructor and other
phases cannot share that index, even when their operation names match. These
descriptors retain original typed extents and rejection bounds, not capacity
or permission inferred from names. Missing complete phase supply refuses.

After adopting the original Request parent, the Host reserves the Plan's
operation-control inventory on that same Ledger before returning the parent
to its variable child consumer. A getter does not start this reservation. A
physical child then reserves its selected occurrence before credential binding,
and the existing capture retains it before preparation. The original Site
issuer receives its unchanged authorization; an invocation's separate `useId`
does not create another grant. CREATE checks, refreshed checks and the claimed
write remain independently authorized operations. The durable dispatch claim
still precedes the write child, and raw response custody precedes projection.

An installed Effect selects the existing Core credential implementation bounds
once on its original initial-material constructor before opening its Site.
The shared Site preserves that immutable selection and refuses caller-supplied
replacement amounts or reentrant selection. It does not borrow a Source reader
or treat its codec bounds as a Run allowance. Each later binding, secret and
failed child still requires its selected operation backing on the same adopted
Plan; consumed grant/binding attempts retain their existing retirement rules.

Transport accounting observes exact outbound body bytes and every consumed
binary response chunk before copying or protocol refusal. A response body
bound and its one-byte refusal window describe a funded read extent, not an
observed transfer. A failed debit, pending socket/binding close or live request
alias prevents settlement. A provider's omitted await cannot detach its
original physical call from the child. Saved recovery needs its actual original
parent and child retainer; a saved recipe or CID cannot select fresh backing or
silently restore the legacy physical route.

A standard capture extent may retain a fixed prefix beside material for each
checked input row. The original Effect Plan resolves those quantities from the
same completed Compute inventory before returning its selected operation
extents. Resolution preserves one member child, no physical attempt and no
transfer; it does not multiply occurrence count or traverse schemas again.
Row-operation slots cannot carry this member template. Fixed extents retain
their original meaning and identity. Zero input rows still need real fixed
constructor backing; overflow or zero backing never supplies a constructor.
The same resolved extent is quoted, borrowed and retired by the original Run.

A managed capture selects its fixed `captureConstruction` member occurrence
before Source export can append proposal rows, expand JSON or derive canonical
CREATE identities. The original Plan reserves that body and the existing
capture retainer holds its same per-member proposal vector. A missing selected
extent refuses before export; no empty capacity or per-row constructor token
substitutes for this enclosing prefix. Native member and row occurrences have
separate coordinates, even when they share an immutable extent or index.
The row limit still bounds exported proposals; member/control children do not
consume row slots. Early failure retains every already-created sibling and
keeps the original input pin until child retirement, including failure before
a Source set exists. Current/capture/route aliases must retire before the same
capacity reservation settles. The installation's full selected extent must
still cover this prefix, its failed construction and simultaneous outputs;
reserving an unqualified numeric bound supplies none of those facts.

The installed native CREATE implementation owns its fixed HTTP/JSON limits.
The Host snapshots that original method and receiver once; it has no parallel
numeric default table. These are codec/transport rejection bounds, never Run
allowances or permission. Native constructor profiles retain original
`ExecutionCapacity` values beside existing `ParseLimits` for optional byte-JSON
input and the returned JSON String. JavaScript forwards the opaque
Option/Array/tuples unchanged to the typed Core adapter. The Core adds the
existing indexed input constructor and literal Host output constructor, without
parsing a Program, granting capacity or reconstructing an ABI tuple.

Those constructor quantities remain separate from original request/response
storage, headers, credentials, failed children and saved-output overlap. A
complete selected physical recipe must fund all of them on the same Plan
before allocation. A nonempty constructor quantity alone never enables an
ordinary physical call or upgrades a provider response into an applied Effect.

The Credential receiver and the Effect response constructor share the original
Node process's HTTP header limit; the physical request explicitly selects that
same value. Initial headers and trailers have separate parser counters and can
coexist with the body. Their raw and normalized forms, duplicate-value join
prefixes and selected header views therefore compose with the body buffer
inventory through the existing representation fold. A body-only extent fails
the same pre-borrow check. This response quantity does not include the separate
request, secret, provider projection or saved/failed holdings and does not
change the existing header or transfer policy.

The standard CREATE declaration can express a read check as fixed `http`
method/path/headers/bounds plus synchronous `body` and Unit `project`
callbacks. These callbacks receive original provider request/response DATA
only; the common adapter owns the scoped HTTP invocation. The legacy
`check.request` callback remains a separate consuming form and cannot be mixed
with that declaration. An invalid async projection remains joined through
settlement, with its original rejection preserved, before the same child can
finish. A body or projection supplies no grant, current decision or ACK.

For an existing metadata GET, `body` may return `undefined` to preserve the
original request without an entity body. An empty String is a different HTTP
shape and is not substituted. POST still requires its declared String body;
invalid asynchronous results remain joined and refused. The existing HTTP
method owner continues to determine the supported method set.

Sheets append uses that declaration for its original spreadsheet/grid metadata
check. The fixed request description and pure target projection are shared with
publication's existing physical check, so the Plan can retain the actual HTTP
bounds without hiding I/O inside a provider callback. Native codec construction,
Host parsing, physical response and failed-child holdings still need their
separate same-parent backing before invocation.

An optional fixed `check.beforeSend` additionally requires a distinct
`write-check` occurrence. The constructor captures the original check method
and receiver and refuses missing/incompatible recipe supply. Inside the same
durable dispatch, the Host obtains a fresh acquisition decision and its own
original read grant, awaits that retained read child, then selects the separate
write child. The commit decision never authorizes the read. A rejected read
leaves the original claim in place without a mutation response or settlement;
it cannot authorize resend or manufacture a terminal failure. Kintone supplies
only the exact original App request and complete Form correspondence, keeping
its native request/Mapping distinct from permission and physical custody.

The captured CREATE frame retains the original bounded Common `changesWire`
beside its mapped value and canonical occurrence. The existing Core CREATE
inventory consumes that same wire, rather than re-encoding a decoded JavaScript
Number. A pure standard mapper may consume this `proposalWire` DATA; other
request callback contexts keep their absent form. Shared read body/projection
callbacks receive the same independently retained mapped value, never another
read grant or an input inferred from the physical request body.

An installed standard implementation can supply its original native constructor
profile to the existing Host recipe composition. The Host combines that opaque
profile with the selected HTTP declaration, actual Credential codec and secret
policy, and original Ledger constructor bounds. None of these immutable DATA
projections issues a grant, samples grant time or substitutes a transfer/disk
quota for constructor backing. Capture, request construction, physical reads,
physical write and pre-body controls retain distinct original lifetimes. A
secret-size check after resolution does not fund the resolver's earlier or
failed construction; that producer must already have its own actual backing.

Managed Sheets initialization captures the original configuration methods
before its first awaited read. Its CA remains the exact original byte object
from the initializer's observed-FD reader, without text conversion or a secret
byte ceiling. The same context prepares the authored declaration and Mappings;
the returned Environment and complete immutable Mapping array pass unchanged
through the original Site service into the common Effect constructor. Missing
initialized readers or constructors refuse rather than select raw-file,
standalone declaration or another Environment preparation. Physical publication
and unfinished reader/constructor migrations keep their separate obligations. The registered
Sheets loaders require that original initializer, configuration reader and Site
service. They have no unmanaged readPages, standalone Environment or copied
Site-close fallback. The separate operator publication entry retains its own
existing authorization and cleanup contract; it is not another registered
runtime loading route.

The Sheets append constructor uses the same closed literal document/cell
builders as its actual mapper. Its immutable schema and the original Host input
bound select native parser/index, scalar arrays, supplied-width closed-object
maps, literal forest, both String builders and pre-refusal UTF8 buffers. The
outgoing validator consumes that exact constructed forest; its geometry is not
an arbitrary input-node ceiling. Supplied invalid row width is bounded by the
original input's wire syntax, never by the allowed column count. Sheets uses
preserving byte parsing, so its native quantities own that input directly and
do not add the generic normalizing decoder again. An absent metadata GET body
has no native output; typed None does not create an empty JSON document. Each
present output still adds the original Host literal-JSON constructor. These
quantities do not by themselves prove installation prelude, complete concurrent
request/response/failed-child backing, ordinary execution or physical release.

Managed Sheets grid Source uses the common standard page Reader for its single
bounded POST. Before opening the Site, its native request constructor quantity
is composed once with the original JSON reader quantity; the same opaque
capacity and immutable request-byte bound reach the original Reader factory.
An operation name or an HTTP body limit alone is not that constructor quantity.
Replacing the selected constructor refuses without repeating the quote. The
native quantity shares the actual grid request document builder and owns its
schema decoding, request forest, writers and UTF8 buffers. The existing reader
owns response parsing, projection and row work, so they are not counted again
as another request parser. The grid retains no paging cursor or row-identity
strings; those unused representation dimensions do not constrain cell values.
The grid response selects the preserving Reader quote because its actual
native parser and indexed admission retain exact keys without NFC. The generic
normalizing Reader quote is unchanged. Literal parser construction already
contains its key-map growth peak; the preserving quote replaces only that
component using the same KeyAdmission constructor inventory. Parser frames and
decoder ObjectNext frames retain at most min(nodes, depth) live map owners and
at most nodes entries, including a pending key before refusal. Their depth
checks precede map creation. Completed Source objects retain fields, not those
maps; parsing and indexed admission are sequential, so one such peak covers
both. Source/indexed trees, text, decoder controls, ancestry, buffers and
failed-input backing remain composed independently. This changes neither
implementation bounds nor the admitted Ledger policy and supplies no cleanup
or physical-GC acknowledgement. Indexed object and array populations are
mutually exclusive per Source node: their sum is bounded by the original node
limit. The existing structural inventory is affine in those populations. The
preserving quote therefore uses the componentwise maximum of its all-object
and all-array endpoints for indexed storage and decoder controls/ancestry,
rather than summing two impossible full populations. Text, parser/key-map
peaks and retained inputs remain separate original families. No provider
reservation is settled early; original pending cleanup and the later Compute
reservation keep their existing lifetimes.
The preserving implementation selection is
immutable; missing native support or switching the selected parser recipe
refuses rather than falling back to the generic quote.
All declared cells remain admitted before requested-column projection. Site
authorization, acquisition admission, before-send current checks, response
charging and failed-child retirement remain with their original owners.

The existing Sheets range and clear Catalog projection also retains the full
canonical Command body beside that same Catalog. The shared row Environment
constructor consumes those original bodies together with their referenced
contracts; the installer does not append them later by rehashing a second
Environment. Range and clear keep distinct original contracts and requests.
This projection does not issue a ResourceRef, permission, approval, claim or
physical cleanup acknowledgement.

Initialized range and clear run their existing declaration projection inside
the original Source constructor. The initial parent backs the Source-only base
before its Common restore; the selected native quantity is retained before the
same Command/Catalog builders run. Their fixed document shapes are shared with
the quantity's template geometry, including exact role names and unchanged
identity domains. Original schema/connector text supplies only variable extent,
never a second semantic declaration or caller-chosen allowance. Native parse,
index, canonical-identity workspace, escaped outputs and Host output parsing
remain backed together with prior Source material and failed prefixes. The
shared quantity fold retains each selected native quantity through the same
Source lifetime. Before the closed synchronous Command projection it selects
the full original peak. Only after its canonical wires and plain frozen
outputs have returned, validated and been retained does the same Source
replace that entry with its original retained-output quantity. The final
outer declaration and definition forests, final wire and captured schema/range
text remain charged using the existing Host units. Native parser, NFC and
writer locals do not escape this closed call. Failed, invalid asynchronous or
unproven construction keeps the full original peak. This selection issues no
Resource, current observation, physical-GC acknowledgement or work refund.
The next constructor still crosses the original current/reservation boundary;
only its existing after-unwind reconciliation may reduce the live reservation.

The completed original Command array, full declared Catalog and one Environment
stay associated with that context. The installer forwards them unchanged to
the same Site service and Effect owner. Default empty Mappings are merely the
absent family; copied/nonempty Mappings or copied Commands cannot join another
context. A failed native reservation never enters the provider projection or
reissues its original declaration. Reentry and a second construction refuse;
an invalid native Promise remains held until its actual computation settles,
without turning its later result into an admitted construction. Original Site
close, physical stop, Request admission and managed driver Plan construction
remain distinct obligations.

The native Command quote passes original decoded input lengths to the
normalizer's scratch inventory. Its separately retained NFC outputs use the
same canonical owner's output bound once; expanded output is not normalized
again as a new input. The closed canonical emission calls are synchronous and
do not expose or nest their Writer/cursor. Their completed Catalog, contract,
Command and declaration Strings remain co-held, while the active writer
workspace is counted once beside all retained output families. This is a
logical live-representation bound, not a GC observation or physical ACK. The
Source keeps the returned Command outputs until its own retirement. Other
native construction families keep their existing conservative peak lifetime.

Initialized range and clear also construct their original retained binding
inside that SAME Source initializer, before the Effect adapter is created.
The initializer reserves the provider's configuration/reference/binding peak
before the projection callback and retains it through Source retirement,
including failed construction. Fixed callback/control frames use the existing
trusted Host baseline; variable configuration/schema/target representations
are composed explicitly. Provider methods and their original namespace
receiver are captured before reserve/current can reenter. The Effect adapter
retains the original Site rather than a copied close facade; reference
currentness comes from that Site's original current method.

A native driver capture recipe retains its fixed and per-row constructor
quantities together with an optional effect-name term. The standard recipe
composer forwards the opaque quantities unchanged. After matching the SAME
checked member descriptor, the original Effect demand resolves that term once
from its actual effect ID length; row multiplicity is applied separately from
the original checked Result. No caller supplies a name-length allowance, and
neither term grants attempts, transfers or permission. Generic CREATE recipes
keep their original fixed/per-row form; old native driver profiles receive a
zero effect-name term.

Clear recovery parses the full incoming forests with the original byte/node/
depth guards. It validates marker grammar and reconstructs metadata from the
original binding, then requires canonical equality before normalizing that
metadata. The arbitrary parsed entry remains live, but is not a second
normalized tree. Its reconstructed and normalized trees use their own closed
schema/target/marker geometry, and effect-name growth comes from the original
Unicode inventory. Returned text, prior input forests, writers and failed
prefixes remain independently backed. These quantities do not reconcile an
operation reservation merely because a placeholder preparation returned; the
actual later constructor and its retained aliases keep their original duties.

The native range/clear request profile returns its nominal request quantity
and the actual closed output geometry separately. Core adds the Host literal
projection once, borrowing the native result String. Direct cold recovery uses
the same native quantity plus the same shared literal constructor inventory;
it does not omit that Host projection or retain it twice. Successful output
has the original checked rectangle/scalar cells and immutable target. Clear
accepts only its existing empty value and validated marker, so its successful
output is independent of arbitrary invalid input size. The original input
parser, canonical/Writer and failed-prefix peak remains fully bounded. Output
geometry describes emitted data; it does not replace a product guard, grant
resources or signal physical cleanup. Fixed request controls keep their
existing common envelope, with no new JS closure tariff or work-phase token.

The range/clear Reader's native metadata callback returns only its bounded
checked/refused reply. It retains no parsed sheets tree, Cursor array, ID
vector or opened metadata maps. At most root/sheet/properties/grid maps are
live in the original loop, while all supplied entries, sheet Cursors and IDs
remain bounded by the unchanged total node limit. Grid request projection
retains its schema wire and bounded body/result separately from native schema
parsing and Writer scratch. Those native returned quantities compose with the
existing shared Reader once. The original ResourceRef stays with its Source
initializer; response data is not stop or release evidence. This changes no
Reader mode, current boundary, byte/node guard or cleanup owner.

A completed installation retains its immutable Environment on the SAME
initial Source material while its original Source is held. A paired Command
Effect can retain that exact Environment only with the same original
installation entry, connector/base input and complete final declaration wire.
A matching CID or copied holder is insufficient. Successful initialization,
original Source presence and logical close remain distinct facts; a failed or
closed Source cannot supply this handoff. The same before-use current fence
still runs without an extra Environment workspace, and reentrant loss refuses
rather than reconstructing after selection. Each native declaration and its
completed output quantities remain independently retained. Only the repeated
Environment assembly is omitted, with no new permission, physical ACK or work
refund. Uncompleted native quantities retain their original full peak.

Identical complete Source and Effect Environment wires are admitted once by
the same composer; distinct complete inputs retain their separate admission,
policy and selector checks. The constructor reservation uses the SAME fixed
role-input selection. It does not treat a CID match or another repeated
occurrence as identical construction. Independent connector/Site bindings are
still checked separately, and the Host's base policy is never replaced by a
publication. This reuses immutable DATA, not Account, read or write authority.

The installing Source also reads its protocol assets through that same
original file reader, reserving before the actual FD read and before text
decoding. Its existing native protocol owner quotes the stdlib Json parser,
canonical values/keys, refusal frames and hashing writer before admission.
This uses the original per-body canonical UTF16/node/depth limits and the
separate cumulative canonical UTF8/node writer limits. It does not interpret
escaped byte counts as additional generic value trees or add those trees
again after the native peak. The full native constructor peak remains held
on the original Source through retirement, including reservation/admission
failure. The immutable admitted protocol holder is retained before subsequent
current/reconcile callbacks. No second parser, protocol meaning, quota,
Resource owner, permission or physical acknowledgement is introduced.

Range/clear request payload and target serialization use the existing
preserving canonical codec; their framed request identity hashes the original
UTF8 parts. They do not invoke configuration NFC normalization. The native
request quantity therefore keeps its parser/index, Json/canonical forests,
writer, byte preimages and Host output backing without adding a normalization
constructor that this path never calls. Binding and recovery configuration
identity retain their distinct normalization obligations. This changes no
payload spelling, request identity, refusal guard or installed resource ceiling.

The shared Effect request constructor uses the existing preserving byte-JSON
parser/index inventory, matching data-key Preview admission and the Native
payload codecs. It does not add the distinct normalizing reader's NFC work.
Input String/Bytes, indexed nodes, native provider quantities, failed prefixes
and their original output lifetimes remain co-held. Response decoding keeps
its own declared recipe; no response, grant, transport or recovery allowance
is removed by selecting the request's actual decoder.

Range recovery bounds its configuration-normalization input at the original
callee boundary. Initial entry construction first completes the binding's
bounded preserving canonical wire. Saved range restoration checks its own
original wire-byte guard before NFC, including later identity refusals. The
quantity keeps the larger of those two guarded inputs and all complete
payload/parser/writer forests separately; it does not normalize the escaped
whole Preview forest. Clear recovery retains its separate envelope because
its stored-entry path has no equivalent early wire-byte guard. No refusal
order, field spelling, identity or installed resource ceiling changes.

Captured Effect operation multiplicity selects the SAME checked member Result
endpoints inside the existing work-bounded schema walk. It does not replace
Source/Compute input demand with an output count or re-lower another Program.
An original literal cross-join output guard can bound successful Result rows
even when an upstream Source cardinality is unknown; it neither truncates a
failed join nor proves its input demand. Missing/parameter/unknown facts keep
the original executor fallback. Multiple members remain separate occurrences,
even when they share the same immutable extent or Result owner. The existing
Request reserves the extra fixed endpoint-selection scratch before calling the
Plan constructor, and the Plan uses that same constructor quantity. General
Compute inventories retain their original complete-node scope.

The actual range/clear driver supplies its same immutable Command definition,
constructor descriptor and original native binding profile to the existing
standard Effect Plan composer. It does not supply an independently handwritten
operation table or a second recipe calculator. The existing checked proposal
input bounds apply to per-row request construction; the complete Preview
bounds independently apply to capture/recovery. Native profiles return opaque
typed quantities and parse limits directly through the bridge. The shared Core
fold adds the original fixed and per-row capture peaks once, alongside its
existing request/response/credential/HTTP/control quantities. Request building,
response decoding, saved recovery and failed prefixes remain distinct live
representations. These quotes admit no Run, permission, physical attempt,
release, retry or cleanup acknowledgement, and do not change implementation
limits or original request/marker/identity domains.

An original range/clear request retains its native binding and immutable
projected target. Subsequent CID, recheck and send boundaries use the existing
private original-request association and native binding admission, with current
installation checks kept separately. They do not reparse the same admitted
target before every CID access. A new selector still passes the original native
request constructor's target check. Foreign/copied failure paths retain the
existing target-first diagnostic and cannot acquire original provenance by
passing that diagnostic check. New-selector refusal still precedes value
encoding and clear-marker generation. Within the original private binding,
exact canonical text reuses its admitted immutable DATA; different spellings
retain the previous complete parse/canonical comparison, including accepted
noncanonical equivalents. This does not retain current permission or a physical
read decision.

A range/clear Source uses the same managed Reader for both grid rows and its
single metadata-verified range reference. Metadata GET construction is shared
with the existing Effect metadata check; callback return is not response charge
or physical completion. The original metadata codec sees every declared column
before that same original reference is emitted. The initialized normal entrance
has no parallel `readPages` transport factory.

The reference itself has the installation's lifetime, beyond any individual
Run's Reader. Its original native constructor therefore runs only after the
same Source initializer reserves its separate full peak. The exact returned
reference, declaration, Command and Environment stay retained there, including
failed and invalid asynchronous construction. Per-Run reader construction uses
the maximum of its mutually exclusive grid and metadata callback quantities;
it does not combine two simultaneous full native parses. Source/index, received
response, projected output and failed-child overlap remain in the same common
preserving Reader recipe. Native optional quantities pass unchanged through
the Host; typed Core consumes their Options before composing allowances.

The exact installed Source adapter is returned, not a copied close facade.
Reference currentness uses the original Site's captured synchronous method and
receiver, so requested close denies later reference use while physical cleanup
continues under the existing owners. Source initialization completion still
requires the same retained adapter; no reference or close callback supplies a
new admission, permission or cleanup acknowledgement.

A synchronous request constructor returning a native Promise is invalid, but
its original task stays in the same capture child until settlement. Observation
uses the captured native Promise method before any replaceable public `then`.
If even native observation fails, the unjoined original remains pending in
that child. A foreign thenable cannot supply a retirement acknowledgement by
calling a supplied callback. The same rule applies to invalid asynchronous
current fences and binding-close observations; neither an observation error
nor Promise fulfillment implies a physical close acknowledgement.

Capture failure cleanup has one original child inventory. Its input-pin
callback runs after that inventory has retired, without recursively draining
the same children and Source payloads again. Direct successful-route disposal
still drains them before releasing pins. The retained wrappers' retirement is
monotonic, so a cleanup cursor can advance past their actual retired prefix;
pending or newly appended children still block parent release. Each synchronous
cleanup status projects one observation per owner. A retry's external callbacks
are followed by a new observation, rather than reusing a previous current state.
Each existing child, input and payload wrapper sets its synchronous opening
latch before invoking an original release callback. Reentry during the interval
before the returned Promise is assigned observes pending cleanup and cannot
invoke that callback again. Later calls share the retained flight; a rejected
or false release retains the same original callback/receiver for its real retry.

The Kintone standard CREATE declaration supplies only its fixed endpoint,
native proposal/body admission, Form request/correspondence and native response
classification. It selects the original Mapping resource and captures original
runtime methods with their namespace receiver. Input String units and UTF8 bytes
are checked before encoding into Bytes. No mapped-JS-row JSON encoder is used:
the existing native parser admits exactly the complete `state:present`/`value`
envelope under the same Form and Mapping, with independent input/output bounds.
Its selected one-record body is not a restriction on the Program's row count.
The shared owner retains exact request DATA/CID and its whole saved envelope.
Cold native correspondence consumes that saved proposal wire and complete
physical body through the comparison serializer, without fresh prepare, a new
tag/CID or another provider read. Native protocol success remains DATA; the
original Preview/claim/current/permission and settlement duties remain outside.
This declaration creates no Account, Site, operation reservation or cleanup
owner and cannot stand in for full constructor/Host/secret/failed-child overlap
or the actual initializer and cold parent.

Saved Kintone CREATE restoration re-admits the complete checked value rows
under the same original Mapping/Form and compares the saved physical body
through the original serializer's bounded comparison sink. Only complete byte
correspondence can retain that immutable saved String in the private native
request. It neither emits a replacement physical document nor issues a new
tag, CID, permission or dispatch. The same native serializer serves fresh
emission and saved comparison; a text-equivalent alternate JSON spelling
refuses. Generic encoded-document ownership is unchanged. The caller must
still authenticate its saved description, original row/key/occurrence, selected
Form/Mapping, current scope and exact provider CID. This DATA restoration does
not construct a cold parent, reacquire backing, renew a lifetime or authorize a
send. Parser/cell construction, comparison controls and retained saved inputs
need the caller's complete overlap quotation before normal restoration.

Native Kintone CREATE constructor inventories retain the original Mapping and
Form as borrows. Mapped value construction, complete current Form projection
and acknowledgement/outcome construction are separate components. Each
composes the existing collection, decoder, SHA and writer owners' logical
representation units with the existing execution-capacity arithmetic. Bounds
and returned capacity remain DATA until the same Request Plan reserves them;
there is no connector-specific byte tariff or additional admission.

Form correspondence compares every immutable original field path in place.
It keeps App/revision, complete field count, exact paths, options, calculation
and lookup facts; it makes no detached original or observed path catalogue.
Projection still bounds the whole observed response, including nested metadata
which a CREATE Mapping may later refuse. Response acknowledgement inventory
bounds unknown-field refusal by the possible supplied object width, never by
the two permitted `ids` and `revisions` keys. Wide digit strings keep their
original spelling and request correlation. Missing/foreign originals, invalid
bounds, batch substitution and arithmetic overflow refuse without a fallback.

These synchronous metadata constructors perform no I/O, clock read, read/write
authorization, cancellation acknowledgement or outcome settlement. Received
Bytes stay with the physical child; the shared response decoder accounts its
own parser/index/key-normalization buffers without encoding another input
String or Bytes. Full Host request/response/secret/failed-child controls, saved
custody and simultaneous lifetimes remain required additional components.
Native constructor tests with an explicit initial carrier demonstrate only
their stated same-parent reservation and original projection boundaries, not
complete ordinary installation backing or physical provider acceptance.

## Original Source and Model inputs of an installed Effect Plan

The installed Effect Plan selects each Source from the checked Request
inventory, in occurrence order. Its immutable selection supplies the original
declaration, reader capacity and transport bounds. The Plan constructs and
retains the actual requirement and acquisition once. Execution borrows those
originals; installation order and a second Query preparation cannot replace
them. A base row reader keeps its original acquisition capture, while a
provider reader additionally retains the same installed provider capacity.

The Compute portion retains typed schema demand for both Pure and Effect
purposes. The same original graph and generated sequences determine column
widths and closed row bounds; an Effect purpose does not discard those facts
and substitute the whole general value envelope. Number/Bool and JSON-leaf
proofs remain distinct. Nested or unproved fields keep the existing general
limits, including their independent text and wire checks.

A source-free Effect operation Plan uses the completed Compute Plan's retained
schema inventory for its row multiplicity. It does not traverse those same
schemas again. A captured Source prefix remains outside the Compute tail's
graph offset, so its full original inventory is still required. Operation
attempts, transfer, simultaneous bodies and pending cleanup are added to that
same Plan; smaller proved Compute demand does not refund or omit them.

The Model component in the Plan configuration is the same native provider
used by execution. The existing component may retain its original occurrence
before Source acquisition and bind its physical context once after capture.
Opening before that binding, rebinding after an attempt, or creating a late
replacement provider is unavailable. The original compiled JS holder is
unwrapped only through its existing private control association; its public
fields are not a native compiled Run.

The Request retains the original Model Scope before adoption. The component
borrows its read when Local supplies the actual inputs. Read retirement and
Scope retirement remain separate from transport completion and from each
other. A physical Mock document child closes separately from the Core row
capture, while correspondence between the charged original documents remains
checked across Source occurrences. Failed cleanup keeps the same original
child and cannot reissue the read or refund consumed work.

These identity and lifetime connections do not establish constructor funding.
The installing Request must fund all simultaneous construction, component,
read, output and failed-child backing before allocation, and retain it until
the corresponding original aliases and physical duties have retired.

## Model demand on the original installed Effect Plan

The Node bridge obtains Model/read/bootstrap bounds through the same checked
compiled Run, definition, Infer occurrence and graph. Its Model demand retains
those originals in the existing Core Plan. JavaScript supplies no Model Ledger
vector and cannot convert an ordinary admission into the local Mock purpose.
The selected component handles enter the Plan's provider factory alongside the
unchanged canonical family constructors; later execution must use those same
handles rather than append a replacement after quoting.

The Host retains the same SDK Request, selected Plan and Model demand before
constructing its Scope on the original Request parent. The immutable Plan
projection must match that exact demand. The existing outer Run record retains
the returned Scope before Request completion or adoption can fail; there is no
second Node admission, replacement Root or additional cleanup owner. The
manager captures both Model methods with the original runtime receiver before
construction. Non-Model Requests retain their existing completion path.

The existing complete dispatch or initialization retirement observation reaches
the same Scope's finish port before the preparation-owned Run can retire.
Live reads, a pending finish, or changed originals refuse that transition; a
terminal outcome or settled Promise supplies no physical-cleanup acknowledgement.
After that witness, Host retirement cuts its raw Scope, compiled definition,
graph, selected demand and Plan aliases before returning the original typed
input borrower. Failed adoption retains that Scope in the same outer record;
its original producer/input cleanup, rather than a nonexistent adopted manager
Run, retires the initial parent.

The normal implementation still has to select its actual original Model graph,
component providers and complete initial constructor/read overlap. Neither this
caller nor the Model Plan's numeric requirements select or fund those inputs.
A missing original selection continues to refuse before execution.

## Capturing the installed Source service

Installation-metadata issuer intake captures the supplied Source configuration
reader and its original receiver before the first metadata await. The same
`readText` receives the exact declared issuer-key byte bound; it preserves the
original file owner and pending cleanup carrier. A supplied malformed reader
refuses before metadata work, rather than selecting a separate file read.
Issuer-type validation, original current checks and custody construction remain
inside that same failed-initialization handoff. If they fail after key intake,
the metadata view retires only after the original failed child has acknowledged
cleanup; pending view retirement retains its same retry holder.

Connector loaders capture their four original standard Source methods once,
before the first metadata await. The common snapshot retains each own DATA
function and its original receiver; replacement methods, inherited methods,
accessors and proxies cannot change that selection. Its invoker is bounded to
those same four methods and adds no service call, admission or cleanup owner.

The connector supplies its existing synchronous unavailable error factory or
throw callback. Returned values and Promises, original throws and rejected
cleanup carriers pass through unchanged. The connector still selects its own
explicit legacy entrance when the service is omitted, and keeps its own profile
grammar, limit conversion and error boundaries. The shared snapshot never
chooses a fallback, a numeric policy or physical authority.


## Original ModuleBody preparation mode

The installed Host retains its normalized Boolean output mode in the same
immutable preparation context as the original runtime and publication
environment. The funded caller passes that exact mode to the distinct
ModuleBody constructor together with its existing phase and sequence-contract
admission. Completion remains a separate call after the constructor returns.
Neither an older Body export nor a missing mode supplies a fallback.

A selected funded context is checked before the Source owner allocates a
producer receipt. A missing capability or throwing context lookup cannot
consume producer slots or select raw snapshot preparation. A staged adapter
which cannot construct the selected input retires its actual preparation and
reports unavailability; this does not define a new language restriction or
qualify the remaining frontend construction paths. Original cleanup failures
remain attached to the same producer until their actual retirement.

The installed Request facade preserves the same Source-first manager selected
for the SDK lineage through submitted-intent lookup, funded preparation and
the typed preparation borrow. Each operation checks that original manager
under its own installation purpose and forwards the same original Request.
A selected Source's currentness or preparation refusal cannot switch to a
Compute manager. Compute-only and unselected installations keep their existing
selection behavior; this correspondence creates no parent, allowance or read
authority.

## Kintone proposal constructor quantities

The native Kintone proposal constructor quote includes the complete outer
Common change envelope in addition to the existing mapped CREATE value and
request constructors. The closed-object key-check inventory uses the supplied
node bound, not the two allowed field names, so an unknown or duplicate key
cannot make its failed prefix disappear from the quotation. The two original
cursor lookups, state check and one-record carrier stay explicit.

The same quote co-counts fresh text emission and cold comparison controls.
Cold restoration borrows the saved body, checks its UTF8 bound at both existing
entries, and uses the original comparison sink and complete serializer. It
does not emit a replacement request, issue a tag or renew a lifetime. The
saved String itself remains with the caller's separately backed material.

These are native constructor quantities only. Input parser/index/String/Bytes,
the enclosing capture prefix, Host request and response storage, credentials,
failed children and all retained overlap must be composed and admitted on the
same actual parent before construction. Quote construction also needs its
original backing. A nonempty quantity does not select a Plan, provide a grant,
acknowledge cleanup or enable an ordinary execution path.

## Effect response buffer backing

The observed binary HTTPS receiver retains its copied chunk prefix beside the
concatenated body at successful end. A body bound B permits at most B nonempty
one-byte chunk copies; the original current read is bounded by B+1, including
the byte which causes refusal. Its constructor inventory co-counts those three
byte families, the chunk Buffer headers and the shared Array growth inventory.
It holds that whole envelope through original output retirement rather than
inferring early release from a response Promise or copied body.

Before borrowing or binding a physical occurrence, the shared Effect child
checks the capacity of that same original selected extent against this buffer
inventory. A declared attempt or sufficient transfer amount cannot replace
retained/execution backing. Missing native support or an insufficient extent
refuses before binding, grant consumption or a physical call. This check
creates no new reservation: the existing original Plan and parent own the
later borrow and its retirement.

The buffer inventory is one necessary component, not the complete physical
operation. Native quotation, the request, receiver/control frames, headers,
secret/current/Journal material, provider parsing and saved response envelopes
need their own backing and retained overlap before normal execution. Node's
stream, Buffer-pool, TLS and runtime implementation storage is not measured by
these logical quantities. No receiver check supplies authority or a cleanup
acknowledgement, and no old compiled runtime gains the new native predicates.

The preserving byte-JSON construction inventory belongs to `decode_core`.
Sheets native codecs and the installed Source Reader project the same parser,
active key-map and indexed-admission inventory into their existing constructor
quotes. Objects and arrays share the same node population; their two structural
endpoints bound each coordinate. Parser and decoder maps are sequential and
use one active-depth peak. Original text, Source/index backing, UTF8 checks,
growth and failed-prefix controls remain included. This changes neither input
limits nor the shared byte tariff or Run allowance.

The native range/clear parser uses the preserving Source parser's original
UTF8, duplicate-key, node and depth checks directly. A discarded indexed
Cursor supplies no additional range fact: both index text limits were equal
to the input byte limit, and decoded JSON key/value UTF8 totals cannot exceed
their original encoded spelling. The original limit/byte refusal and native
JSON construction stay in order; codecs which actually use a Cursor retain
indexed admission. The range constructor therefore selects the parser-only
projection of that same inventory.

Range acknowledgement construction follows `classify_append`; clear follows
`classify_clear`. The latter opens at most five maps whose total fields belong
to the one admitted input tree. Reply Cursor materialization remains bounded
by all supplied nodes, including later cardinality refusal. The closed clear
marker projection retains its eight-node, seven-field, depth-two construction
and canonical writer. Only the Native outcome String escapes; input indexes,
maps, reply cursors and failed-prefix paths remain temporary workspace.

Native range capture quotes returned entry/request-array material separately
from its synchronous parser, NFC and canonical-writer work. The two full
recovery input trees can coexist; Source parsing, entry parsing, normalization
and canonical emission use their actual sequential phases. Each phase retains
all original input Strings/encodings and its failed prefix. Metadata generation
uses its closed column/target/coordinate/marker construction, not the complete
Preview forest. Canonical emission checks its original byte bound before
appending output; saved clear first canonicalizes expected metadata before
NFC, while saved range also has its earlier independent wire guard. The same
representation owner takes the coordinate maximum and keeps returned material
separate. This quote does not certify a consumer's actual phase reconciliation,
physical cleanup, or the complete Compute/HTTP/Store Plan.
