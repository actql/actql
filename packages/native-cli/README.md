# Native CLI

ActQL CLI v0.0.2 — Initial Developer Preview

```sh
npm install -g actql
actql version
```

The preview CLI targets macOS arm64 and Linux x64 with **glibc 2.38 or newer**.
Debian 13 meets the Linux requirement; Debian 12 (glibc 2.36) does not. This
minimum comes from the bundled Local runtime, including Crypto, and applies
even to `actql --version`. The current
macOS qualification environment is 26; the final binary's ABI and installed
acceptance must establish any earlier minimum. Intel Macs, Windows and musl
are outside this release. Public APIs, command syntax, and
storage formats may change incompatibly during the preview. See the
[release notes](../../release/notes/v0.0.2.md).

The npm package installs a small launcher and the selected Native executable.
Node 22.22.0 or newer starts the launcher; the executable itself is Node-free.
There is no install-time download, compiler or fallback engine. Keep optional
dependencies enabled so npm installs the matching binary package. Exact source,
binary digests and platform requirements belong to the fixed release manifest.
Installation intentionally has no platform-check lifecycle script: npm can
finish installing on an older glibc, but the launcher refuses execution with
exit 64. Installation success does not establish runtime compatibility.

## Local projects and Remote Hosts

Local project commands use the packaged Native Host, checker, journal and Store:

```sh
actql init --template deal-review-mock deal-review
cd deal-review
actql run deal-review.aql --stop-before commit
```

The template uses mock Connectors and a mock model without live-service
credentials. Use `approve`, `status` and `result` to continue and inspect that
same Local Run. Project discovery selects Local execution when no explicit
Remote or connection selection overrides it. Quick queries such as
`actql sql 'SELECT 1 AS id'`, and saved `status`/`result` commands, can also use
Local mode without a project. Use `--mode local` or `--mode remote` to select
the mode explicitly; Remote connection options take precedence over project discovery.

`init` explicitly adopts the new project Store. Low-level Local initialization
uses `actql --mode local adopt --json`; `connect` cannot silently adopt. The
finite default source-free profile grants no external I/O authority. `check`
returns `kind: prepared`, not Run admission. See the [CLI reference](../../docs/cli.md).

Explicit Remote mode uses the existing HTTPS/mTLS Client–Host protocol. A
connection to a Local Host over HTTPS is Remote transport, rather than embedded
Local execution. The Host and its credentials are supplied separately.

For Remote mode, supply a Host URL, connection file, scoped token file and mTLS
credentials:

```sh
actql --endpoint https://host.example/ \
  --connection-root "$PWD" --connection-file connection.json \
  --token-root "$PWD" --token-file token.txt \
  --http-library "$ACTQL_HTTP_LIBRARY" \
  --ca ca.crt --cert client.crt --key client.key connect
```

Set `ACTQL_HTTP_LIBRARY` to the absolute path of the installed `libcurl.so.4`
on Linux or `libcurl.4.dylib` on macOS.
Installation does not register a Runner or grant execution authority. Protect
the token, keys and saved operation
references. See the [transport usage](https://github.com/actql/actql/blob/main/src/cmd/native_client/README.md)
for command arguments. Allocate and save a submission reference before sending
input. Save the exact admitted Run reference for subsequent operations.

| Operation | Native CLI |
| --- | --- |
| connect; new submission | `connect`; `new-submission` |
| Program/source submit | Local project `run`; Remote `start`/`aql` with explicit format, saved submission reference and explicit invocation attempt ID |
| Original operation lookup | `lookup-submission`; `lookup-request`; `lookup-cancellation` |
| Run attach/status/wait | `attach`; `status`; `wait` |
| Cancel | `cancel` with saved operation ID, original revision and explicit invocation attempt ID |
| Reconcile | `reconcile` |
| Bounded complete Result read | `read` with saved attempt ID |
| Delivery evidence lookup | `delivery-attempt` |
| Checkpoint answer/approval | Local project `approve`/`reject`; use the public SDK for Remote approval |
| Embedded Local execution | Project-selected or explicit `--mode local` on either selected release platform |
| SDK streaming/automatic disposable-handle scope | Not provided by this bounded transport CLI |

Transport errors exit nonzero. `SubmissionUnknown`, `CancellationUnknown` and
incomplete Result reads preserve the original reference/attempt for lookup.
No new submission, resend, alternate format, Site switch or cancellation is
initiated automatically. A domain outcome returned as valid JSON must be
inspected; transport success does not prove a successful Run. Existing Native
command exit semantics are unchanged. Launcher failures use 64 (unsupported
platform/libc), 65 (artifact mismatch), or 69 (missing package/start failure).

The TypeScript/Node entry is `npm install @actql/node`. Python distribution is
deferred. This preview does not establish browser or managed Cloud support,
live-service coverage for every provider, or the complete Debug/fault matrix.
Unsupported platforms never receive another platform's binary.
