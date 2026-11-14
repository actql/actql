# Installed Local Node Host

## Public helper imports

`@actql/local-node/observation` exposes `createHostObservationConnection` and
`observationLimits`, with the existing observation types. Its previously exposed
untyped installation, projection and context implementation helpers are no
longer exported from that public entry. The canonical Host implementation keeps
those helpers and the same nominal connection identity.

`@actql/run-host-core/result-access` retains all five typed service functions:
`installResultAccessAuthority`, `installResultAccessService`,
`deliverAuthorizedResult`, `inspectAuthorizedDeliveryAttempt`, and
`describeAuthorizedResult`. The previously exposed, untyped `ResultAccessError`
constructor is no longer a public import. Existing failures retain their original
class, code, cause and cleanup behavior. Use the typed service entry points;
these public import changes do not replace current authorization or cleanup.

`@actql/node` includes this package in its standard installation. Embedded
`connect({mode: 'local', owner: 'local'})` lazily loads the checked MoonBit
compiler and runtime, and the built-in Local Host adapters.
Connected Remote mode imports only the lightweight SDK path.

Use Node.js 22.16 or later in the 22.x line, or Node.js 24.0 or later
(`^22.16.0 || >=24.0.0`). Local Journals use the native `node:sqlite`
`DatabaseSync.isOpen` and `DatabaseSync.isTransaction` observations, not
substitutes inferred from SQL statements. The transaction observation is
available in [Node.js 22.16](https://nodejs.org/download/release/v22.16.0/docs/api/sqlite.html#databaseistransaction)
and [Node.js 24.0](https://nodejs.org/download/release/v24.0.0/docs/api/sqlite.html#databaseistransaction),
but not Node.js 23. The transport-only `@actql/sdk` does not acquire this
Local SQLite dependency.

Trusted Host bootstrap code can create a complete, process-local installation
table with `createInstalledConnectorTable(entries)` from `@actql/local-node`.
Pass its opaque handle as `installation.connectorTable` to an embedded Client,
or as `connectorTable` to the HTTP Host and `publishSource`/`publishEffect`.
Use the same handle for publication and Host startup. Entries retain the existing
Source/Effect profile schema, registration, revision, provider bundle and lazy
module-loader declarations. Construction snapshots these declarations without
loading modules, resolving secrets or contacting providers.

An explicit table has no implicit built-in fallback; an empty table supports
source-free Values. Duplicate profile versions within one role are rejected.
Different tables may select different implementations of the same profile
schema. Clients sharing an open embedded root must supply the identical table
handle; another handle refuses with `InstalledHostConfigurationMismatch`.
Separate roots can use different tables. Omitting the option preserves the
generated default installation and lazy optional DuckDB behavior.

This table snapshots loader references and metadata, not executable file or
closure contents. It does not issue durable Connector Set identity, retain old
artifact bytes, or activate a Workspace revision. Those require the artifact
and Set lifecycle owners; serializing or copying a handle cannot recreate it.

Each embedded Client holds a private lease on the compatible installed Host.
`await client.close()` seals that Client, disposes its readers, then releases
the lease. Other Clients retain their own leases. The final close stops new
ingress and Checkpoint resumes, waits for existing dispatch and cleanup, and
closes the physical owners using the same shutdown protocol as the HTTP Host.
It preserves durable Runs and retained Checkpoints; it never requests Run
cancellation. New opens are refused while final cleanup is pending. Retrying
the same Client's close continues the original cleanup without reopening
providers. After confirmed release, the same directory can be reopened in the
same process under current installation checks.

Source-free Local Values execution does not install or load DuckDB. DuckDB is
an optional peer dependency. Before explicitly selecting a DuckDB Source or
Compute installation, install the pinned native package in the consuming app:

```sh
npm install @duckdb/node-api@1.5.5-r.4
```

A selected DuckDB installation without that dependency rejects with
`DuckDBDependencyUnavailable`. The Host never installs dependencies at runtime
or falls back to another execution method when the selected provider is missing.

The installed source-free profile accepts supported SQL/Pipe query text and
Effect-free JSON or YAML AQL Programs with Values computation and named
Results. Query composition and Pipe Result taps share the checked Program
owner. It binds the
initial empty captured Artifact set through the shared MoonBit Run owner, durably
records the request, executes the real Local Site, commits formal publication,
and serves Result rows in process. A repeated request ID with the same intent
attaches to the retained Run; changed intent is rejected. A reserved dispatch
is reconciled and never automatically recomputed. The default profile has no
external connector registrations yet, so Programs requiring acquired input
return `ClientProgramNeedsInputs`. An explicit DuckDB or Salesforce source profile selected
with `ACTQL_LOCAL_SOURCE_PROFILE` enables the acquired-input path, including
read approval and restart. Multiple published Sources can instead be selected
with `installation.sourceProfilePaths` (or `sourceProfilePaths` on the HTTP
Host). This plural option accepts 2–128 absolute, distinct profile paths and
cannot be combined with the singular option or environment fallback. The
combined inventory remains bounded to 128 read bindings, 64 per member,
1024 exact query aliases and the existing 16 MiB environment limit. Every
member's declaration and physical binding is checked; installing a member
does not read it or resolve its credentials. Each Run retains the existing
maximum of two checked acquisition occurrences, selected by SourceRef.
See the [current implementation status](https://github.com/actql/actql/blob/main/docs/reviews/current-product-status.md)
for merged capabilities and work that is still in a PR. Salesforce requires
explicit declaration publication through the packaged `publishSource` export;
Host startup restores the publication without provider I/O.

The generated standard installation includes the finite Sheets Source and
collection-only append Effect. Explicitly publish and select its installation
profile; no Source URI causes a package download or implicit credential use.
See the [Sheets guide](https://github.com/actql/actql/blob/main/docs/connectors/sheets.md)
for the supported two-stage read Program, typed cell contract, approval and
unknown non-resend rules. Real Google service acceptance remains separate.

Multiple independently published Effects use `installation.effectProfilePaths`
(or `effectProfilePaths` on the HTTP Host). Publish each profile with the
existing `publishEffect` operation first. The plural option takes two or more
distinct absolute paths and cannot be combined with the singular option,
`ACTQL_LOCAL_EFFECT_PROFILE`, or the HTTP Host's injected Effect installation. Every
installation must own at least one unique admitted Mapping. The Host rejects
more than 256 profiles before loading because its shared checker permits only
256 Environment members in total; the same checker's 64 KiB, 4096-node and
depth-64 limits still apply to the combined Environment. Profile files have a
separate 8 MiB read bound. Run execution retains its existing member, row and
work limits.

Checked Effect kinds, targets and exact Mapping references/CIDs select one
installation for the complete Set before Compute. Missing, ambiguous or
mixed-installation Sets fail preparation. Unused installations perform no
target reads, secret resolution or dispatch. Target-read accounts remain
separate, and restart selects the original authenticated capture's Mappings
before the existing adapter validates its capability and physical bindings.
The original Run, Checkpoint, Preview and ledger owners still govern unknown
outcomes and cleanup.

An installed Effect uses `publishEffect({effectProfilePath, directory,
resolveEffectSecret})` to publish its declaration, execution Mappings and
Check Environment before Host start. The public embedded connection supplies
`installation: {directory, effectProfilePath, authorization,
resolveEffectSecret}`; the Remote HTTP Host accepts the same installation
fields in its options object. The profile contains credential references, not
access tokens. Reconnecting an embedded Host root with an equivalent profile,
generation and account configuration reuses its owner; a changed installation
is refused instead of silently attaching to the old Host. The installed
Source and Effect profiles can be selected together after both publications
are installed in the same Host root; shared connector bindings must match and
read/commit authorization remains separate. The bounded acquired
Read→Compute→Effect profile also supports approval and restart, with an
immediate read decision for a checked Source selected from the inventory.
The existing two-Source Effect profile still requires two distinct DuckDB
owners; an unused member neither becomes an acquisition nor changes that
selected pair's continuation support. Host admission and each selected
Source's own read authorization remain separate. See the
[installation and recovery evidence](https://github.com/actql/actql/blob/main/docs/reviews/current-product-status.md#source-and-effect-installation).

Preparation, compilation, and Run evidence issuance retain the same checked
owner in the installed runtime. Local does not load a second Run Host Core
runtime or recompile the Program to compare CIDs. The separately distributed
`@actql/run-host-core` keeps its standalone API and private handle custody.

Ordinary materializing Local uses finite initial Request/Run memory ceilings
of 512 MiB retained and 512 MiB execution by default. Select both together with
`installation: {requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824}}`.
Common validates the pair and derives checking and collection row ceilings from
the same effective selection. These ceilings are not prepaid memory: the same
original owner reserves and grows only actual constructor/live-output demand.
Explicit Host row limits can narrow this bound; omitted optional dimensions
remain unresolved. Wire, per-row, batch, work and saved retention/current limits
remain independent. Exceeding any applicable limit refuses rather than silently
expanding the budget. Reopen the installation with the same memory selection;
Saved reads retain their original Run and do not re-execute the Program.

For source-free ordinary Local Compute, select
`installation: {sourceFreeMaxWork: 30000000}` (or `sourceFreeMaxWork` on the HTTP
Host). The positive signed 32-bit value is captured as Host installation DATA
and bound to the same Request before its original Plan and fragment requests
are constructed. Omission keeps the Core default of 20,000,000. Each applicable
fragment/sequence has its own cumulative counter; this is not a global Run or
Host-lifetime quota, a compiler/check budget, or a change to managed-memory
admission. Acquired Source, Model and Effect work policies remain separate.
A successful computation can still refuse a later copy under the selected
retained/workspace policy. Reopen with the same installation selection;
reading an original Saved Result does not resubmit or re-execute its Program.

When an accepted Compute exceeds a managed memory or runtime-work quota,
`ExecutionUnsuccessful` keeps its original `execution` and `observation`.
Inspect `error.observation.terminal_error.message` for the failed phase,
dimension, requested additional amount, remaining allowance, selected policy,
units, and installation setting. `retained_bytes` maps to
`installation.requestMemory.retainedBytes`; `execution_bytes` maps to
`installation.requestMemory.executionBytes`. These are logical byte quotas,
not process RSS. `value_capture_work` and `control_work` map to
`installation.sourceFreeMaxWork`, which does not change Program parsing or
checking limits. The original bounded UTF8 probe can prove only a lower bound
on additional work; the message labels that bound instead of rescanning the
input. If the original failure did not retain quantities, they are explicitly
unavailable. Diagnostics do not grant a retry, success, cancellation or cleanup
acknowledgement. Re-reading the same failed Run retains the diagnosis after
confirmed stop and retirement; successful Saved reads do not resubmit it.
A request-snapshot refusal before submission remains a separate preparation
failure, rather than an accepted Compute failure.

The source-free Values profile derives its row demand from the checked authored
input and closed outputs. For a single-task Values Program a Host may explicitly
select `installation: {valuesMaxRows: 121}` (or `valuesMaxRows` in the HTTP Host
options), with a positive signed 32-bit integer budget. This representation bound is not
a workload admission guarantee; there is no separate 10,000-row product cap. The
already checked Program uses that selected ceiling in compilation,
compute/import/export capacity and Named Result row-index workspace; cells,
values, work, wire and the selected memory
ceilings remain independently bounded. Sort scratch still consumes that finite
workspace and can require more than one index per row. This option does not
enable acquired, Graph, INFER, multi-task or Effect profiles. A configured
profile's original is saved with request acceptance and bound into the Run's
execution context. Restart/attach reads the original successful Run without
recompiling under the current defaults. A new read uses a new attempt and grant;
lookup of an interrupted attempt opens no payload and consumes no new grant.

## Authored Connector Node adapters

An externally authored Connector Host or Site module can import the common
installation helpers from `@actql/local-node/connector-installation`. This
subpath directly re-exports the existing installed row Source and Effect
owners: `createInstalledRowSource`, `rowSourceCheckEnvironment`,
`rowSourceMapping`, `installRowSourceAuthorization`,
`openRowSourceCredentialSite`, `createInstalledRowEffect`, and
`retainInstalledHostInitializationFailure`. It also exports `checked` for
the pinned runtime's raised-result representation and
`invokeScopedCredentialOperation` for a declared physical credential call.
Use `canonicalJson` from `@actql/sdk/host-port` when needed.

These helpers consume the installed Host's common runtime, regenerated
declarations, account gate, credential Site, and registered installation
entry. Keep the supplied common and provider runtime objects, decisions,
grants, and other runtime handles intact. Their identity belongs to their
original owners; the declaration types do not describe the complete generated
MoonBit ABI. Connector code supplies its provider meaning and physical driver,
while the common owners retain authorization, credential use, capture,
Effect Ledger claims, recovery, and retryable cleanup. The helper subpath does
not register an installation or grant permission to perform provider I/O.

The package contains the helper implementations and their dependencies after
normal prepack. Authored packages import this public subpath, without depending
on a repository checkout or importing private `adapters` paths.

## HTTP Host

`import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host'`
opens the same installed Host through its HTTP handler. Pass an owned
`directory` and an `authenticate` callback that maps the Authorization header
to the authenticated principal (or returns `undefined` to refuse it). Optional
installation fields match the Embedded Local profile above. Attach
`host.handler` to a Node HTTPS server; close the server and await
`host.close()` when finished. Authentication and TLS configuration belong to
the embedding application. Clients use `@actql/node` or `@actql/sdk` with
`{mode: 'remote', endpoint, token, durability: 'durable'}`.

To admit `actql://host:port/workspace-id` clients, also supply the Host's
stable `workspaceId` installation option. It is a service identifier, not a
directory path or a replacement for the existing Local namespace. The Host
checks the assertion independently of current authentication/authorization on
every operation. Without this option, asserted connections are refused.
Only asserted connections receive the matching profile field; existing
endpoint clients retain their original response shape. TLS trust and server
startup remain explicit, including when the Host listens on localhost.

For explicitly opted-in local HTTP clients, set `loopbackHttp: true` and attach
the handler to a caller-owned Node HTTP server bound to a literal loopback:

```js
import {createServer} from 'node:http';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
const host = await openInstalledRemoteHttpHost({
  directory, workspaceId, authenticate, loopbackHttp: true,
});
const server = createServer(host.handler);
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen({host: '127.0.0.1', port: 8080}, resolve);
});
```

The application supplies its normal bearer-authentication callback. Clients
use `actql://localhost:8080/workspace-id?transport=http`; an IPv6-only listener
uses `host: '::1'` and `actql://[::1]:8080/workspace-id?transport=http`.
The guard checks the actual accepting Server's bind and socket addresses before
authentication, rejecting wildcard/public listeners and non-loopback peers.
Host and forwarded headers cannot supply those facts. It does not bind, retry
or reconfigure a listener. Close the server, then await `host.close()` as above.
Loopback is not an identity, and this mode does not provide TLS server
authentication. Keep ordinary authentication and per-request Workspace checks.

The physical journal and publication Store live under
`~/.local/share/actql`. Set `ACTQL_LOCAL_STATE_DIR` before process start to
select a different directory. The Host uses the current OS user's filesystem
access as its Local security boundary; it does not require Cloud credentials
or make a Cloud request. The installed profile guarantees durable request and
Result metadata only within the Store's configured retention policy. It does
not claim uninterrupted Compute or indefinite Result retention. Local-owned
embedded Hybrid is not yet installed and reports `LocalHybridUnavailable`.


## Explicit Host capacity and lookup policies

Embedded Local accepts `installation.hostCapacityPolicy`; the Remote Host
factory accepts `hostCapacityPolicy`. Supply the complete existing
`actql-capacity-host-policy/0.1` object, including its required fields. This
Host-owned option is detached before asynchronous installation and admitted
by the existing checker. Adapter publications must carry the same selected
policy; a single adapter cannot replace it implicitly. `publishEffect` accepts
the same option when publishing its policy-dependent generation. Source
publication contains connector declarations; Source loading extends the
selected Host base.

Omitting the option preserves the installed defaults and historical authority
scope. An explicit selection is bound into installation identity and the
Host-issued authority scope used by request journals and Run references. Its
policy CID covers the effective checker-consumed capacity body, including
built-in defaults for omitted optional graph limits.

Keyed SourceView JOIN also requires explicit finite lookup ceilings. Supply
`installation.hostLookupExecutionPolicy` for Embedded Local, or
`hostLookupExecutionPolicy` for the Remote Host factory and `publishEffect`.
This is the complete registered `actql-lookup-execution-policy/0.1` component:
network attempts per request, request bytes per attempt, total request bytes,
total response bytes, total decoded response bytes and total duration. Omission
leaves lookup unresolved; a Connector cannot add defaults or override the Host.
The detached selection is bound into installation identity and authority scope.
Changing it cannot reuse another scope's submission or approval. These ceilings
do not grant Source access; read authority remains independently checked for
the selected Source, physical target and original resource/version request.

Every connection reports the existing opaque authority scope in `scopeRef`,
including the default policy. This distinguishes state roots and principals
as well as explicit policy selections, without changing historical Run or
request identities. Older principal-only lookup contexts do not name this
exact scope and must not be silently translated during recovery.
Equivalent explicit policy values retain identity across restarts; a different
selection is a different request/authority scope, including for the same caller
request ID. Existing references are not translated into that scope: use the
original configuration to access its Runs. Embedded Local refuses changing the
policy of an already open installation. Selection does not grant Source,
Effect or Model authorization. Declared graph-construction limits are retained;
omitted graph limits keep the existing built-in defaults.
