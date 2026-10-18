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
