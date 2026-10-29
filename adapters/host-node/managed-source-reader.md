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
actual constructor/read/failure overlap still requires the SAME Request parent.
