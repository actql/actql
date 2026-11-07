# Record update approval consumer fixtures

The shared workflow uses the public Client API for one record UPDATE. A case
supplies its own Program, parameters, expected rows and Review fields. It does
not implement a connector, permission decision, Effect claim or retry policy.

`salesforce-approval`, `hubspot-approval` and `kintone-approval` each contain an authored update and
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

Run `check` with the same arguments first to validate the configuration and the
connector's original selection contract without connecting or creating receipts:

```sh
node /external/fixtures/hubspot-approval/run.mjs check /fresh/consumer.json /fresh/receipt
```

The three launchers share `record-approval/command.mjs`. `check` does not load an
operator module or signing key, inspect the remote account, admit the Program,
or prove that the installation/state/receipt prefix is fresh.

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
`privateKeyPath` is absolute or relative to the configuration file's directory.
Capture and recovery never open this approval key; the explicit approval phase
opens it only after the workflow rechecks the same original sealed Review.

An installed connection needs function-valued authorization and secret ports
which cannot be encoded in JSON. Set `operatorModulePath` to an explicitly
trusted local module, absolute or relative to the configuration file. It exports
`configureConnection(options)`, returning the ordinary `connect` options with
the operator's existing `installation.authorization`, `resolveSourceSecret`
and `resolveEffectSecret` callbacks. The launcher imports this executable
configuration only for capture, approval or recovery, before connecting. It
does not supply permission decisions or turn a secret reference into a grant.
Do not copy a test callback that always allows access into a real installation.

See the [kintone preparation checklist](../kintone-approval/README.md) for the
original record/field contract and the inputs still needed from a real account.

The external acceptance harness must independently observe the provider/mock
target before approval, after approval and after recovery, including an unchanged
control record. It must verify the installed payload before and after, and
observe the original still-live child after public `client.close()` returns.
Process exit alone is not close acknowledgement or an alive FD observation.

The pure workflow contract tests are included by the existing `client-ci.test.mjs`
suite. They check consumer sequencing and failure preservation with an explicit
fake Client; they do not establish provider authentication, physical writes or
ordinary installed support. A declared mock UPDATE likewise does not establish
that a connector's standard installed Effect factory is connected. The kintone
fixture retains string `$id` values without numeric conversion; its normal
installed Effect connection is a separate requirement from mock acceptance.
