# Standard Node Client

Install the published standard package with `npm install @actql/node`.
Local execution needs no additional internal package, compiler, Cloud login,
or provider assembly. For fixed release candidates and publication status,
see the [release guide](https://github.com/actql/actql/tree/main/release).

Use Node.js 22.16 or later in the 22.x line, or Node.js 24.0 or later
(`^22.16.0 || >=24.0.0`). The bundled Local Host needs the native
`node:sqlite` connection state, including `DatabaseSync.isOpen` and
[`DatabaseSync.isTransaction`](https://nodejs.org/download/release/v22.16.0/docs/api/sqlite.html#databaseistransaction).
Node.js 23 does not provide the required `isTransaction` API. This Local
requirement does not change the transport-only `@actql/sdk` runtime range.

`@actql/node` exports the same Client, Execution and Result API as the
lightweight `@actql/sdk`. Standard installation includes `@actql/local-node`.
Embedded Local loads that provider only when selected; Remote and connected
Host options remain on the transport Client path.

Use `await client.close()` in `finally`, or asynchronous disposal with
`await using` where supported. It closes this Client's readers and releases its
Local connection lease. Shared Clients stay usable; the final lease waits for
the installed Host's graceful physical shutdown. Reconnect to the same directory
to look up or attach retained Runs. Close never cancels a Run. A failed close
reports `ClientCleanupPending`; retry close on that same Client.

The current embedded Local profile supports checked, source-free Effect-free
Values Programs through named Result retrieval, request lookup and attach.
An explicitly installed DuckDB or Salesforce source profile also supports acquired input,
read approval and restart through Checkpoints. The default Values profile
does not install an external source. Embedded Local-owned Hybrid remains
unavailable. See the [current implementation status](https://github.com/actql/actql/blob/main/docs/reviews/current-product-status.md).
The standard installation also includes an explicitly configured Sheets
profile for finite typed grid reads and approved dedicated-tab appends.
See the [Sheets guide](https://github.com/actql/actql/blob/main/docs/connectors/sheets.md)
for declarations, credentials, supported Program shapes and unknown outcomes.
Fixture acceptance does not establish real Google service acceptance.
An explicit Local endpoint can use the connected Host path. The Remote SDK
does not depend on the Local package or DuckDB.

For the source-free, single-task Values profile, explicitly set
`installation: {valuesMaxRows: 121}` to select a finite positive signed 32-bit row
budget instead of deriving demand from the checked authored input and closed
outputs. The integer representation is not a product row ceiling or a guarantee
that the selected workload fits. Other work, cell, value, wire and the 512 MiB
capacity limits still apply. The installed Host saves the selected profile's
original with request acceptance and binds it to the Run; attaching to an
already successful Run does not re-execute it under current configuration.
For source-free ordinary Local Compute, `installation: {sourceFreeMaxWork: 30000000}`
explicitly selects a positive signed 32-bit work limit. Core keeps its existing
20,000,000 default when omitted. This is a cumulative limit for each applicable
fragment/sequence counter, not a global Run/Host quota or a memory grant.
Compiler/check work, acquired Source, Model and Effect policies are separate.
The same checked Plan binds the selected limit before execution; an installed
budget does not guarantee that the workload fits the independent 512 MiB limits.
See the [Local Host profile](https://github.com/actql/actql/blob/main/packages/local-node/README.md) for scope and HTTP options.

Embedded Local and Remote HTTP expose the same public submit, lookup, Run
status, Checkpoint, Named Result and cancellation operations. Transport does
not make a held or unknown request safe to resubmit under another connection.
The [packed acceptance record](https://github.com/actql/actql/blob/main/docs/reviews/2026-09-29-local-remote-client-parity.md)
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
[installed Host policy contract](https://github.com/actql/actql/blob/main/packages/local-node/README.md#explicit-host-capacity-policy).
This option is not a connected Remote Client request or authorization grant.

## Short Local queries

```js
// Run after npm install @actql/node. No endpoint, token or Cloud login is needed.
import {open} from '@actql/node';
const db = await open({stateDir: '.actql'});
try {
  console.log(await db.sql('SELECT 1 AS id').all());
} finally {
  await db.close();
}
```

Expected output: `[ { id: 1 } ]`. The same code is valid TypeScript; `open`,
`sql`, `all` and awaited `close` are part of the shipped declarations.
`@actql/sdk` is the Remote-only package and needs an existing Host and token.
An `actql://...` connection string also selects a network Host, including when
its hostname is `localhost`; it does not select this embedded Local entry.

`open()` is a thin entry into the existing installed Local Host and its private
connection lease. Its default is CWD/.actql, and `db.info.stateDir` reports the
absolute selected directory. Keep this durable state out of version control.
The existing `connect()` environment/home-directory defaults are unchanged.
`open({installation})` accepts the existing installation options except its
`directory`; choose that location only with `stateDir`. Closing or asynchronous
disposal uses the same awaited Client cleanup and never cancels a Run.

Short `sql`/`aql` calls return a native ResultPromise and preserve one request ID
across all awaits. For immediate low-level source admission use `startSource`;
Program `start` is unchanged. These entries preserve the installed language and
connector capabilities; `open` does not load or install an unselected DuckDB
adapter. See the SDK README for Result selection, read limits and recovery.
