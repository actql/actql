# Native Remote CLI

`npm install -g actql` installs the npm launcher and an OS-specific Native
Client transport executable. The executable uses HTTPS/mTLS and the existing
Client–Host protocol. It does not embed a Local execution engine. Connecting to
a Local Host over HTTPS is remote transport, not embedded Local execution.

This release uses `actql@0.0.2`; the existing `0.0.1` name placeholder is not
overwritten. Package version and protocol version are independent. Node
22.22.0 or newer starts the npm launcher; the Native executable itself is
Node-free. There is no install-time download, compiler or fallback executable.
Do not omit optional dependencies. Platform declarations and the exact binary
digests accompany the fixed release manifest; candidate platforms are macOS
arm64 and Linux x64/glibc. A candidate is supported only after its real external
installation and Host acceptance succeeds.

Supply a Host URL, connection file, scoped token file and mTLS credentials:

```sh
actql --endpoint https://host.example/ \
  --connection-root "$PWD" --connection-file connection.json \
  --token-root "$PWD" --token-file token.txt \
  --http-library /usr/lib/libcurl.4.dylib \
  --ca ca.crt --cert client.crt --key client.key connect
```

On Linux select the installed `libcurl.so.4` instead. The Host and its
credentials are supplied separately; installation does not register a Runner
or grant execution authority. Protect the token, keys and saved operation
references. See the [transport usage](https://github.com/actql/actql/blob/main/src/cmd/native_client/README.md)
for command arguments. Allocate and save a submission reference before sending
input. Save the exact admitted Run reference for subsequent operations.

| Public SDK operation | Native Remote CLI |
| --- | --- |
| connect; new submission | `connect`; `new-submission` |
| Program/source submit | `start`; `aql` with explicit format and saved submission reference |
| Original operation lookup | `lookup-submission`; `lookup-request`; `lookup-cancellation` |
| Run attach/status/wait | `attach`; `status`; `wait` |
| Cancel | `cancel` with saved operation ID and original revision |
| Reconcile | `reconcile` |
| Bounded complete Result read | `read` with saved attempt ID |
| Delivery evidence lookup | `delivery-attempt` |
| Checkpoint answer/approval | Not connected; use the public SDK |
| Embedded Local execution | Not included; retained as a subsequent standard Local CLI requirement |
| SDK streaming/automatic disposable-handle scope | Not provided by this bounded transport CLI |

Transport errors exit nonzero. `SubmissionUnknown`, `CancellationUnknown` and
incomplete Result reads preserve the original reference/attempt for lookup.
No new submission, resend, alternate format, Site switch or cancellation is
initiated automatically. A domain outcome returned as valid JSON must be
inspected; transport success does not prove a successful Run. Existing Native
command exit semantics are unchanged. Launcher failures use 64 (unsupported
platform/libc), 65 (artifact mismatch), or 69 (missing package/start failure).

The SDK/Node initial release is independent of this CLI. Unsupported Windows,
other CPUs and musl do not receive another platform's binary. Browser, Cloud
deployment and standard embedded Local CLI completion are not claimed.
