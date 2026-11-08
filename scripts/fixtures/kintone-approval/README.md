# kintone UPDATE: prepare a real account

Use the original `update.aql` and `read.aql` for the mock, local TLS provider
and real account. This consumer checks one selected record's `Subject` change;
it does not claim support for every kintone operation or create an account.
The [shared workflow instructions](../record-approval/README.md) describe its
three fresh processes and original Run/Review/receipt custody.

## Required account and installation inputs

Prepare these outside the source checkout:

- The HTTPS origin, app ID and any configured guest space, matching the
  installed Source, Effect, Site and current published Form metadata.
- A writable `SINGLE_LINE_TEXT` field with field code `Subject`. The selected
  record's native `$id`, current Subject and a distinct intended Subject are
  independent inputs. Keep `$id` as a string; a display record number is not
  a replacement for the native key.
- A different control record with a known Subject that must remain unchanged.
  The external acceptance operator observes it independently before approval,
  after approval and after Saved recovery.
- The existing published Source and UPDATE Effect profiles, selected together
  in a fresh normal Host installation. Use the Source alias
  `kintone.inquiries`, resource `inquiries`, and UPDATE field `Subject`.
- The installed operator's existing Account/Credential/authorization bindings
  for Form reads, record reads and record UPDATE, with currentness checks.
  An API token is stored through the configured secret port/environment, never
  in the Program, fixture JSON, receipt or source repository.
- An existing authorized reviewer/signing key for the configured operator.
  Its public key and reviewer must already be admitted by that installation;
  supplying a key path here grants no approval authority.

The vendor's [Get Form Fields](https://kintone.dev/en/docs/kintone/rest-api/apps/form/get-form-fields/)
API supports API-token authentication and requires permission to view or add
records for a live app. Updating a record additionally requires the relevant
record and field update permissions; see
[Update Record](https://kintone.dev/en/docs/kintone/rest-api/records/update-record/).
These vendor rights do not replace the separate ActQL Form/read/write grants.

## Consumer configuration

Copy both `kintone-approval` and `record-approval` into a fresh external ordinary
installation of the five Client packages. Keep this configuration in that
consumer, not in the package or source checkout:

```json
{
  "selection": {
    "recordId": "123",
    "previousName": "Before approval",
    "nextName": "After approval"
  },
  "connect": {
    "mode": "local",
    "installation": {
      "directory": "/absolute/fresh/project/.actql",
      "sourceProfilePath": "/absolute/operator/kintone-source.json",
      "effectProfilePath": "/absolute/operator/kintone-effect.json"
    }
  },
  "operatorModulePath": "operator.mjs",
  "signer": {
    "keyId": "existing-review-key",
    "reviewerId": "existing-reviewer",
    "privateKeyPath": "keys/reviewer.pem"
  }
}
```

`operator.mjs` is trusted local executable configuration. Its named export
`configureConnection(options)` adds the installation's existing authorization
and secret callbacks and returns the ordinary public Client connection options.
Reuse the operator implementation that published these profiles; the fixture
does not fabricate one. Keep the selected app, credentials, profile generation
and namespace consistent across all three processes.

From the fresh project directory, validate the authored inputs first:

```sh
node /external/fixtures/kintone-approval/run.mjs check /fresh/consumer.json /fresh/receipt
```

`ready` proves configuration/selection shape only. It makes no provider call,
imports no operator module, reads no signing key and creates no Run or receipt.
It does not prove that the supplied operator, installation or remote app works.

## Explicit execution sequence

```sh
node /external/fixtures/kintone-approval/run.mjs capture /fresh/consumer.json /fresh/receipt
# Inspect the original sealed Review before explicitly approving the update.
node /external/fixtures/kintone-approval/run.mjs approve /fresh/consumer.json /fresh/receipt
node /external/fixtures/kintone-approval/run.mjs recover /fresh/consumer.json /fresh/receipt
```

Capture saves the real reference before wait, requires a waiting Checkpoint,
checks the complete original Review and reads the unchanged Subject. Only the
separate approval command may apply the update. Recovery reads the same saved
Result before status and performs no new submission, approval or resend.

Stop at the first unexpected failure or Unknown. Preserve that fresh state and
its exclusive receipts; do not retry a failed phase or replace the original
Run. Observe the external control record, installed payload and live process
FDs separately. A returned public close is not a physical provider ACK, and
process exit is not an alive-FD observation. Configuration readiness, mock and
TLS passes remain distinct from real-account acceptance.

## Reproduce the owned TLS provider case

The maintained `packed-kintone-approval.mjs` uses this same Program pair and
the same shared installed fixture/command/workflow as HubSpot. It checks the
original string `$id` and `$revision`, exact `Subject` payload and explicit
`upsert: false`; a different control record remains unchanged. Its fixture
Form comes from the existing kintone UPDATE Form fixture, including writable,
option-valued and computed fields. A credential header's presence is observed,
not the validity or permissions of a real API token.

Use the existing bounded local-check wrapper to invoke
`scripts/test-packed-hubspot-source.mjs ORIGINAL_SOURCE NORMAL_RELEASE_DIRECTORY CLOSED_APPLICATION --kintone-approval`
with absolute paths. This preserves the original normal release admission,
archive digests and installed-member checks, and selects only the one kintone
three-process case. Set `ACTQL_TEST_PRESERVE_SCRATCH=1`; clear ambient loader
overlays and local Source/Effect profile environment variables. No build or npm
install is performed. Keep the original printed root on every outcome.

Each phase has a 30-second whole-child limit. After the existing public close
returns, two still-live snapshots include exact canonical Host/Credential root
directories and all descendants. The observer does not acknowledge physical
cleanup. The setup closes its real installed Source bootstrap before the
public phases; Saved-first recovery must make no provider request or UPDATE.
