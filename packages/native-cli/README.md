# Native CLI

`npm install -g actql` installs the npm launcher and an OS-specific Native
Client executable. Remote remains the default and uses HTTPS/mTLS and the
existing Client–Host protocol. Explicit `--mode local` uses the existing Native
Host, checker, journal and Store. Connecting to a Local Host over HTTPS is still
Remote transport, not embedded Local execution.

The fixed Darwin arm64 private-integration cohort from source
`eb2f8b3b0a096e8dd86548bffbc6bafb6e79fc20` completed seventeen Local CLI
operations on macOS 26.0 or newer, including three expected refusals and no
skips. After external installation and explicit trust adoption, it exercised
`check`, source-free SQL `explain`, `run` with `SELECT 1 AS n`, fresh-process
`status` by original reference and Run ID in JSON/human form, and the Named
Result `[{"n":1}]` with digest/release evidence and an explicit retained reread.
This is exact-cohort evidence, not acceptance of the latest main or complete
Source/Model/Effect/approval/cancel/Debug and other-platform Local profiles.

The earlier source `109564ef9a4f8241096292843b875d4c81fbb6f3` keeps its
original eleven-case `aql`/Result evidence. Its binary and capabilities are not
relabelled as the later cohort.

Local initialization requires `actql --mode local adopt --json`; `connect`
cannot silently adopt. Product defaults and bundled dependencies do not require
user-authored internal configuration, library paths, a Host, token or mTLS.
The defaults authorize only the finite source-free private-Store profile, not
external I/O. `check` still returns `kind: prepared`, not a public diagnostic
report or Run admission. See the
[Local command guide](../../docs/cli.md#accepted-source-free-local-baseline).

The accepted fixed cohort uses `actql@0.0.2`; the existing `0.0.1` name
placeholder is not overwritten. This acceptance does not publish npm packages
or establish registry availability. Package and protocol versions are
independent. Node 22.22.0 or newer starts the npm launcher; the Native executable itself is
Node-free. There is no install-time download, compiler or fallback executable.
Do not omit optional dependencies. Platform declarations and the exact binary
digests accompany the fixed release manifest; candidate platforms are macOS
arm64 and Linux x64/glibc. A candidate is supported only after its real external
installation and Host acceptance succeeds.

For Remote mode, supply a Host URL, connection file, scoped token file and mTLS
credentials:

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
| Program/source submit | `start`; `aql` with explicit format, saved submission reference and explicit invocation attempt ID |
| Original operation lookup | `lookup-submission`; `lookup-request`; `lookup-cancellation` |
| Run attach/status/wait | `attach`; `status`; `wait` |
| Cancel | `cancel` with saved operation ID, original revision and explicit invocation attempt ID |
| Reconcile | `reconcile` |
| Bounded complete Result read | `read` with saved attempt ID |
| Delivery evidence lookup | `delivery-attempt` |
| Checkpoint answer/approval | Not connected; use the public SDK |
| Embedded Local execution | Explicit `--mode local`; accepted source-free Darwin arm64 baseline only |
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
deployment and complete standard Local Source/Effect/Debug capability are not claimed.
