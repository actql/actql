# Native Client transport CLI

`actql-native-client` is a Node-free native binary that uses the public
Client–Host HTTP protocol over mTLS. It uses the existing bounded native
HTTPS adapter. It does not load a Local kernel or a Cloud SDK, and it does not
implement Run admission or retry itself. The selected Host must provide the
corresponding operations.

Build with the pinned MoonBit toolchain using `moon build --target native
--release src/cmd/native_client`. The resulting binary is
`_build/native/release/build/cmd/native_client/native_client.exe`. Supply an
HTTPS endpoint, CA, client certificate and key, the installed libcurl library,
and a bearer token file. The token stays out of command-line arguments.

The connection JSON contains the public `mode`, `owner`, `consentRefs`,
`runners`, optional `durability` and Hybrid `movementPolicyRef`. Local-owned
Hybrid also requires a registered `cloudConnectionRef`; Cloud-owned Hybrid
requires at least one selected Runner. The CLI
negotiates that exact connection before each operation and rejects a Host
profile with a different mode or owner, or a downgrade from requested durable
to volatile. The `aql` command takes a JSON or YAML Program document and an
explicit `--format`; `start` takes a JSON Program object. Both can take a
`--parameters-file`. Both currently require a caller-saved `--request-id` so
an ambiguous submission can be looked up or resent with the same intent.
`lookup-request` only queries existing request history and rejects malformed
Host replies instead of reporting them as successful lookups.

`attach`, `status`, `wait`, `cancel`, `reconcile`, `read` and
`delivery-attempt` use an explicit Run reference file. `read` requires a
caller-saved attempt ID. It accepts only a complete JSONL response with the
normal terminator and writes exact payload bytes to stdout after completion.
The whole response is bounded by `--max-response-bytes` (default 1 MiB,
maximum 16 MiB); this is a bounded CLI read, not the streaming SDK reader or
a JavaScript heap limit. A failed read reports its attempt ID and does not
cancel the Run. `delivery-attempt` validates the existing attempt-lookup
reply shape and never requests payload replay.

This is a transport development artifact. The BASE Host has no generic
Program submit or full active-Run state service, and the binary does not yet
include embedded Local providers. The mTLS fixture in
`scripts/test-native-client.mjs` uses a mock Host, while the existing
published-Result test exercises a real Node Host and MoonBit publication
owner. Neither proves a native end-to-end Program Run.
