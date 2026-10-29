# Managed HTTP Source reader

`createInstalledCredentialSourceReader` is the installed RowRun's managed
reader factory. It is the existing accounted `providerReader` alternative to
an advanced physical `readPages` driver; callers select exactly one. No dummy
legacy callback is required. Core reserves the same provider capacity and
binds response cleanup before calling the factory's synchronous `prepare`.

The normal installer calls the SAME service as
`createSourceReader({installation, implementation, site, operation,
preparePageReader})`. The implementation and Site must be the originals selected
by that service for the SAME installation. The implementation supplies response,
secret and request bounds; provider options never issue a capacity or grant.
The Host binds the exact original read authorization forwarded by the Source to
that nominal Site, then obtains each indexed use from the original RowRun.

An internal explicit-port component may use the same owner's raw-Site constructor
with `{capacity, site, operation, maxResponses, maxResponseBytes, maxSecretBytes,
preparePageReader}`. This supplies no normal installation association or funding.
The existing advanced `createReader` or `readPages` alternative retains its
nominal Site and complete protocol under this SAME owner. It is exclusive with
the standard callbacks; it is not a fallback for a missing standard capacity.

`preparePageReader({resource, columns, requestWire})` is synchronous and
I/O-free. It returns original receiver-bound methods:

- `fetchPage({pageIndex, rowCount, receivedBodyBytes})` returns an HTTP request
  descriptor `{method:'GET', path, query?, headers?, responseHeaders?}`. It may
  retain API cursor state but performs no I/O. `receivedBodyBytes` is BigInt.
- `decodePage(response, {pageIndex, rowCount, receivedBodyBytes})` returns
  `{rows, done}` synchronously. A preserving generic decoder may instead
  return `{rowsWire, rowCount, done}`; the SAME Host passes that original wire
  directly to the existing Common page admission without JSON.stringify. The
  reported row count is DATA, not a substitute for actual Common validation. It receives the SAME original response only
  after retention, byte charging and a current check. It owns API status,
  parser, identity, version, cursor and provider-specific aggregate bounds.
  It must validate any next cursor/page limit before returning rows.
- Optional `onError(cause)` returns the provider's error wrapper with that SAME
  cause. It performs no retry, physical cleanup or credential work.

The trusted facade may capture the second private argument to
`preparePageReader(input, applySynchronousProjection)`. It invokes a nested pure
transform as `applySynchronousProjection(fn, receiver, args)` through this SAME
reader's callback custody. The invoker works only inside a synchronous
Host-owned callback frame; escaped or after-await calls refuse before invoking
the function. An author transform receives only its declared DATA arguments,
never this invoker. Returned Promises remain refused and joined by the same
pending-callback handling; the facade supplies no second pending inventory.

The callbacks receive no credential, authorization, raw transport, current
callback, charge callback or stop handle. The Host snapshots each request,
checks the original grant/scope, rechecks current, performs one scoped call,
retains the response before fallible accounting, charges before decoding,
and delivers rows with that exact charge ticket. It does not parse provider
JSON itself. A standard author facade must use a matching bounded preserving
parser rather than silently losing duplicate keys or wide numeric values.

The returned read handle owns cancellation and physical binding close. Read
settlement alone does not acknowledge cleanup. `requestStop` aborts and closes
the original binding; `observe().cleanupConfirmed` becomes true only after
the joined read and actual binding close, when its response aliases retire.
A callback which returns a Promise is still refused. Its SAME returned
computation remains retained and joined under this reader, including rejected
setup, request, decode and error callbacks. Cleanup cannot acknowledge release
while any such computation still borrows input or response DATA. Settlement
only permits the existing physical-close and read-completion checks; it grants
no read, retry or new authority.

`retry` retries only that cleanup, never a send or grant. Existing RowRun
cleanup invokes this same retry on a subsequent close. The original failure
remains primary if physical close also fails. A live abort is observed before the
stopped-state guard, preserving the SAME original cancellation reason through
the provider error wrapper. This does not permit another read on a closed handle.

The factory's own `retire` requests stop on its SAME active handles and refuses
completion until all readers have joined and retired. Source close calls this
original method before closing its Site. Pending physical or callback custody
therefore keeps that same Source close pending; no equal or copied factory can
acknowledge it.

This internal SPI does not certify a normal installer, complete capacity
supplier or matched runtime. Provider migrations must remove their replaced
outer and inner lifecycle managers in the same coherent composition.

Failed Source construction retains that SAME factory in the existing Host
initialization cleanup with `{sourceReader: factory, sourceProfile: site}`.
The original `retire` method and receiver are captured before cleanup awaits.
A pending retirement keeps its Site pending; independent Effect cleanup may
still finish. Only an actual synchronous `true` permits Site close. An
unexpected returned computation is joined, then refused as retirement ACK.

For the original Calendar calendars profile, the SAME implementation selector
may consume its complete required seventeen-field limits object after the
SAME installation selected its zero-metadata-response policy. It checks
`maxResponseBytes * maxPages` and `4 * maxCursorUnits` with BigInt before any
Number conversion, and checks them against that original policy. The original
`maxRows` is total rows, page rows are `min(perPage, maxRows)`, and
`maxRequests` remains a separate original ceiling; it is never extra attempts
or credit. The identity-text bound comes from the original value-text bound;
target workspace uses the already selected policy bound. Every repeated
selection must keep all original Calendar limits, including the separate CA
configuration ceiling. No field/default is added to the public profile, and
`maxCaBytes` is not reused as secret/JSON capacity. This projects demand only;
actual constructor/read/failure overlap still requires its original parent.

