# Record update approval consumer fixtures

The shared workflow uses the public Client API for one record UPDATE. A case
supplies its own Program, parameters, expected rows and Review fields. It does
not implement a connector, permission decision, Effect claim or retry policy.

`salesforce-approval`, `hubspot-approval` and `kintone-approval` each contain an authored update and
read Program, a case adapter, a declared-data mock project and a public consumer
entry. Use the same Program files for mock and installed-provider verification;
do not rewrite a Program to hide an unsupported provider operation.

For the original HubSpot and kintone record-update cases, `cases.mjs` also owns
the finite shared fixture selections and before/after/control DATA. The packed
Mock and HTTP fixtures consume the same selected record, unchanged control and
names. Provider envelopes, HubSpot markers/pre-write comparison and kintone
revision conditions remain separate. Existing standalone three-field Mock
selections retain their original control defaults; existing Whole/binary/three-
Source variants retain their original selections. Shared fixture DATA does not
establish that either installed consumer executed or qualify live behavior.

Run `npm ci` in the source checkout to prepare the fixtures. The repository's
prepare step emits their `.mjs` entry points from the `.mts` sources.
Copy `record-approval` and the selected sibling fixture directory with their
emitted JavaScript into an external normal installation of the five Client
packages. The consumer owns a fresh project, installation directory and receipt
prefix. Its configuration is:

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

To supply your own case, replace `selection` with `"casePath": "case.json"`.
The path is resolved relative to the configuration file. Write a UTF-8 JSON
file of at most 1 MiB with these fields.

| Field | Value |
| --- | --- |
| `name` | The authored case name. |
| `effect` | `document`, `format`, `resultName`, `parameterDeclarations`, `parameters`, and `expectedRows`. Optionally supply `additionalResults` keyed by Result name. |
| `read` | The same document, format, Result name, and parameter fields, with independent `beforeRows` and `afterRows`. |
| `review` | The exact expected `target`, `identity`, `before`, and `changes` from the one-row UPDATE Review. |

Use `aql`, `sql`, `json`, or `yaml` for `format`. Provide `document` as text or
replace it with `documentPath`, the name of a regular UTF-8 file alongside the
case. The total input and the resulting case each fit within 1 MiB. Keep
connection, operator and signing settings in the separate
configuration. All three phases read the authored case. The original receipt
binds both documents, their parameters and the oracle before approval or Saved
recovery. Keep the case available for each phase.

The installed HTTP fixture may also use a `fixture` object in the case file.
Provide a `seed` with `recordId`, `previousName`, `controlId`, and `controlName`.
Independently specify `expected.before` and `expected.after`, each containing
`target` and `control` records with `id` and `name` fields. Pass `casePath` and
the existing provider's installation factory as `createInstallation` when
calling `runInstalledRecordApprovalFixture`. The runner binds the seed and
expectations to the same Run receipt and checks them against the provider
observations. The standalone phase commands use the independently supplied
connection and check the Program and Review oracles.

Include `fixture.schema` with `sourceRef`, `sourceViewContractCid`, and
`carrierSchemaContractCid` to pin the selected provider schema. The installed
fixture compares all three with the checked Source View before starting the
Run. Phase commands require the matching installed fixture for a pinned case.

An installed HTTP case may set `fixture.faults` to an empty array or one
`{"kind":"apply-then-lose-reply","expected":{"approveStatus":"needs_reconciliation","lookupStatus":"needs_reconciliation"}}`
entry. The existing provider adapter selects the exact write route. The case
supplies the outcomes to check, and the ordinary fixture observes the original
approval and lookup replies. Use a single fault selection. Standalone phase
commands refuse a scheduled fault without the matching installed fixture.

Set `ACTQL_RECORD_APPROVAL_MOCK_CASE` to the absolute path of a case file to
run it with the existing `--mock-hubspot-approval` or `--mock-kintone-approval`
packed fixture. The Mock uses the same authored Program, parameters, seed,
Review, and expected states. It constructs the existing Mock catalog for the
selected connector. The installed HTTP adapter checks the provider schema and
applies the HTTP fault schedule in its own run.

The standard HubSpot and kintone packed fixtures use their respective
`case.json` for both HTTP and Mock. Each references that adapter's existing
`update.aql` and `read.aql` files.

