# OSS Host authorization behavior

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
Exact crash-recovery mechanics and the trusted fresh-environment marker are
implementation prerequisites; a destroyed store cannot prove that it was never
initialized. No install-time hooks, automatic profile reapplication or key
replacement on decryption failure are implied.

Registering a Connector establishes connectivity, not permission to delete or
otherwise operate through it. The same setup flow may offer explicit grant
selection and write those grants, but registration/authentication alone does
not grant all operations. This preserves convenient one-flow onboarding without
making connection success an authority decision.

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
The exact trusted-config bootstrap mechanism remains to be designed; this draft
does not add an undocumented flag or change existing discovery defaults.

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

Select trusted local configuration bootstrap, concrete config schema,
immediate decision envelope and technical failure mapping before implementation.
All-target scope, explicit exclusion, conflict rejection and no-match deny are
agreed semantics, no longer pending product choices. Initial grants are not
inferred from the convenience examples above: a documented initial profile may
be written once with durable adoption evidence. Specify its exact contents,
trusted freshness detection, store/config recovery protocol and containment
checks before implementation. Do not claim those mechanisms already exist.

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