Installation material uses the existing Resource body tuple of the actual
initialized Source aggregate and its prepared Environment. The initial owner
must reserve construction before completing that body, retain it across
Requests, and wait for Source and physical-child retirement before release.
Requests borrow and return the same material; they do not reload Sources or
reuse a completed Request parent as installation capacity.
`borrowed_installed_source_environment` reads that same Environment only when
the existing body borrow is live and its Source aggregate is the exact original.
Equal manifests, copied aggregates and serialized identities cannot substitute
for that association. Existing borrows can identify their metadata during
retirement; the Resource owner separately refuses new sibling borrows. This
pure accessor adds no reservation, current decision, authority or cleanup ACK.

The existing connector-installation author declarations select exactly one
managed factory or advanced `readPages` callback. They expose the actual
charged-wire and optional original-authorization ports only to the private
reader preparer, and describe optional same-cleanup retry/factory retirement.
The failed-initialization `sourceReader` holding requires its synchronous Bool
retirement method. These types issue no grant, capacity or cleanup authority.

Reentrant factory retirement during pure preparation cannot discard an
unreturned handle. The SAME factory retains that handle and its returned
callback computations, requests its stop, and remains pending until they join.
The private `prepare` caller can retain a receiver-bound retirement view of
that exact invocation before fallible preparation. If the handoff throws,
the existing RowRun retries only that original view. Whole-factory retirement
remains installation shutdown: a failed request cannot stop another live
request sharing the factory. Observation is passive, and neither a truthy
value nor a returned computation's settlement acknowledges release. A custom
throwing factory without the original handoff remains pending. No new reader
or cleanup owner is created, and no prepare/read/send is retried.

Pure installed provider Sources receive the original managed Run with the
same prepared Program and Request. Their Core read port selects the Plan's
retained requirement, acquisition and reader capacity, crosses the existing
current boundary, and checks those originals again before returning the tuple.
It retains a partial read on the same Run if that boundary refuses. Missing
retained-plan support refuses instead of preparing another equal query or
acquisition. Later current checks and the ordinary Credential read grant still
apply. This borrow does not fund earlier installation/configuration/schema
construction or replace the original parent's constructor/failure overlap.

Native callback Promises stay in the existing pending-callback inventory before
their public `then` property is observed. The original getter error remains the
read failure; only actual native settlement can release that callback borrow.

An advanced constructor must still return its reader synchronously. A returned
native Promise is refused, but the same Host joins its original computation and
retains the actual late child before observing its cleanup methods. Stop requested
while construction is pending reaches that same child once it arrives; its
actual stop settlement and retirement remain required before release. A public
`then` getter failure stays primary, and rejection never fabricates a child.
No refused asynchronous constructor starts a read or causes another construction.

A standard page callback describes a bodyless GET. A factory may also capture an
explicit positive own-data `maxRequestBytes` and describe a POST with its original
String body. The Host checks UTF-8 bytes and forwards that same bound and body to
the scoped Credential invocation. Other methods remain refused. This rejection
ceiling supplies no constructor capacity: nominal implementations may select only
request shapes covered by their actual material and retained-overlap recipe.

## Original initial Source material

The normal initializer consumes the original Host initialization input and its
live Resource capacity once, before shared profile or identity metadata I/O.
The existing service retains the typed Source successor before any fallible
constructor. It never exposes a Ledger or replaces this input with a completed
Request, public profile amounts or a copied Environment.

The loader passes `configurationReader` and `sourceInitialization` to the
selected provider. The former reserves the existing chunk/concatenation Buffer
peak before opening, then the actual received native JSON/text peak before
decode. Its original file-close owner retains a failed FD; the service only
observes that same cleanup status. The original native JSON semantics remain.

`sourceInitialization.prepareDeclaration(views, expectedCatalogCid?)` is a
receiver-bound synchronous port returning `{declaration, declared, environment}`.
It captures the provider's original view strings before current callbacks,
reserves declaration/schema/identity/output overlap, invokes the existing
Common constructor and freezes the same native projection in place. Providers
pass these exact originals, including `environment` and `sourceInitialization`,
to `createInstalledRowSource`. They select their Reader implementation and Site
through the same four existing service methods; this context supplies neither
permission nor a numerical Reader capacity.

Each normal quartet call also carries that exact `sourceInitialization`.
The table entry identifies installed connector code; it does not identify one
of several Source profiles using that code. Profile/implementation selection
and the original Site association are keyed by the individual Source context,
so different connections keep their own original origins and valid bounds.
A changed selection on the same context still refuses. No equal/copied context
or fabricated table entry can recover another Source's selection.

Native input nodes, decoded text, owned Buffer/wire peaks and complete retained
prefixes use the existing shared execution-capacity allowances. The recipe
includes profile projections, declaration/Catalog/manifest assembly, Environment
merging and failed constructors. Fixed control frames remain Host baseline;
these logical allowances are not measured JavaScript heap/RSS geometry.
Issuer-key intake observes the size of the same opened FD and reserves before
buffering it, without reusing a CA/secret/JSON limit. Growth beyond that original
extent refuses on the same handle. The original key error wrapper retains its
actual close/retry owner; no read or key construction is retried for cleanup.

The initializer completes the same body with its actual Source installation and
prepared Environment. Requests borrow and return that body through the existing
Resource tokens. Source close must settle the original Readers/Sites and pending
configuration cleanup before retirement; outstanding Request borrows keep the
same debit live. Source retirement does not close the original Host admission.
That existing initial owner closes only after its Source successor and physical
children have actually settled.
