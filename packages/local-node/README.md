# Installed Local Node Host

`@actql/node` includes this package in its standard installation. Embedded
`connect({mode: 'local', owner: 'local'})` lazily loads the checked MoonBit
compiler and runtime, the built-in Local Host adapters, and DuckDB assets.
Connected Remote mode imports only the lightweight SDK path.

The installed source-free profile accepts an Effect-free JSON or YAML AQL
Program with one checked Values task and one named Result. It binds the
initial empty captured Artifact set through `@actql/run-host-core`, durably
records the request, executes the real Local Site, commits formal publication,
and serves Result rows in process. A repeated request ID with the same intent
attaches to the retained Run; changed intent is rejected. A reserved dispatch
is reconciled and never automatically recomputed. The default profile has no
external connector registrations yet, so Programs requiring acquired input
return `ClientProgramNeedsInputs`.

The physical journal and publication Store live under
`~/.local/share/actql`. Set `ACTQL_LOCAL_STATE_DIR` before process start to
select a different directory. The Host uses the current OS user's filesystem
access as its Local security boundary; it does not require Cloud credentials
or make a Cloud request. The installed profile guarantees durable request and
Result metadata only within the Store's configured retention policy. It does
not claim uninterrupted Compute or indefinite Result retention. Local-owned
embedded Hybrid is not yet installed and reports `LocalHybridUnavailable`.
