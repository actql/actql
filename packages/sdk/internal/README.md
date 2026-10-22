# SDK implementation boundaries

`index.mjs` exposes the existing public API and selects a connection. `client.mjs`
assembles fixed operation families after admitting the captured Host profile.
These modules are package implementation files, not additional package exports.

- `check-observation.mjs` owns Check input, report and frontier associations,
  location resolution, editor sessions, and the Check operation.
- `submission-observation.mjs` owns original Submission and Request associations,
  submission invocation results, explicit lookups and recovery attachment.
- `run-observation.mjs` owns Run observation explanations and control-revision
  comparison for each attached handle, including cancellation and Owner views.
- `result-read.mjs` constructs readers and owns read progress, validation and
  DeliveryAttempt associations. It uses the connection's original reader cleanup
  sets. Reader cleanup does not cancel a Run or acknowledge a remote release.
- `client-lifecycle.mjs` seals the connection and retains failed reader/provider
  cleanup for an explicit retry on the same connection.
- `transport.mjs` owns dispatch tracking and transport I/O;
  `transport-response.mjs` bounds control-response decoding. A dispatched request
  with an uncertain response is not automatically sent again.
- `connection-options.mjs`, `plan.mjs`, `resources.mjs`, and
  `checkpoint-operations.mjs` keep those independent connection/service concerns
  out of the public entry and the observation families.

Identity WeakMaps stay private beside the operations that admit and retain their
entries. Sharing a formatted explanation or copying an object never transfers
that association. Modules exchange narrow operations and immutable connection
facts, not a shared mutable context containing all families' identity stores.
The `data.mjs` helpers capture and compare data; they do not validate the wire or
own observations. Wire admission continues to use `@actql/client-wire`.

Profile, attachment and Run-state replies are detached by `captureResponse`
before their existing wire admission. Admit that snapshot once, without a
verification clone or full structural serialization. This reuse ends at that
synchronous boundary: every new status/wait/reconcile or attachment still calls
the Host and validates its new reply. Independent state/control revisions and
the stable-and-newer wait contract remain checked. Private retained control
facts are separate from the returned mutable presentation; this does not cache
Account authority, skip a durable claim or infer an Effect outcome.

English facts-to-display projections and translations live in the existing
presentation modules. Check rendering receives only original-input location
resolvers; presentation cannot submit, retry, cancel, grant access or free Host
resources. The package's `files` closure includes this directory, while its
`exports` surface continues to expose only the public SDK and Host port.
