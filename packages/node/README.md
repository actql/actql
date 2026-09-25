# Standard Node Client

`@actql/node` exports the same Client, Execution and Result API as the
lightweight `@actql/sdk`. Standard installation includes `@actql/local-node`.
Embedded Local loads that provider only when selected; Remote and connected
Host options remain on the transport Client path.

The current embedded Local profile supports checked, source-free Effect-free
Values Programs through named Result retrieval, request lookup and attach.
Acquired input and embedded Local-owned Hybrid remain outside this profile.
An explicit Local endpoint can use the connected Host path. The Remote SDK
does not depend on the Local package or DuckDB.
