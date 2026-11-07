# Record update approval consumer fixtures

The shared workflow uses the public Client API for one record UPDATE. A case
supplies its own Program, parameters, expected rows and Review fields. It does
not implement a connector, permission decision, Effect claim or retry policy.

`salesforce-approval` and `hubspot-approval` each contain an authored update and
read Program, a case adapter, a declared-data mock project and a public consumer
entry. Use the same Program files for mock and installed-provider verification;
do not rewrite a Program to hide an unsupported provider operation.

Copy `record-approval` and the selected sibling fixture directory into an
external normal installation of the five Client packages. The consumer owns a
fresh project, installation directory and receipt prefix. Its configuration is:

```json
{
  "selection": {
    "recordId": "selected-test-record",
    "previousName": "Before approval",
    "nextName": "After approval"
  },
  "connect": {
    "mode": "local",
    "installation": {"directory": "/absolute/fresh/project/.actql"},
    "profile": "mock"
  }
}
```

For mock, write the selected fixture's `mockProjectFiles(selection)` into that
fresh project before connecting. Run each phase from the project directory in
a separate process, with the same configuration and receipt prefix:

```sh
node /external/fixtures/hubspot-approval/run.mjs capture /fresh/consumer.json /fresh/receipt
node /external/fixtures/hubspot-approval/run.mjs approve /fresh/consumer.json /fresh/receipt
node /external/fixtures/hubspot-approval/run.mjs recover /fresh/consumer.json /fresh/receipt
```

Capture saves the actual reference before waiting, checks the sealed Review,
and reads the unchanged target. Approval is an explicit phase and must commit
before waiting for the same Run's exact named Result and reading the new target.
Recovery reads that original named Result before status, with no new submission
or approval. Receipt binding includes both Program digests, parameters and the
independent expected values. Receipts are created exclusively; retain a failed
attempt and use new state for a distinct attempt.

Without `signer`, approval uses the existing default Local signer. A configured
operator can supply `signer: {keyId, reviewerId, privateKeyPath}` for the existing
signed resolution API. These inputs do not grant a connector Account or provider
permission. Keep real credentials outside the fixture and receipt files.

The external acceptance harness must independently observe the provider/mock
target before approval, after approval and after recovery, including an unchanged
control record. It must verify the installed payload before and after, and
observe the original still-live child after public `client.close()` returns.
Process exit alone is not close acknowledgement or an alive FD observation.

The pure workflow contract tests are included by the existing `client-ci.test.mjs`
suite. They check consumer sequencing and failure preservation with an explicit
fake Client; they do not establish provider authentication, physical writes or
ordinary installed support. A declared mock UPDATE likewise does not establish
that a connector's standard installed Effect factory is connected. In particular,
the HubSpot fixture does not supply that missing installation entry.
