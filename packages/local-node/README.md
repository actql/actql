# Installed Local Node Host

`@actql/node` includes this package in its standard installation. Embedded
`connect({mode: 'local', owner: 'local'})` lazily loads the checked MoonBit
compiler and runtime, the built-in Local Host adapters, and DuckDB assets.
Connected Remote mode imports only the lightweight SDK path.

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
read approval and restart. This does not imply arbitrary multi-source support.
See the [current implementation status](../../docs/reviews/current-product-status.md)
for merged capabilities and work that is still in a PR. Salesforce requires
explicit declaration publication through the packaged `publishSource` export;
Host startup restores the publication without provider I/O.

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
immediate read decision and one installed Source. See the
[installation and recovery evidence](../../docs/reviews/current-product-status.md#source-and-effect-installation).

Preparation, compilation, and Run evidence issuance retain the same checked
owner in the installed runtime. Local does not load a second Run Host Core
runtime or recompile the Program to compare CIDs. The separately distributed
`@actql/run-host-core` keeps its standalone API and private handle custody.

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

The physical journal and publication Store live under
`~/.local/share/actql`. Set `ACTQL_LOCAL_STATE_DIR` before process start to
select a different directory. The Host uses the current OS user's filesystem
access as its Local security boundary; it does not require Cloud credentials
or make a Cloud request. The installed profile guarantees durable request and
Result metadata only within the Store's configured retention policy. It does
not claim uninterrupted Compute or indefinite Result retention. Local-owned
embedded Hybrid is not yet installed and reports `LocalHybridUnavailable`.


## Explicit Host capacity policy

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
The explicit-policy connection also reports that opaque scope in `scopeRef`,
so retained SDK lookup context distinguishes the selection.
Equivalent explicit policy values retain identity across restarts; a different
selection is a different request/authority scope, including for the same caller
request ID. Existing references are not translated into that scope: use the
original configuration to access its Runs. Embedded Local refuses changing the
policy of an already open installation. Selection does not grant Source,
Effect or Model authorization. Declared graph-construction limits are retained;
omitted graph limits keep the existing built-in defaults.
