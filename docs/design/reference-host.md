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


## Initial Node control and preparation

The selected Node startup may admit bounded original Project, configuration and
Task intake and Host preparation records in its explicitly declared initial
control lifetime. The [execution boundary](../spec/execution.md#initial-node-control-preparation)
owns this scope. It is not confined to fixed preload wrappers, but it is also
not a general V8/RSS lease, a Native arena adopted by JS, or a numerical release
profile. A separate physical lease for each V8 object is not a prerequisite to
initializing this declared trusted control scope.

The first concrete selected recipe consumes one installation generation for the
entire original process lifetime. It supports only the original omitted `open`
input: no caller object, callback graph or key enumeration is acquired. The
real early preload declares its full envelope before loading the generated
inventory, capturing images or initializing the Host namespace. It then matches
the selected Node/V8/OpenSSL/backend and every declared native library identity,
captures the original namespace validator, and admits only the same private
registry's Host, installation, generation, supplier and module lifetime. The
same producer keeps one original empty packet across initialization; repeated
or unsupported entries cannot replenish or reconstruct this admission.

This recipe makes the following finite implementation assumptions explicit;
they are not measured RSS, an OS quota, a normal numerical profile or a theorem
about arbitrary V8 workloads. The actual heap ceiling must fit 5 GiB. Native
runtime/control backing is conservatively declared as 256 MiB plus 16 times the
maximum selected 128 MiB source graph and 64 KiB for each of at most 2048 image
modules. Captured source backing additionally includes the whole graph and
16 KiB per image for small backing/lookahead overlap. A maximum 64 packages and
512 dependency edges bound the retained module/manifest inventory. The selected
managed heap includes decoded Strings, parser/normalizer trees, records,
closures, indices, Promise/error referents and escaped aliases. The separate
preparation encoding disposition retains 48 bounded 65536-byte encodings for
each of 128 Tasks plus configuration and registry. None of these terms is
reduced using a smaller observed source, low current heap usage or GC.

The ordinary installed public import has a separate fixed package-prefix
recipe. It does not broaden the preload selector, pretend to be `--no-lazy`,
or recover earlier application work. Its original public delivery module enters
the existing Host responsibility before the covered SDK/Host image graph and
before acquiring a caller packet. The generated inventory retains distinct
ordinary backend correspondence with `eager: false`; a matching label remains
DATA, not the operational issuer. The actual prefix retains its own runtime,
module, delivery and installed Local references, captured package Sources and
Host namespace, and the same private registry's five preparation originals.

The ordinary recipe retains lazy compilation, tiering and cache overlap for
the bounded selected graph through process and escaped-function lifetime.
Its separate conservative compiler disposition is 64 times the bounded source
graph, replacing rather than adding a second eager compiler or whole VM. The
managed heap, fixed native, module, source, encoding and physical-child terms
remain simultaneously present. Neither this implementation assumption nor a
successful package-image check supplies a general VM lease or business phase.

The initial ordinary caller recipe supports the documented own-DATA local
Mock packet with an installation directory and no opaque callback graph.
Its captured reader snapshots the same input before an initialization await;
the mutable caller alias is cut after synchronous consumption while the
original immutable packet and cleanup duty remain retained. Unknown fields
are not silently discarded. An explicit connected-Local endpoint and Remote
selection retain their existing SDK route without opening an embedded Host.
The fixed selector invokes no getter or Proxy trap and issues no scope. Other
valid but unsupported embedded inputs remain backend Unavailable, not a new
public language restriction or permission to substitute live providers.

The ordinary prefix preserves one process generation, sticky original image
or namespace failures, and child-first retirement. A failed image's original
FD carrier stays reachable without a second read. Scope closure acknowledges
only its original preparation duty after retained children finish; captured
images, compiled/lazy code, native/library domains and escaped aliases keep
their actual lifetimes. Source, Compute, Model, Effect, transport and Result
still require their separate original suppliers. Descriptor/currentness checks
do not prove all loader registration history or authenticate arbitrary earlier
application code; the selected actual prefix and loader responsibility remain
independent of a published property fence.

External physical children are a distinct part of that phase, not resources
issued by the declaration. Actual image, Project and Task readers retain their
same file handles, bounded backing and lookahead through close failure. Journal
classification retains at most 100000 complete names plus one original Dirent;
fixed markers use one original FD and only their exact closed body plus one
byte. Each isolated SQLite inspection pins a combined DB/WAL extent of at most
64 MiB before making any copy; its same source, isolated copy, sequential 64 KiB
buffer and actual SQLite connection coexist until that child's own cleanup.
The whole memory declaration adds that 64 KiB copy buffer and a separate 1 MiB
allowance for simultaneous and retained fixed-marker backing; pinned/copy file
extents remain a distinct physical-storage vector, not reclaimed heap credit.
Larger valid retained state is inspection Unavailable, not corrupt, truncated,
deleted or permission to bypass classification. These work limits do not fund
stored business records or authorize another database, Source or metadata read.
Before selecting Coordinator metadata values, classification admits the known
plain two-column STRICT metadata table from SQLite's schema table. A substituted
view, virtual/generated column, expression or different DDL is refused before
its value query can execute. The closed table spelling tolerates only whitespace
differences between the existing generated and legacy layouts, so the original
legacy observation-history refusal remains separate from schema admission.

The actual preload's private operational closure, not this accounting DATA,
issues the nominal scope. Its persistent native/module/library/image domains
remain charged for the real process and escaped-module lifetime, even after
the Host closes. The existing Host first completes every original physical
child, cuts only its managed preparation aliases, notifies the original retained
record and calls the captured scope close. Only the original `pending:false`
allows final retirement; a false/throwing FD close, replacement callback,
settled Promise or successful sibling cannot supply that acknowledgement.

The actual private bootstrap issues its installation-only nominal admission
before the covered work. It retains the selected startup, source, backend,
recipe and same Host/installation/generation originals. An eight-reference
runtime view, parsed bounds, matching source digest, caller Boolean or Ledger
cannot issue that admission. Earlier imports and Project discovery cannot be
charged retrospectively when a Host is associated later.

The same-phase envelope includes raw read backing and lookahead, concatenation
and strict decoding, retained text and parser cursors, normalization writers,
preimages and hash workspace, original configuration/registry/Task/default
records, indices, arrays, closures and escaped aliases. Selected module images,
runtime internals and libraries remain explicit implementation domains, not
zero-cost constants. A bound on input text alone does not cover these overlaps,
and unselected callbacks or libraries do not inherit coverage.

Preparation material remains with that original lifetime through partial
construction and uncertain cleanup. The existing Host shutdown retains each
original child and its cleanup receiver; successful sibling cleanup cannot
retire another child's duty. An explicit transfer accounts for simultaneous
source and destination responsibility before cutting source aliases. A local
view's retirement or Promise completion is not a physical acknowledgement.

Private consumers authenticate an initial-control scope through the same
preload Owner's nominal current check, not by invoking a method on a supplied
object. That check binds the original Host, installation, generation, supplier
and module lifetime, and rechecks closing after the original current callback.
Copying a scope's methods or constructing another internal state-machine
instance cannot add membership to the selected preload's instance.

The prepared embedded Host obtains its fixed check-environment source through
that same nominal scope and five originals. The private startup projects the
already captured package image; the Host does not reread its pathname or fall
back to current file contents when that projection is unavailable. The original
String remains in its selected module/preparation lifetime, including escaped
aliases; this borrow is neither a new issuer nor a physical release acknowledgement.
Independent Host entries without this preparation retain their own acquisition
obligations and do not inherit the embedded startup admission.

An eager original Host namespace may capture the startup's already-published
immutable CJS forwarders through the same synchronous private receiver. This
avoids a static CJS/ESM require cycle without deferring authentication to entry
code or accepting a later cache-export replacement. It neither creates an
operational original nor covers earlier module loading by itself.

The original Host candidate, empty installation, five-reference snapshot,
existing registry entry and cleanup scaffolding precede begin under the actual
bootstrap lifetime. They are not retrospectively charged to the installation
scope. Project/configuration/Profile/Task body intake and Provider preparation
remain after begin and the fixed nominal current check.

A preparation record is retained before fallible work. Repeating retention of
that same record returns its original duty and may attach its original cleanup
handle once; it cannot replace a pending handle. Managed-reference release is
only a notice that the caller cut its own aliases. Captured cleanup methods and
their original receiver remain held until their own status reports
`pending: false`, independently of retry settlement. The scope closes only
after every preparation duty and the original operational close acknowledge
completion. Concurrent closes share one flight, completed siblings are not
retried, and diagnostics retain the first and latest error records rather than
an unbounded history. Escaped aliases remain the original envelope's duty.

The original supplier may initialize its selected Host module namespace through
one asynchronous flight. Begin snapshots all five original references and
consumes the generation before that initialization; it checks original current
afterward before returning the nominal scope. The caller awaits begin and uses
the fixed Owner validator before importing Common or discovering the Project.
An initialization failure preserves its original cause and cleanup duty; neither
a provisional scope nor Promise settlement substitutes for that duty's ACK.

The ordinary package builder derives a private image inventory from the exact
rewritten adapter outputs, runtime images and selected dependency manifests.
This generated Source is correspondence DATA, not an operational issuer. A
same-FD image read checks its original extent, identity and complete digest,
holds its immutable UTF-8 Source and closes that same descriptor before handing
the Source onward. Close failure retains the original FD and close-only retry;
it cannot return Source, reopen the image or retire a sibling. The temporary
byte backing, decoded String, hash and native decoder workspace overlap. Such
byte custody alone does not establish the complete image loader, installation
admission, current Host or preparation envelope.

For a generated installed image inventory, the selected preload captures each
original Local and resolved dependency package before optional SDK and Host
namespace compilation. Each package's same-FD manifest and image bytes must
match that inventory, while repeated dependency edges must resolve to the same
original package, not an equal copy at another root. Those held Sources feed
the private loader; the same synchronous receiver initializes the Host namespace
and completes its Module handoff before entry. Source-only absence stays absent.
The selected namespace and asset projection remain process/module holdings, not
an operational intake issuer or a Host-level release acknowledgement. Stock
resolver/bootstrap provenance and unselected library domains remain independent.

The owned release-cohort transformation may change only the packaged manifest
and license. The image generator binds the exact source manifest and the exact
manifest produced by that existing transformation before acquisition, including
the selected cohort version. It does not normalize installed JSON or ignore
metadata fields. Local, the public Node facade and their owned cohort dependencies
must all use the same source or release representation; all other image bytes
retain their single original digest. The phase envelope charges the larger of
the two bound manifest extents once before capture. Admitting this representation
does not issue a startup original or extend control admission into business work.

The standard Node facade is a separate image domain, not a dependency of Local.
Its generated facts identify its original public entry and dependencies, with
an explicit edge to the same actual Local installation. When that facade is
selected, the preload captures its Sources and checks that edge before any Host
namespace compilation. Both Local and Node public ESM entries are initialized
from the held Sources before the final Module handoff; later entry imports
reuse those same namespaces. Missing facade coverage refuses that selected
route, without loading an uncovered parent for Local-only delivery. Optional
dependency preparation failure cannot leave a dangling package index in another
image domain. These package facts and namespace identities remain correspondence
DATA, not operational admissions or coverage of caller-owned opaque backing.
The extra Source Strings, manifests, dependency paths, image/namespace records,
graph traversal, compiler and loader workspace overlap the original Host and
library domains. Module-cache retention or a Host close does not release them.

Ancestor public preload wrappers publish their same immutable null-prototype
table before nested loading. A later exports replacement or Node's circular-
require warning prototype cannot stand in for that original receiver. Eager
ESM consumers use the original synchronous CJS receiver rather than creating a
static CJS/ESM import cycle. Private preparation dispatch captures only the actual
Host namespace's operation and receiver; it refuses a missing operational Owner
before touching the raw input or constructing a candidate. Image correspondence
or the presence of that operation alone does not enable dispatch, and only the
existing Client result may escape, never a Scope, issuer or capacity handle.

Each public package's private `initial-control-public-dispatch.cjs` is loaded
by its actual wrapper before child loading. During that native preload only,
it captures the same wrapper's original Client-only function and receiver.
The actual fixed preload argv, `internal/preload` ancestor and same consumer's
selected entry resolution are required together; forged Module/cache parent
records in an unrelated preload cannot enroll a callback.
Ordinary imports return an immutable `undefined` selection without loading a
wrapper or Root. Application-time cache metadata or a caller-supplied table
cannot enroll a later dispatch. The wrapper retains its child function and
receiver once the synchronous child load completes; namespace reentry before
then refuses without observing raw input. Later exports/method replacement
does not change either captured link. This source/module boundary still
requires independent actual startup ownership and non-escape; it does not
turn module metadata into operational admission.

The two wrapper tables/functions, child receiver/function references, private
delivery tables/closures and captured native descriptor/path/module controls
remain in the selected module lifetime. Each call additionally retains its
original kind/raw aliases and argument forwarding workspace. These holdings
and partial child initialization overlap the original startup/preparation
envelope. A frozen table, undefined selection or rejected call supplies no
physical retirement acknowledgement or numerical capacity. Private root-level
implementation files participate in the same ordinary package image inventory
even though they are not public export subpaths.

Selected image loading supplies immutable captured Source to the original Node
compiler rather than delegating the body to a later pathname read. Uncaptured
dependencies and additional query-identified images require their own selected
domain; they cannot inherit this control coverage. Registration through the
published `registerHooks`/`register` fences permanently invalidates this helper,
even after deregistration. This observation does not cover an original native
registration function retained before fence installation: it can install a
short-circuit loader without changing the published property or this helper's
currentness result. That result therefore is not an all-history certificate.
Before operational adoption, the actual selected startup must independently
establish the ownership and non-escape of those original registration functions
and any earlier registrations. This component does not establish that boundary;
without it, operational admission remains unavailable.

The admission must also bind the actual post-load CJS cache/exports, original
stock resolver, fixed asset reads and runtime-file identity to the loaded
runtime. A Source-delivery marker, a stock-function identity check or a matching
cache-shaped object alone does not authenticate those originals. These are
selected implementation obligations, not restrictions on ActQL Programs or
permission for unrelated Node callbacks, libraries or business work.

After synchronous original namespace initialization, the actual preload captures
its CJS/JSON Module records and exports descriptors once, before entry runs.
Currentness checks retain that same record, exports reference and shallow own
descriptor inventory without invoking exported getters. Changed or replaced
records remain refused even if restored. An image not initialized at that
handoff cannot acquire pre-entry provenance by compiling later. Preexisting
bootstrap bodies, nested export referents, stock resolution and fixed asset
reads still need their independent selected-domain correspondence; this cache
handoff alone is neither a complete loader proof nor an operational issuer.

For selected JSON compiler metadata, the preload compares the actual Module's
tree against a separate parse of the same captured Source before sealing its
own records and arrays. Changed values, accessors or substituted alias graphs
refuse before any node is sealed. The held Source identity is unchanged, while
stock JSON BOM handling and primitive values are preserved. This does not
freeze language prototypes, arbitrary CJS exports or application data, and it
does not authenticate nested library state or earlier registration history.
The original Module/tree/Source overlaps the second parse, comparison pairs,
key/descriptor walk, node array, weak membership and native freeze workspace;
sealing or later GC is not physical cleanup, a reservation or funding.

Completed native ESM JSON translation can publish the original two-field
`exports`/`loaded` cache record without a CommonJS `filename`. Only already
Source-delivered JSON may use that exact header, with the same full Source/tree
check, sealing and retained record/exports identity. A matching cache preseed
without delivery remains refused, and CommonJS images still require their
filename-bearing Module. This Node interop distinction does not authenticate
prior cache ownership, nested library state or loader registration history.

The selected preparation path also retains the native `String.prototype.trimEnd`
used between its original environment Source and the existing normalizer.
Replacing that method must not introduce an application callback into this
declared control step. Ordinary unselected imports do not fix that method.
The retained descriptor and method reference, original Source, trimmed result
and normalizer workspace overlap under the same control lifetime. This narrow
implementation fence does not establish coverage for every String operation,
the VM heap or an operational supplier, and Host-view retirement is not native
implementation retirement or physical cleanup.

The original startup publishes its same immutable forwarder table before
synchronous Host namespace initialization can reenter that Module. A missing
captured callback must not be confused with a refusal from the original Owner
merely because both report unavailable. Early table capture neither admits an
installation nor covers initialization work: the original unavailable Owner
remains unavailable until the independent selected operational original exists.

Fixed control assets are projected from that same selected immutable Source
holding through the private nominal installation port. It checks the original
scope, five references and currentness before and after the captured supplier
callback, returning only its original String. It neither rereads a path nor
parses, reconstructs or authenticates new DATA. An unavailable asset stays
unavailable; callers cannot substitute a file, receiver, Promise or matching
digest. Scope retirement does not collect escaped Strings or acknowledge the
separate module/image holding.

The prepared installed Host uses this same projection for its fixed numeric
profile, graph laws, pipeline Registry and AoA contract body before parsing or
checking them. It does not reopen those four pathnames after package capture,
including on an unavailable or current-refused projection. Unprepared Host
entrances retain their independent existing file-acquisition responsibility.
The private preparation method, original String aliases, decoded trees and
canonical encodings overlap the same preparation/image lifetime. Borrowing an
asset does not retire that holding or issue business capacity or authority.

This admission has no conversion to metadata HTTP, Source, Result, business Run,
Model invocation, Content/driver or external-VM capacity or authority. Their
existing Resource suppliers and current authorization remain separate. The
initial trust boundary introduces no Owner, Ledger, queue or scheduler.

The existing installed Host shutdown retains the issuer's original initial
control receiver as its final control duty. It closes that duty only after
dispatch, Checkpoint, journal, Source, Effect, Store, observation and retained
owner-view cleanup have completed. Failed initialization uses the same ordering
and original retry carrier. A successful sibling close cannot release the
initial holding while another child remains uncertain.

The Host captures that same receiver's close operation before its first child
cleanup await, but invokes it only after those children complete. A getter
failure retains the holding under the same cleanup Owner; only a still-unobserved
getter may be retried. A successfully observed callback cannot be replaced
before the first close request or during child cleanup. Only its
explicit `pending: false` observation completes the control duty; a fulfilled
Promise, absent/malformed observation or replacement close function does not.
Final runtime-reference retirement remains behind that confirmed duty. These
cleanup consumers cannot issue an initial admission, establish its coverage,
prove garbage collection or supply business-Run capacity.

Pending initialization retains each original cleanup phase's first and latest
failure, rather than accumulating an unbounded in-memory retry history. This
bounded diagnostic projection neither completes that phase nor changes its
original cause, cleanup receiver or retry authority.

The same installed Host registry retains a preparation candidate under its
actual Host identity before Project discovery. This candidate has no root
lease. Only the selected startup's original module operation can validate its
same Host, installation and generation, original `connectEmbeddedLocal`
function and module lifetime. A namespace, public function, caller callback,
copied record or equal configuration cannot reconstruct this membership.
The startup independently supplies the operational admission; registry
membership is not capacity, authority or coverage of earlier imports.

The Local preparation awaits that admission before snapshotting options,
importing Common or reading Project originals. Its original scope is checked
after awaits and between original file acquisitions and Common admission.
The existing file Owner first closes or retains an acquired FD, so a current
refusal cannot lose it before cleanup custody. Getter failures on a thrown
initialization value likewise remain under the retained cleanup phase.

The selected startup may support an original producer-controlled preparation
packet without making every public option object data-only. Its actual intake
coverage must precede the first raw acquisition, own-key enumeration, spread,
descriptor copy or clone, including refusal and partial-construction workspace.
Frozen shape, a packet label, bounds or an alias count do not prove that
coverage. A general object without it remains unsupported by this selected
supplier, not an invalid public API value; existing unknown-field, type and
duplicate-consent checks and unselected entrances retain their responsibilities.

The private begin port passes the same raw input unobserved to the captured
operational preparation callback synchronously, before namespace initialization
can await. That supplier first retains its original intake responsibility and
then invokes only its original bounded reader. It keeps the same snapshot and
cleanup through initialization and failure. A fixed nominal/current projection
returns that original snapshot after begin; it cannot reconstruct one, adopt a
replacement or infer admission from the preparation Promise's resolved DATA.
Callbacks and opaque handles remain original Owner borrows, not traversed or
cloned closure graphs. Their backing and extended lifetimes, the raw/snapshot
overlap, captured reader and receiver, scope alias and partial-failure holdings
all stay in the same declared envelope. Managed alias retirement is not their
physical cleanup ACK. This port does not itself supply the missing operational
original or a public consumer's earlier intake coverage.

The embedded consumer passes its raw options to this synchronous begin and,
after initialization, reads only that original nominal input projection. It
retains the packet in the same preparation record through Host adoption or
failed initialization; it never rereads the caller as an input fallback. The
private selected namespace exposes a pure bounded snapshot reader so the
actual startup can capture its exact Source, rather than accept an application
callback as the reader. This operation cannot issue the operational admission.

The selected public-entry consumer initially supports omitted `open` input.
It forwards that same `undefined` to the existing candidate's begin exactly
once. The operational supplier, not a public default argument or facade copy,
owns the empty packet's acquisition. The original path observation remains
before initialization awaits, under the independently admitted prior startup
envelope; its result or failure stays with the same preparation record through
partial failure. After nominal/current admission, only that original empty
packet becomes the existing Local mode/owner and project-local state-directory
options. A nonempty replacement packet refuses without dropping its fields.
The returned Client and `info.stateDir` describe that same registry Host and
directory; no second open, candidate, installation or scope is issued. This
finite producer support does not redefine other valid public option objects
as invalid. Their complete before-copy supplier and original semantic
validation remain necessary; unsupported selected inputs are unavailable.

The reader preserves own data fields, enumerability, array holes, primitive
String code units and shared immutable DATA without clamping, normalization or
unknown-field dropping. Existing Owners still validate field meaning. Finite
properties, nodes, depth, individual and aggregate String code units, array
lengths, original-reference occurrences and traversal work are separate input
allowances, not backing-byte amounts or a numerical profile. Explicit traversal
frames, own-key arrays, paths, original and copied records and rejection overlap
remain in the supplier's complete simultaneous envelope. Proxy/accessor/cyclic
DATA without supported acquisition coverage remains unavailable on this
selected path, not an invalid general public option. Original Host handles,
callbacks and non-DATA values retain exact identity for their existing Owners;
neither copying classifications nor original-reference counts authenticate
those Owners, closure backing, current authority or physical retirement.

On adoption, the candidate and root lease use the same registry entry and
actual returned Host. A foreign returned child enters its acquired shutdown
custody before the pair refusal. Reusing an existing Host first retires only
the unused preparation, then rechecks that original entry and its nonclosing
lifetime after the await, before exposing another lease. Pending preparation
cleanup does not close or replace the existing Host.

Project views share one original retirement record. Existing Host cleanup or
an unadopted preparation cuts its managed configuration/registry references;
captured getters and downstream lookups then refuse. This does not rewrite
escaped canonical DATA or acknowledge its physical storage, GC or capacity.
Managed preparation aliases are cut before the same control's close, while
runtime-view retirement remains behind its explicit original completion.

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
