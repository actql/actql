# Installed Local Node Host

`@actql/node` includes this package in its standard installation. Embedded
`connect({mode: 'local', owner: 'local'})` lazily loads the checked MoonBit
compiler and runtime, the built-in Local Host adapters, and DuckDB assets.
Connected Remote mode imports only the lightweight SDK path.

The installed source-free profile accepts an Effect-free JSON or YAML AQL
Program with one checked Values task and one named Result. It binds the
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
Effect and installed source profiles cannot be selected together in 0.1.

Preparation, compilation, and Run evidence issuance retain the same checked
owner in the installed runtime. Local does not load a second Run Host Core
runtime or recompile the Program to compare CIDs. The separately distributed
`@actql/run-host-core` keeps its standalone API and private handle custody.

The physical journal and publication Store live under
`~/.local/share/actql`. Set `ACTQL_LOCAL_STATE_DIR` before process start to
select a different directory. The Host uses the current OS user's filesystem
access as its Local security boundary; it does not require Cloud credentials
or make a Cloud request. The installed profile guarantees durable request and
Result metadata only within the Store's configured retention policy. It does
not claim uninterrupted Compute or indefinite Result retention. Local-owned
embedded Hybrid is not yet installed and reports `LocalHybridUnavailable`.
