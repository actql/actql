# Workspace connection strings

An `actql://` URI identifies one service Workspace. The initial SDK binding
uses the existing Client–Host HTTPS transport; it introduces no execution
engine, discovery service, automatic daemon or new authorization model.
The registered wire shapes and generated JS/TypeScript/Native validators are
owned by `spec/contracts/actql-client-host.json`.

## Syntax and credential handling

The supported network forms are:

```text
actql://token:<percent-encoded-bearer>@host[:port]/<workspace-id>
actql://host[:port]/<workspace-id>
```

`token` is a literal credential-format label, not a username or Basic-auth
login. Encode the opaque credential and the single Workspace path component
independently. Decode each exactly once. The Workspace ID is case-sensitive,
bounded to 256 UTF-16 units, and is not a display name, filesystem path,
Organization, OSS namespace or authority scope. Dot segments, decoded slash
or backslash, controls, malformed escapes and extra path segments are refused.
No query or fragment is accepted in this initial form. An empty credential,
ambiguous userinfo or characters unsuitable for a Fetch header are refused
before I/O. The whole input is bounded to 16,384 characters and a decoded
credential to 8,192 characters.

A secret-bearing DSN is ordinary secret configuration, suitable for an
application-supplied environment variable. A credentialless DSN accepts a
separate token string or synchronous/asynchronous getter. Supplying both is an
error even when the values agree; there is no precedence rule. The SDK does
not read environment variables, create credentials, save them or renew them.

The parser constructs a fresh credential-free HTTPS origin from the authority.
It never changes an `actql:` URL's scheme in place, uses its original string
as an HTTP URL, or follows a discovered origin. Credentials enter only the
Authorization header for that origin. Redirects remain refused. Credentials
and the raw DSN are absent from profile/configuration views, request bodies,
submission snapshots, lookup contexts and Run references. Parser, option,
credential-provider, transport and response-consumption failures do not copy
borrowed credential-bearing causes into DSN errors. Existing outcome and
recovery facts remain separate. An application can still disclose its own
original string by logging it; the SDK cannot prevent that.

## Authenticated target assertion

`connection.workspaceId` is optional for the existing endpoint API and
required for the DSN entry. The Client retains it immutably and sends it on
every operation, including request lookup, Checkpoints, reads and controls.
It expresses the expected target, not permission to select a new target.

After authentication, each Host ingress obtains the actual Workspace from
its trusted request-scoped grant or installation. Missing binding support,
resolution failure or inequality returns `ClientConnectionDenied` before
operation authorization/handlers, preparation, request/Run/resource lookup,
admission or dispatch. Authentication's own credential-store lookup necessarily
comes first. An old boolean authorizer cannot implicitly accept the assertion.
Normal current authorization remains mandatory after matching.

An asserted connect response includes `profile.workspaceId` from that same
trusted binding. Generated response rules require exact equality. Unasserted
connections omit the field, preserving old clients' closed profile shape.
An older Host that rejects the new field is unsupported; the Client never
removes the assertion or automatically retries against another target.

The Node HTTP Host accepts an explicit installed `workspaceId`. Its existing
Local namespace and root-derived authority remain unchanged. Cloud maps its
own authenticated Workspace using its existing adapter; the SDK does not
duplicate Cloud scope hashing or assume namespace IDs equal Workspace IDs.
Changing credentials on one Client never changes its asserted target. Each
request obtains its credential into request-local state, and the Host checks
the current binding before any business operation. Saved request/Run identities
retain their existing owners. This does not solve lost-history admission or
create replay permission.

## Local and deployment boundaries

`actql://localhost:port/workspace` denotes an already running network Host,
not an embedded directory. In this first binding it also uses HTTPS and
ordinary certificate verification. Applications provision their Host and TLS
trust explicitly. There is no HTTP downgrade or certificate-warning bypass.
Explicit loopback HTTP and an in-process `open()` facade are separate work;
their absence must not be disguised as an automatic fallback.

The existing `{mode, endpoint, token}` API and `Promise<Client>` connection
handshake remain available. SQL/AQL, Execution, Result and lifecycle behavior
are unchanged by this connection entry. Flight SQL, MCP and other ecosystem
adapters may reuse the identifier through their own supported contracts;
this change does not claim those protocols or their deployment exist.
