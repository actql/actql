# Reference Host

Informative implementation guide, not an additional conformance profile.

## Authorization

The agreed [Host authorization design](host-authorization.md) uses execution-account settings and
`allow / deny / delegate`. Local can use one execution account; Cloud can
delegate application-user authorization without registering every user in Core.
Immediate delegation answers need no dummy Checkpoint; deferred answers use the
existing durable continuation. Human approval and application routing belong to
the Host. Conflicting account settings are errors, not a rule-priority system.

Configuration and protocol integration remain specification work. This design
does not claim executable authorization support.
Authorization behavior below is the design target, not the current pinned
contract: the [listed contract changes](host-authorization.md#relationship-to-current-pinned-contracts)
have not yet been applied. This informative guide does not override those contracts.
Encrypted evidence, secure defaults, retention and recovery guarantees remain
unchanged. Follow the linked specification-work matrix before changing any wire or Core.

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
