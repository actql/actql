# Explorer Local Gateway: finite read-only transport

This private development package attaches an **already-connected public SDK
Client** to a loopback Hono server. It opens no Host, Store or execution Owner.
The first transport unit supports static `plan`, original Run `attach`/`inspect`
and Named Result `describe`. Result payloads, Sample, controls, submission and
Effect operations are unavailable. The React/Flow SPA, built asset loader and
Cloud route adapter are subsequent units; this is not the complete Explorer.

```js
import {startExplorerGateway} from '@actql/explorer';

// `client` belongs to the embedding application and retains Host authority.
const gateway = await startExplorerGateway({client});
const bootstrap = gateway.issueBootstrap();
// Supply bootstrap to the local browser once, without putting Host secrets
// in a URL, storage or JavaScript. The browser adapter exchanges it by POST.
// Explicitly invalidate presentation before changing authority/Workspace:
gateway.invalidateScope();
await gateway.close(); // closes this server, not the Client or any Run
```

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

Only an explicitly preloaded asset Map is served: at most 32 assets and 2 MiB
in total, with closed path/content-type sets. Assets are copied at admission;
requests cannot traverse the workspace. The current tests use asset fixtures,
not a Vite build. The next unit must supply actual built assets and their
external package/peer/styles acceptance. No Vite development server is used.

Hono 4.13.13 and its Node adapter 2.1.4 are exact MIT-licensed pins. The
[official Node adapter documentation](https://hono.dev/docs/getting-started/nodejs)
defines the HTTP server/Fetch seam; it does not supply the application security
or Host authorization contract. React/Query remain outside this transport and
will be peers of the shared UI package, rather than a second bundled runtime.

Finite Node tests cover refusal before SDK I/O, real loopback server closure,
expiry, stale replies/errors, body/reply/concurrency limits and non-renewal.
They are not current-main packed Host, Cloud, Native or full E1 acceptance.
