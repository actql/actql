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
