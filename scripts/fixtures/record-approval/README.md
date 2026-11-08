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

Keep the complete Account configuration identity consistent between the Host
and its installed Source/Effect Site. A provider-only subset and a Host
configuration with extra rules are different configurations, even when their
provider rights agree. The Site checks the original Checkpoint dispatch facts
against its actual configuration. For owned loopback tests,
`host-account.fixture.mjs` preserves the explicit provider rules, adds only the
named test principal's Host submit/read rules and returns one wire to share.
It does not validate policy or issue any decision or grant.

The maintained HubSpot and kintone installed fixtures share
`installed.fixture.mjs` and `installed-child.mjs` for bootstrap, fresh state,
three-process command execution and live descriptor observation. Each sibling
supplies its original provider protocol, metadata, numerical fixture limits
and Source/Effect profile DATA. They use the same full Account wire on both
sides; Form/revision checks and HubSpot dispatch markers remain distinct.

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

For a reproducible ordinary mock consumer using an already closed normal
installation, the same bounded runner accepts one explicit selection at a time:
`scripts/test-packed-hubspot-source.mjs ORIGINAL_SOURCE NORMAL_RELEASE_DIRECTORY CLOSED_APPLICATION --mock-salesforce-approval`
(or `--mock-hubspot-approval`, `--mock-kintone-approval`). Use absolute paths,
preserve scratch and clear ambient loader/local-profile overrides as described
by the installed fixtures. The normal release Source/archive/installed-member
checks are retained; no build, npm install or provider call is made.

Each selected case writes only a fresh declared mock project, runs `check`
without creating Host state, then uses three separate processes for capture,
explicit default Local approval and Saved-first recovery. It compares the
entire authored mock data before and after every phase, including the untouched
control row. The shared child observes exact canonical Host root descriptors
twice while alive after public close returns; mock has no Credential root to
observe. Each child retains the original 30-second limit. Keep every original
state and receipt after failure; never retry that original Run to finish a case.

## CI producer input

The ordinary CI producer emits `packed-client-packages.json`, not a release
manifest. After the existing exact-artifact download action sets
`ACTQL_PACKED_CLIENT_PACKAGES`, run one explicit case with:

```sh
ACTQL_TEST_PRESERVE_SCRATCH=1 node scripts/test-packed-hubspot-source.mjs --ci --approval
```

Select `--kintone-approval` or a `--mock-CONNECTOR-approval` case in the same way.
This entry requires all five unchanged archives from the exact clean checkout
through the existing `packedClientPackage` gate. Missing inputs refuse; there
is no pack/build fallback or synthetic `release.json`. It installs the original
archives and the source-pinned DuckDB peer normally in fresh external scratch,
checks each installed member against the original archive before and after,
and then executes the same authored fixture. Lifecycle scripts remain enabled.
Keep install output, original inputs, state and receipts on failure or success.
Run on the producer's actual supported platform; a Linux native asset does not
qualify Darwin. This source connection alone is not hosted CI or real-account
acceptance. The existing three-path release/closed-installation entry is retained.
