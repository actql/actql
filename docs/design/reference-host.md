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

Each Host owns its active/closing/closed lifecycle. Independent Hosts and reopen
are supported within the same process, subject to actual directory locks and
resource limits. A shared module/runtime cache does not become a Host child
that must be unloaded before close. A new Host cannot reset a retained Run's
budget, request identity, send state or adoption history.

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

The Host retains the original admission before beginning the Run. A failed
begin keeps that same admission's unpublished or started cleanup, never a
replacement attempt. The source-free dispatcher opens its configured Compute
Host through this opaque Run and rechecks the original Ledger after sequence
preparation. It cannot use the legacy scalar constructor on refusal. Successful
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

This preparation grants no key, Account, Content reference or Result authority.
Private derivation evidence still requires its original purpose-confined key;
a no-key Result Store cannot infer key initialization from a missing file.
The ordinary Host selects its real 32-byte random AEAD key during the existing
Store initialization, without a Mock Account, Reviewer or signer prerequisite.
The same prepared Store Owner must positively establish first initialization.
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
one original Run Ledger. The two Source reads and the generated managed DAG
borrow that same Ledger internally. The existing physical Ledger equality at
capture transfer remains mandatory. Independent Source-only children, equal
limits, copied prepared values or a fresh scalar Ledger cannot replace it.
Currentness and the existing mutable-resource/park fence both apply before
preparation and after callbacks. Account and read/send authority stay separate.

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
the same bounded page-number set for both connections. Before native SQL work,
the counter consumes a conservative transaction allowance for dirty pages,
possible final commit repetition and FULL-sync sector padding. Batch SQL counts
every semicolon plus its final statement, deliberately overestimating literal,
comment and trigger-body separators rather than introducing another SQL parser.
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
database/source extent, SQL compilation, statement/parameter/result, schema,
WAL and operation support counters together. It retains the same shared control
declaration by reference; it does not duplicate that declaration's heap or
native amounts. Recipe retention alone does not issue the operational service.
The actual prefix must still bind the complete co-phase and original facility
before native acquisition.

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

SQL and native-statement counters do not bound an operation that refuses
before reaching SQL, including its validation and any earlier native crypto
work. The selected Journal may therefore additionally impose an original
lifetime operation ceiling before its delivered methods inspect arguments or
invoke currentness. Failed validation or currentness consumes that attempt;
reentrancy, rollback and property replacement cannot refill it. The same
original receiver and method are captured from the authored Journal record.
Its asynchronous admission remains asynchronous. Once exhausted, it retains
and rethrows one refusal original rather than allocating a new error on each
denied call. Close and separate observation-close remain their exact original
operations, available without operation credit or currentness.

The delivered method record remains a nominal member of the original Journal
custody observer; copying it is not independent custody. Its original method
record, forwarding closures/receivers, operation count, retained refusal and
escaped method aliases coexist for their real lifetimes. This support ceiling
does not bound each operation's input/work by itself, fund any native or managed
backing, create permission, or reset shared allocation domains. The full recipe
must combine it with the original per-operation input/cardinality/SQL limits
and physical facility before use. An unselected Journal is unchanged.

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
