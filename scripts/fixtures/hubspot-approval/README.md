# HubSpot record approval fixture

Use the original `update.aql` and `read.aql` with the
[shared record workflow](../record-approval/README.md). The same authored
Program selects one company's native string `id`, reviews `name`, explicitly
approves one UPDATE and reads the same saved Result before status on reopening.

## Prepare a real account

Keep these inputs outside the checkout and share their paths, not secrets:

- The selected development account's native portal ID and API origin, matching
  the installed Site and original metadata. Keep company IDs as strings. Use
  the company's native record ID, not its domain or another unique property;
  this fixture's Program selects `id`.
- One explicitly writable test company, its independently observed current
  `name`, and a distinct permitted next `name`. Also select a different control
  company that must remain unchanged. The operator observes both companies
  independently before capture, after approval and after Saved recovery.
- An existing writable string marker property, selected as `markerProperty`
  in the Effect profile (for example `actql_request_id`). Its original Catalog
  and Mapping must admit it. This workflow creates no company or property,
  grants no schema permission, and selects no UPSERT or other write operation.
- The normal installed Source and UPDATE Effect profiles, using alias
  `hubspot.companies`, resource/object type `companies` and business field
  `name`. Keep their metadata, profile generation, namespace and runtime
  together across all three processes. Use the operator's actual bounded
  profiles; the small synthetic fixture limits are not a real-account profile.
- The selected account's existing access token through the Site profile's
  `tokenEnvironment`. Both installed HubSpot factories already resolve this
  environment variable when no secret callback is supplied. A custom secret
  callback is optional, and its presence grants no resource access. Keep the
  token out of the Program, JSON configuration, receipts and source tree.
