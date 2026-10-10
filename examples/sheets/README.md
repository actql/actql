# Isolated Sheets installation and acceptance example

This example uses only installed public product exports. It is not a new
Effect scheduler, ledger, authentication service or production account policy.
It creates one ordinary read Program and one two-row approved append Program.
Use a disposable synthetic Spreadsheet, separate numeric read/append tab IDs,
and the [independent cells and permission checklist](../../docs/connectors/sheets-real-service-acceptance.md).
Installation grants neither Google access nor ActQL authorization/approval.

## External installation

Create a private directory outside the repository. Copy `acceptance.mjs` and
`campaign.example.json` there, renaming the latter to `campaign.json`. Supply
the authorized IDs and a unique nonsecret marker. Leave
`appendPermissionConfirmed: false` until the resource owner permits this
campaign's two total rows. Never put keys, bearer tokens or private URLs in
public documentation, commands or receipts.

Use the supported Node version from the release cohort. The recorded campaign
used Node 24.21.0 on macOS arm64. For a supplied verified RC cohort, install all
four archives from that cohort, not a mix of development/release packages:

```sh
npm install --ignore-scripts --offline --no-save --no-audit --no-fund \
  /verified-release/actql-client-wire-0.0.1.tgz \
  /verified-release/actql-sdk-0.0.1.tgz \
  /verified-release/actql-local-node-0.0.1.tgz \
  /verified-release/actql-node-0.0.1.tgz
```

The producer must have run normal prepack and verified its source SHA, runtime
bytes and archive digests using `scripts/package-release.mjs`. Disabling
consumer lifecycle scripts above does not bypass producer generation.
This command describes the tested RC installation, not npm registry availability.
The standard user package is `@actql/node`; the other archives are its fixed
cohort dependencies. A remote-only application uses `@actql/sdk` and does not
install the Local runtime.

## Credentials, TLS and authorization

The adapter consumes an access token through the private
`ACTQL_SHEETS_ACCESS_TOKEN` environment reference. Obtain it using existing
operator OAuth/service-account tooling, with the Sheets scope and explicit
file access. Do not pass the secret as a CLI argument, print the environment
or enable shell tracing. A service-account JSON is not an access token.
Renew an expired token using that same supply path; renewal never permits
repeating an uncertain write.

For the example's local HTTPS server, provide `resource.key`, `resource.crt`
and `ca.crt` under `tlsDirectory`. The certificate must cover localhost /
127.0.0.1. Use existing operator certificate tooling, not a new trust service.
The example adds that CA to the current process's trust only. Public Local
read uses the installed Local Host; HTTPS read/write uses the actual HTTP Host
and SDK, not a fake Google responder.

`setup` generates private Ed25519 Host/reviewer/credential-grant keys and
profiles with exclusive file creation. The grant-signing key is **not** the
Google service-account key. Files remain private to this installation.
The current OS user may read only the configured connection and resources;
append is delegated to a distinct installed reviewer. Target metadata read
is explicitly allowed. The example allows that user's normal Run operations
through the existing account contract. Adapt these rules through the normal
Host authorization installation for production; do not copy a fixture's
all-principals permissions.

```sh
node acceptance.mjs setup
node acceptance.mjs read local normal
node acceptance.mjs read https normal
```

Each read installation is used once. Additional cases are `nullable`, `empty`,
`formula` and `error`; their ranges and independent expectations are declared
in the example. The formula case expects safe refusal for the recorded Google
fixture without an effective value. An API that actually returns evaluated
empty Text differs; inspect that distinction rather than changing the codec
or claiming the recorded refusal proves empty-string success.
Normal reads compare full expected rows, repeat Result reads and repeat the
original submission without another credential use.

## One approved append and separate-process replay

After explicit permission, change only `appendPermissionConfirmed` to true.
Inspect the marker, numeric target and two-row limit before submitting.
Run these commands **once, in order**, as separate processes:

```sh
node acceptance.mjs append-start https
node acceptance.mjs approve https
node acceptance.mjs resume https
node acceptance.mjs replay https
```

The first command publishes the collection Mapping and submits a normal
Values/create Program. It retains the original submission and Run references,
waits at the common Effect Set Checkpoint, and checks zero append credential
uses. Approval resolves that Set using the separate reviewer's installed key;
it does not create per-row approvals. The next process resumes the **same Run**,
checks the independent Named Result and two append uses. Replay captures
credential counts **before opening the Host** and requires all counts unchanged.
All commands close their Client/Host before returning. No internal Owner or
provider factory is constructed by the user.

Credential journal counts are durable use claims, not sole proof of physical
application. Preserve common saved acknowledgements and inspect actual cells
read-only as supplemental evidence. Expected append cells are two equal rows
containing literal Text, Number zero and Boolean false. Position is the last
data row at send time; there is no stable provider row ID or multirow atomicity.
The program refuses NULL and empty Text before send.

If the Run needs reconciliation or a command fails, stop and inspect the
original Run. Do not delete `submission.json` or `run.json` to retry; do not
create another submission, resend an unknown append, infer success from equal
cells or replace the retained installation. Keep the Store, journal, saved
responses and cleanup custody. The two-row permission is campaign-wide, not
per process. Leave test data in place unless the resource owner separately
authorizes deletion. Controlled-service fault injection is not real Google
fault evidence; see the [completed report](../../docs/reviews/2026-10-10-sheets-real-service-acceptance.md).
