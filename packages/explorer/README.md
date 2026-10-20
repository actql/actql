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

To open a selected Program directly, use
`npx actql-explorer --local --state-dir .actql --program query.sql`.
SQL is the default; select `--format aql` or `--format program` for AQL
text or Program JSON. The existing `--format aql-text` alias remains accepted. This reads a static Plan after the explicit browser
session is connected. It does not submit, start or execute the Program.
To read an existing Run's saved original Plan directly, use
`npx actql-explorer --local --state-dir .actql --run run-reference.json`.
The file contains the complete original `namespaceId`, `authorityScopeCid`
and `runDefinitionCid` reference returned by the public Client. A bare ID,
foreign reference or missing old map is not repaired by compilation or a new
Run. Program and Run input options are mutually exclusive.

Input files are bounded UTF-8 regular files; the selected file itself cannot
be a symlink. The complete presentation envelope must fit the same 65,536-byte
Gateway request limit. File paths are never served to the browser. The bounded
input is copied before opening the Host. The browser receives only the existing
Owner's Plan projection, through the same short-lived, Origin/Host/CSRF-protected
session; authoring file text stays with the launcher. Input confers no Run or
Source authority. Automatic browser opening is not provided;
open the printed loopback URL and paste the one-use bootstrap as below.

The nonconflicting `actql-explorer` launcher explicitly uses `@actql/node.open`
in the same process. Open the printed loopback URL and paste its one-use
bootstrap into the page within 60 seconds. Press Enter in the terminal to issue
a new bootstrap; this invalidates the previous presentation session. The
bootstrap is never put in a URL or long-lived browser storage. No Host token,
certificate, absolute library path or Vite server is needed for this Local
source-free profile. The launcher submits no Program or business operation.

Use **Read Plan** for SQL/AQL-text or Program JSON. For an existing Run, paste
its original complete Run reference JSON and optionally a Named Result name.
Use **Read saved Run Plan** to read the immutable map captured at that Run's
original admission. This calls `attach` and `Run.plan()` for the complete
original reference; it does not compile today's Program or create a replacement
Run. Missing legacy evidence or unsupported Hosts stay unavailable. The saved
map is static and is not a live progress overlay or an atomic Run snapshot.

The viewer calls public `plan`, `attach`/`inspect`/`Run.plan` and Result `describe` only.
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
pending SDK slot. Slots remain held until the read actually settles. Gateway
close fences new requests immediately and waits for the original outstanding
SDK calls, including calls whose presentation deadline has expired. The owning
Local launcher closes its Client only after that settlement. Closing the server
closes its own HTTP connections, not the borrowed SDK Client. Invocation
settlement does not replace the Client's separate physical cleanup ACKs.
If HTTP server close refuses, retry retains that same listener after both the
close callback and original SDK calls settle. A pending callback keeps the same
close attempt; a successful close remains acknowledged.

Only admitted built assets are served: at most 32 assets and 4 MiB in total.
The launcher reads its own package-relative frozen inventory, checks every
length and SHA-256, refuses symlinks/duplicate/traversing paths, and then lets
the Gateway copy the finite Map at admission. No workspace path is served.
The optional Flow view includes the pinned ELK.js layout Worker in this same
inventory and serves it under the same-origin `worker-src 'self'` policy. List
remains the default; a layout failure preserves List and does not start/retry a
Run. See [third-party notices](THIRD_PARTY_NOTICES.md).
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

## Current observations

Read Run and metadata now displays the shared current Run inspector and one
bounded Owner-local history page, with original identity/revisions and explicit
unknown/unavailable quantities and Result availability. This remains metadata:
no sample/payload, checkpoint resolution, control mutation or business work is
started. A cancellation acknowledgement does not become physical cleanup proof.

Following is opt-in for the exact last-read Run and refreshes read-only evidence
once per second until a terminal state, refusal, reference change or disconnect.
It never calls execution wait/start/resume/reconcile. Every refresh uses the
current SDK/Host permission and the same finite Gateway session; no long-lived
Allow or durable bootstrap URL is retained. Independent observations remain
non-atomic and are not overlaid onto logical steps without an original binding.

## Explicit cancellation in the current Explorer

The viewer remains read-only by default. `actql-explorer --local --allow-cancel`
adds the existing Host cancellation request and original-operation lookup to the
same authenticated loopback session. This flag enables a presentation route;
it does not authorize the caller. The Host independently checks its current
cancellation permission and original Run/control revision.

Read the exact existing Run, prepare and save its cancellation reference, then
explicitly request cancellation. The reference fixes the observed control
revision, cancellation ID and invocation attempt. This view sends that request
once. A lost or malformed reply stays Unknown: use **Look up original
cancellation**, or load the saved JSON in a later viewer for lookup only. No new
ID, revision, request or Run is generated as a recovery action. Closing or
reconnecting the viewer does not resend the operation. Stale-scope replies and
protected observations are discarded; the Client's original lookup reference
is retained so its uncertainty is not silently forgotten.

Cancellation acceptance is not physical stop, cleanup, Result release or a
successful Run. The existing Run inspector observes those facts independently.
Pause, step, resume and Sample payloads remain unavailable. This connection does
not create a new controller, Host, scheduler, grant or durable operation store.

## Checkpoint review reads

The shared Checkpoint panel lists one authorized waiting Host page and explicitly
reads the original Checkpoint's exact review projection through the public SDK.
Listing, review reading and answering have separate current Host permissions.
The list is independent of the selected Run; original subjects are displayed
without a guessed Run/Logical Map join. A further cursor is retained only as an
opaque indication and is not fetched automatically. A missing API is unavailable.

Review bytes retain the Checkpoint CID and original review projection CID; the
existing SDK verifies integrity. UTF-8 is escaped text, binary stays base64, and
no parser invents a resolved target or Effect diff. Read refusal or scope change
clears protected contents. This panel supplies no signer, answer, approval,
execution, resume, new permission or durable state. It does not make the static
Plan's unknown Preview an observed one.
