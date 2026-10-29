# Managed HTTP Source reader

`createInstalledCredentialSourceReader` is the installed RowRun's managed
reader factory. It is the existing accounted `providerReader` alternative to
an advanced physical `readPages` driver; callers select exactly one. No dummy
legacy callback is required. Core reserves the same provider capacity and
binds response cleanup before calling the factory's synchronous `prepare`.

The trusted installer supplies `{capacity, site, operation, maxResponses,
maxResponseBytes, maxSecretBytes, preparePageReader}`. These are the original
Site, operation and finite existing limits, not an author-issued grant or new
Ledger. The Site provides its original `credential`, `callResource` and
`referenceCurrent`. The RowRun supplies original `verifyRead`, indexed
`authorizationFor`, `chargePage` and `consumePage` callbacks.

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
remains primary if physical close also fails.

This internal SPI does not certify a normal installer, complete capacity
supplier or matched runtime. Provider migrations must remove their replaced
outer and inner lifecycle managers in the same coherent composition.