Capture saves the actual reference before waiting, checks the sealed Review,
and reads the unchanged target. Approval is an explicit phase and must commit
before waiting for the same Run's exact named Result and reading the new target.
Recovery reads that original named Result before status, with no new submission
or approval. Receipt binding includes both Program digests, parameters and the
independent expected values. Receipts are created exclusively; retain a failed
attempt and use new state for a distinct attempt.

The original capture wait, approval status and post-approval wait replies retain
their bounded public status/diagnostic before the success assertions. An actual
`needs_reconciliation` reply stays Unknown and fails this success-only case;
it does not permit a Result read, another submission or another approval. A
thrown wait keeps its original exception and creates no wait-observation
receipt. These receipts are diagnostic DATA, not execution or recovery authority.

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


## Rejecting the original checkpoint

Append `--reject` to the installed `--approval` or `--kintone-approval`
selection to run the same Program and provider fixture in a fresh project.
The three processes capture, reject, and then look up the original cancelled
Run. The parent checks the entire target and control and counts every selected
write request across the three phases. Both rows remain unchanged and the
write count remains zero.

For the separate consumer commands, set `"decision": "rejected"` in the fresh
configuration before capture and use `reject` as the second phase. The signed
rejection must identify the original checkpoint and Run. The final `recover`
phase reads the original cancelled status without reading an Effect Result or
submitting another resolution.

## Applied update with a lost reply

Each provider fixture exposes `writeRequest` from its actual existing write
route. `recordUpdateReplyLossFaults(provider)` snapshots that finite method and
pathname into the existing HTTPS fixture's one-shot `apply-then-lose-reply`
fault. An explicitly selected installed fault consumer may supply this array as
`fixture.faults`; the default successful workflow retains an empty fault list.
No fault chooses a credential, egress grant, claim, Run status or retry policy.

The shared real-TLS component sends one synthetic protocol request, observes
connection reset without a response, and independently checks one actual fixture
mutation plus the unchanged control row. HubSpot retains its dispatch marker and
pre-write comparison meaning; kintone retains its original conditional revision
and exact String identifiers. Neither gains the other's atomicity guarantee.
The ordinary runner and these direct controls call the same thin
`openRecordApprovalExchange` fixture entry; the existing shared server,
certificates and route assertions are reused unchanged.

This TLS component closes only the transport fixture/oracle seam. A single
test-driver request is not proof of product no-resend, and observed backend
mutation is not a public Result, success receipt or cleanup ACK.

The existing ordinary `--approval` and `--kintone-approval` entries can now select
this one fault using the trusted fixture-only environment variable
`ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION`. It is a bounded JSON object with
exactly `approveStatus` and `lookupStatus`; each is `succeeded` or
`needs_reconciliation`. Choose each expectation from the actual selected
provider capability/source contract before the attempt, independently of the
returned state. These inputs cannot be supplied by the Program and grant no
approval, permission, reconciliation or send. They are snapshotted into the
original Program/oracle binding and must remain exact across all three processes.
No variable means the unchanged successful Saved-first case. An incompatible
selection refuses; this is not a product outcome whitelist.

In the loss case, capture still seals and independently reviews the original
Checkpoint before any write. Approval retains its returned committed resolution
separately from the actual post-approval Run state. An expected Unknown creates
no successful `approved` receipt and reads no Result. A fresh process attaches
only that SAME original reference and performs one status lookup. It never
submits, approves, resumes or manually reconciles another operation. A Result is
read and checked against the original independent oracle only after actual
`succeeded`; an expected Unknown remains unresolved. A thrown or unexpected
reply stays failed and keeps its original observation/primary cause, with
first-close failure preserved separately.

The parent observes the real provider target and entire unchanged control after
every phase, consumes exactly one selected loss fault, and counts actual write
requests (including rejected duplicate attempts). Capability-specific reads
during a lookup are allowed; another write is not. HubSpot's marker and prewrite
comparison do not become kintone's conditional revision, and a changed revision
or matching value alone is never converted by this fixture into a known outcome.
Existing default lifecycle, package/installed-byte checks, three original
30-second child bounds, first-close and alive scoped-FD observations remain.

The consumer flow is source/component-qualified only until the selected exact
normal installation actually executes it. Client-double controls, raw TLS
controls and the ordinary Host case remain distinct. This source does not prove
either provider's ordinary lost-reply outcome, Saved success or physical stop,
and it never reopens an old failed business state.
