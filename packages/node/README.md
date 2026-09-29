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

Embedded Local and Remote HTTP expose the same public submit, lookup, Run
status, Checkpoint, Named Result and cancellation operations. Transport does
not make a held or unknown request safe to resubmit under another connection.
The [packed acceptance record](../../docs/reviews/2026-09-29-local-remote-client-parity.md)
uses one Values document in both modes and distinguishes these local Host
tests from live Cloud verification.
