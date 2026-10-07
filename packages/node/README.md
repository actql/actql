# Standard Node Client

`@actql/node` exports the same Client, Execution and Result API as the
lightweight `@actql/sdk`. Standard installation includes `@actql/local-node`.
Embedded Local loads that provider only when selected; Remote and connected
Host options remain on the transport Client path.

The current embedded Local profile supports checked, source-free Effect-free
Values Programs through named Result retrieval, request lookup and attach.
An explicitly installed DuckDB or Salesforce source profile also supports acquired input,
read approval and restart through Checkpoints. The default Values profile
does not install an external source. Embedded Local-owned Hybrid remains
unavailable. See the [current implementation status](../../docs/reviews/current-product-status.md).
An explicit Local endpoint can use the connected Host path. The Remote SDK
does not depend on the Local package or DuckDB.

For the source-free, single-task Values profile, explicitly set
`installation: {valuesMaxRows: 121}` to select a finite row ceiling (1..10000)
instead of its default 100. Other work, cell, value, wire and the 512 MiB
capacity limits still apply. The installed Host saves the selected profile's
original with request acceptance and binds it to the Run; attaching to an
already successful Run does not re-execute it under current configuration.
See the [Local Host profile](../local-node/README.md) for scope and HTTP options.

Embedded Local and Remote HTTP expose the same public submit, lookup, Run
status, Checkpoint, Named Result and cancellation operations. Transport does
not make a held or unknown request safe to resubmit under another connection.
The [packed acceptance record](../../docs/reviews/2026-09-29-local-remote-client-parity.md)
uses one Values document in both modes and distinguishes these local Host
tests from live Cloud verification.

## Query text and machine input

`aql-text` accepts the implemented query language, including Pipe and admitted
Graph patterns; `sql` selects SQL query heads. The retired
`AQL / PROGRAM / STAGE / STEP / OP` envelope is rejected by the Host before
Run acceptance and provider I/O. JSON/YAML Program remains supported machine
input. Text is never retried as another format, and extensions do not choose
a language. Removal of the old surface does not claim that every adopted
Graph, VecA/TEA or Effect surface is implemented.


Embedded Host operators can pass a complete `HostCapacityPolicy` as
`installation.hostCapacityPolicy`. The existing capacity contract is
snapshotted before lazy Local-provider loading and checked by the installed
Host. Explicit policy selections participate in installation and request
scope identity; omitting the option preserves historical defaults. See the
[installed Host policy contract](../local-node/README.md#explicit-host-capacity-policy).
This option is not a connected Remote Client request or authorization grant.