- Existing provider permissions for Account details, company property reads,
  company list/batch reads and company batch UPDATE, plus the separate current
  ActQL Account/Credential grants. Check every endpoint used by this route:
  `GET /account-info/v3/details`, `GET /crm/v3/properties/companies`,
  `GET /crm/v3/objects/companies`, and the `POST` company `batch/read` and
  `batch/update` endpoints. A valid token or a successful company read alone
  does not establish these other rights. See HubSpot's
  [company API](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/companies/guide)
  and [property API](https://developers.hubspot.com/docs/api-reference/legacy/crm/properties/guide).
- The SAME complete admitted Account configuration wire in the Source Site
  and Host authorization, including their actual provider/Host rules. Do not
  copy the synthetic fixture's policy or replace it with a blanket allow.
  The original Checkpoint and dispatch configuration identity must agree.
- The installation's actual Host signing configuration and an already
  admitted reviewer/signing key. Supplying a key path creates no authority.

Use the [shared configuration format](../record-approval/README.md). For an
existing real installation, a consumer configuration can select these inputs:

```json
{
  "selection": {
    "recordId": "123456789",
    "previousName": "Authorized test company before",
    "nextName": "Authorized test company after"
  },
  "connect": {
    "mode": "local",
    "installation": {
      "directory": "/absolute/fresh/hubspot-host",
      "sourceProfilePath": "/absolute/operator/hubspot-source.json",
      "effectProfilePath": "/absolute/operator/hubspot-effect.json"
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

`operator.mjs` is the selected installation's trusted configuration, not the
loopback token resolver. Its existing `configureConnection(options)` supplies
the Host's authorization/signing callbacks. The provider secret can use the
existing environment port above. Do not add a second authorization decision or
replace the admitted Account to make the fixture proceed.

Copy this directory and `record-approval` into the external normal consumer.
Run `check` first; it validates authored input shape without connecting,
importing the operator, reading keys, obtaining a token or proving any provider
permission. Then use fresh state for the explicit sequence:

```sh
node /external/fixtures/hubspot-approval/run.mjs check /fresh/consumer.json /fresh/receipt
node /external/fixtures/hubspot-approval/run.mjs capture /fresh/consumer.json /fresh/receipt
# Inspect the actual original sealed Review before approving this exact change.
node /external/fixtures/hubspot-approval/run.mjs approve /fresh/consumer.json /fresh/receipt
node /external/fixtures/hubspot-approval/run.mjs recover /fresh/consumer.json /fresh/receipt
```

Capture must not mutate the target; approval must produce the same original
Run's exact Result. Recovery must read its original Saved Result before status,
without submitting or approving again. Keep the first unexpected failure or
Unknown and its new state. Stop rather than resending, widening permissions,
changing limits or reopening a failed original. Record the real public close
separately from live FD observations and provider outcome. A real-account pass
is separate from the mock, loopback TLS and CI observations below.

### OAuth operator setup

When using an OAuth app, `oauth.mjs` receives the original authorization
callback on the registered localhost redirect and exchanges its one-use code
through HubSpot's [v3 token API](https://developers.hubspot.com/docs/api-reference/legacy/authentication/manage-oauth-tokens).
It preserves the selected install URL's scopes, checks a fresh `state`, sends
the secret only in the token request body, and writes tokens exclusively to a
private `0600` file. Token values and callback codes are never printed. The
helper obtains credentials only; it does not grant ActQL access or apply an
Effect. Keep the operator configuration, secret, install URL and token output
outside the checkout:

```json
{
  "clientId": "existing-app-client-id",
  "clientSecretFile": "/private/operator/client-secret",
  "redirectUri": "http://localhost:18763/oauth-callback",
  "tokensFile": "/private/operator/new-tokens.json"
}
```

Register that exact redirect in the app, store only the secret value in its
private file, and store the selected app's install URL in a separate file.
Run `node /external/fixtures/hubspot-approval/oauth.mjs CONFIGURATION INSTALL_URL_FILE`.
On macOS this opens the browser after the callback listener is ready. The
operator chooses the development account and grants the selected scopes;
authorization may refuse if the app's actual configuration differs. The
result contains only account/expiry/output-path metadata. Use the saved
access token through the existing installation secret port; do not paste it
into the Program or chat. OAuth success does not prove company rights, Host
admission, approval, UPDATE or Saved recovery. This helper does not implement
token refresh or overwrite a previous token file.

## Owned TLS provider

`provider.mjs` supplies only synthetic Account/property/record responses and
protocol assertions for an owned local TLS server. It never implements the
product Account, Credential, approval, dispatch claim or cleanup. It checks a
credential header's presence, not a real HubSpot token's validity. Provider
authentication and real-account permission acceptance remain separate.

The synthetic Catalog declares `name` and an existing writable string
`actql_request_id` marker. The Effect profile selects business field `name` and
that distinct marker property; it creates neither a provider property nor an
UPSERT capability. The update route requires the exact selected company and
new value, the logical request CID as `objectWriteTraceId`, and the dispatch
marker CID in the same physical body. It accepts only one original write.
The independent control company remains unchanged. Wrong targets, changed
values, missing/malformed markers and additional fields refuse before mutation.

Metadata, target reads and update use their original installed Site, declared
Resources and current checks. For the owned fixture, derive one complete
Account wire with `recordApprovalHostAccountConfiguration` and pass that same
wire to the Source profile and Host authorization. Do not pass a provider-only
subset to one side: the original Checkpoint's configuration identity must
match the Site that later issues its grant. This is caller configuration,
not permission to weaken the product's identity check.

Capture must show the sealed original Review and leave the provider unchanged.
Only the explicit approval phase may send the marked update. Separate-process
Saved recovery must perform no provider request or resend. Keep the first
unexpected failure and its fresh state; no missing response or timeout proves
absence, nonacceptance or cleanup acknowledgement. Record each actual public
close and observe live state/Credential descriptors independently.

## Reproduce with an existing normal installation

From the consumer checkout, run the existing bounded local-check wrapper with
`scripts/test-packed-hubspot-source.mjs ORIGINAL_SOURCE NORMAL_RELEASE_DIRECTORY CLOSED_APPLICATION --approval`.
All three paths must be absolute. Set `ACTQL_TEST_PRESERVE_SCRATCH=1` and clear
ambient `NODE_PATH`, `NODE_OPTIONS`, `ACTQL_LOCAL_SOURCE_PROFILE` and
`ACTQL_LOCAL_EFFECT_PROFILE`. The original Source must be clean and match the
normal release manifest. The runner verifies archives and every installed
member before and after, including a failed functional attempt; it builds and
installs nothing. The default selection still runs the two existing Source
cases; `--approval` selects only this one distinct three-process case.

The shared `record-approval/installed.fixture.mjs` and `installed-child.mjs`
serve both HubSpot and kintone; this sibling supplies only its independent
provider protocol and profile DATA. The fixture uses the selected installed runtime's original initialization
owner to obtain the declared alias, then closes that preparation before the
public workflow. Each child keeps its original 30-second whole-process limit.
Capture, approval and recovery use separate processes and fresh explicit HOME,
Host and Credential roots. Both live descriptor snapshots include each exact
root and its descendants, with physical path aliases resolved, using `lsof` on
macOS or `/proc/self/fd` on Linux. An unavailable observer fails explicitly.
These observations do not constitute a physical cleanup acknowledgement.
Keep the printed original root and its state, receipts, stdout, stderr and
summary on every outcome; never reopen a failed state merely to retry.
