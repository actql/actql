# Standalone read-only Explorer

Install the separate package with `npm install @actql/explorer`. It includes
its built React SPA, Hono Gateway and standard Node runtime dependency closure.
The normal SDK and CLI do not acquire Explorer/React/Flow/Hono dependencies.
`@actql/explorer-ui` remains the shared Cloud library with React/React DOM peers
and built CSS exports. No private Cloud package is needed.

This is the normal installation interface for a supplied Explorer release
cohort. Checked-in `private: true` / `0.0.0-development` manifests serve repository
development; the [optional release recipe](../../release/explorer-cohort.json)
stages exact versions and registry-resolvable dependency/peer metadata. Fixed RC
installation evidence applies to that RC's source and archive digests, rather
than every later main revision. Formal registry publication requires a separate
GO; a missing unpublished version is not proof of an installation defect.

```sh
npx actql-explorer --local --state-dir .actql
```

The nonconflicting `actql-explorer` launcher explicitly uses `@actql/node.open`
in the same process. Open the printed loopback URL and paste its one-use
bootstrap into the page within 60 seconds. Press Enter in the terminal to issue
a new bootstrap; this invalidates the previous presentation session. The
bootstrap is never put in a URL or long-lived browser storage. No Host token,
certificate, absolute library path or Vite server is needed for this Local
source-free profile. The launcher submits no Program or business operation.

Use **Read Plan** for SQL/AQL-text or Program JSON. For an existing Run, paste
its original complete Run reference JSON and optionally a Named Result name.
The viewer calls public `plan`, `attach`/`inspect` and Result `describe` only.
It preserves original logical occurrences/ports and non-atomic Run observations;
missing source origins and unsupported controls are shown as unavailable.
Result description is metadata, not payload delivery or success evidence.

To attach a Client already owned by your application, use the launcher API:

```js
import {startExplorer} from '@actql/explorer/launcher';
// client is your existing public @actql/sdk or @actql/node Client.
const viewer = await startExplorer({client});
const {origin, bootstrap} = viewer.issueBootstrap();
console.log(origin, bootstrap); // supply once from this local operator context
await viewer.close(); // closes only this Gateway, never the borrowed Client/Run
```

`openLocalExplorer({local: {stateDir: '.actql'}})` is the explicit owning API.
It loads the assets first, then opens the existing Node Host once. Store locks,
shared connection leases and recovery remain with Node; failure is not retried
through another Host. Closing releases that original Client lease using its
awaited close contract. Close never cancels a Run or releases retained Results;
retry a failed close on the same viewer. Browser disconnect only discards its
presentation session. Closing the terminal viewer closes its server and lease.

The low-level `startExplorerGateway` export is also available for embedding an
already-connected Client with a caller-admitted asset Map; it opens no Host.

`issueBootstrap()` is an explicit launcher action. Its one-use token expires
after at most 60 seconds. The resulting session lasts at most five minutes,
uses a path-scoped HttpOnly SameSite=Strict cookie and requires a separate CSRF
header. Exact Host and Origin checks reject external origins, DNS rebinding,
proxy headers and credential-bearing query URLs. Binding is always
`127.0.0.1`; there is no external CORS or forwarding endpoint. Bootstrap and
session data stay in memory, and session expiry never causes silent renewal.

The SDK applies current Host authorization on every read. A Gateway session is
not an authority, execution fence or durable Run revision. The application
invalidates the Gateway on a scope change; SDK failures and old-scope replies
cannot establish facts for the new scope. In-flight expiry is checked again
before disclosure. No new authorization Boolean replaces an existing Owner.

Requests are bounded to 65,536 bytes, depth 64 and 10,000 JSON nodes. Projection
bounds retain tighter caller limits through the shared read model. Replies are
bounded to 262,144 bytes, with at most four outstanding SDK reads. The 15-second
presentation deadline does not cancel a Run, retry the request or free a still
pending SDK slot. Slots remain held until the read actually settles. Closing
the server closes its own HTTP connections, not the borrowed SDK Client.

Only admitted built assets are served: at most 32 assets and 2 MiB in total.
The launcher reads its own package-relative frozen inventory, checks every
length and SHA-256, refuses symlinks/duplicate/traversing paths, and then lets
the Gateway copy the finite Map at admission. No workspace path is served.
Normal prepack builds the SPA and inventory; installation runs no compiler,
Vite server, downloader or lifecycle hook.

Hono 4.13.13 and its Node adapter 2.1.4 are exact MIT-licensed pins. The
[official Node adapter documentation](https://hono.dev/docs/getting-started/nodejs)
defines the HTTP server/Fetch seam; it does not supply the application security
or Host authorization contract. React/Query remain outside this transport and
will be peers of the shared UI package, rather than a second bundled runtime.

Controls, Samples, Result payloads, Timeline/physical observations, source-map
origins and the Cloud route adapter remain outside this finite distribution.
No full E1, Full Explorer, Cloud, Native or live Provider acceptance follows
from the read-only installed profile. The optional Explorer cohort is separate
from the initial four-package Node release; formal publication needs its own GO.
