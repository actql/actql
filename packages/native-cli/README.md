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

Embedded Local permits one active Host per state directory and refuses a
second owner. For concurrent CLI processes, start one authenticated public Host
explicitly and connect each CLI using Remote HTTPS/mTLS. The Host owns the
project's storage, and the CLI clients submit queries and read Saved results
through that connection. See the [shared Host setup](https://github.com/actql/actql/blob/main/docs/design/shared-cli-host.md#existing-execution-and-transport-owners).

For Remote mode, supply a Host URL, connection file, scoped token file and mTLS
credentials.

```sh
actql --endpoint https://host.example/ \
  --connection-root "$PWD" --connection-file connection.json \
  --token-root "$PWD" --token-file token.txt \
  --http-library "$ACTQL_HTTP_LIBRARY" \
  --ca ca.crt --cert client.crt --key client.key connect
```

Set `ACTQL_HTTP_LIBRARY` to the absolute path of the installed `libcurl.so.4`
on Linux or `libcurl.4.dylib` on macOS. For the shared route, use the library
admitted as the package's `remote-http` member and pass that path explicitly
with `--http-library`. Runner registration and execution grants come from the
Host. Protect the token, keys and saved operation references. See the
[Remote transport options](https://github.com/actql/actql/blob/main/src/cmd/native_client/README.md).

Save a candidate Submission reference from `new-submission --request-id <nonce>`
and an invocation attempt ID. Use `--request-name <name>` on Remote `start` or `aql` with
`--submission-ref-file`, `--operation-attempt-id` and an explicit format.
On `observed`, save `outcome.submissionRef` as the original, including its
epoch, and save the Run reference when ready. A name bound to different input
returns `conflict`. After a lost response, use
`lookup-submission` with the saved original, or the candidate if no original
was returned. A candidate for an already-bound name may remain unresolved.
Keep its reference and attempt for lookup without resending.

| Operation | Native CLI |
| --- | --- |
| connect; new submission | `connect`; `new-submission` |
| Program/source submit | Local project `run`; Remote `start`/`aql` with explicit format, saved submission reference and explicit invocation attempt ID |
| Static Effect Explanation | Local project `explain <program> --explanation-json` returns the original Plan, Facts and Context. Use `--explanation-language en` or `--explanation-language ja` for text. Both require current Run-read permission. |
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
