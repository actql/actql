# External standard REST author fixture

`connector.json` is the entire handwritten connector implementation. It has
no MoonBit package, Host callback, credential value, reader state machine or
handwritten installation manifest. The optional transform is unnecessary for
this API. `provider.fixture.mjs` contains independent test response DATA and
row expectations; it is not installed author code.

The author projection is generated with the existing script entrance:

```sh
node scripts/connector.mjs build scripts/fixtures/external-rest/connector.json /absolute/output
node scripts/connector.mjs test scripts/fixtures/external-rest/connector.json /absolute/output
```

The second command checks projection freshness only. Neither command proves
that a Source ran, that its account admitted a read, that bytes were charged,
or that a physical resource closed. The shared ManagedReader and original
bounded Common JSON/row projection must be connected before the installed
SDK/real Host conformance case can execute.

The generated package root exports `installedConnectors` through the existing
Host manifest/table generator. Application setup uses the normal public API:

```js
import {installedConnectors} from '@actql-connectors/acme';
import {createInstalledConnectorTable} from '@actql/local-node';
import {connect} from '@actql/node';

const connectorTable = createInstalledConnectorTable(installedConnectors);
const client = await connect({mode: 'local', owner: 'local', installation: {
  connectorTable, sourceProfilePath, directory, authorization,
  resolveSourceSecret,
}});
```

This is the existing nominal table owner, not a new discovery registry or a
test-only Host service. The framework must already contain the matching
standard REST facade and Common exports. A new connector contributes its JS
package and declaration; it needs no per-connector Common compilation or Host
package rebuild. The older external composed-Host build route remains usable.

The conformance preparation uses the existing `openHttpsExchangeFixture` to
supply an own TLS origin before generating the definition. Only that transport
input replaces the reserved origin. Program fields, response bodies and row
oracles stay authored independently. Normal packages and the actual C reader
service must be from one coherent source; no existing installed software is
retagged or overlaid. First successful read precedes reporting author file/LOC,
command/time, Core-delta and callback metrics.

`normal-case.test.mjs` is a prepared ordinary caller, not an executed offer.
It requires `ACTQL_REST_CONFORMANCE_INPUT` naming an explicit descriptor with
`kind: "actql-standard-rest-normal/0.1"`, exact source SHA/tree, normal-five
manifest path/hash, a new output root, an explicit Account input path and one
positive mode (`paged`, `empty` or `one`). It reuses the unchanged physical
family/TLS/process helpers recorded in `shared-fixture-source.json`; it creates
no second Host, issuer or signer. No default installation, state or Run is
selected. The supplied custom CA remains explicit and requires real Host
initialization backing; this caller must stay unexecuted while that input is
missing.

The selected input can name the existing full normal-five inventory manifest,
or the supplier's original qualified offer. A qualified offer must bind its
exact source/tree, successful clean producer, five SHA256/SHA512 identities and
the original `packed-client-packages.json` bytes. The preparation helper uses
the existing archive verifier/unpacker and inventories the original package
payloads in fresh temporary scratch, then removes that scratch. It writes no
replacement manifest and imports no package exports. The ordinary report keeps
both original metadata bindings; installation and payload checks use the same
verified archives. This metadata connection does not admit a Host or qualify
the unfinished normal Source/initialization path.

When deliberately admitted, the parent keeps its own TLS event loop alive,
runs CLI scaffold/build, packs the generated JS connector, and installs the
five selected normal tars plus that package through the default npm lifecycle.
All five offered tar digests are checked before fixture/key creation or npm.
The child uses `@actql/node.connect`, its exact SDK namespace and the installed
connector table. One successful original is then read in a distinct async
Saved child without provider requests or secret resolution. First-close and
scoped descriptor observations remain separate. Fresh configuration, keys,
state and failures are retained. Package/module source aliases are refused.
Once the initial installed inventory exists, its final comparison is attempted
on business failures as well as success. That evidence never substitutes for
the original public close or ordinary row observations.

Metrics are written only after a first successful ordinary Read and close.
They report authored connector files/lines, optional JS/callbacks, actual
commands, automated introduction time and observed Core/Host source diff.
Framework preparation/generated output and unmeasured human typing time are
explicit; these measurements are not latency or performance acceptance.

The fixture has explicit empty, one-page, two-page, provider-error, cursor-cycle
and byte-limit DATA modes. Their existence is preparation, not executed
runtime coverage. Multiple connections/current/cancel/cleanup and first-close
facts must be recorded by the same installed Host conformance caller.

## Source checks and platform scope

The generic distribution command selects `preparation.test.mjs` only. Its
preflight cases use synthetic package/digest and provider DATA without importing
normal software or creating a Host, keys or TLS server. The separate
`conformance.test.mjs` caller-mechanism cases currently require Darwin
`/usr/sbin/lsof` for their same-process scoped descriptor observations; they
are not registered in the Ubuntu distribution job. Those mechanism cases
do not qualify the normal case or establish a portable descriptor observer.
The prepared ordinary case retains that same explicit observation dependency.


## Opt-in cancellation and construction controls

`cancel-normal-case.test.mjs` consumes the same explicit descriptor as the
positive normal case, with `mode: "paged"`. It holds the original second
cursor response through the existing asynchronous HTTPS handler, captures
the admitted original Run, and sends one public cancellation with its observed
control revision. Acceptance, the later `cancelled`/physical-stop observation,
and the first public close and live descriptor observations are independent.
The barrier releases only after the original cancellation returns; it is test
scheduling, not cancellation authority or a product fault flag. No Result or
successful Saved claim is made by this case.

`construction-normal-case.test.mjs` creates two distinct absolute files with
identical valid generated Source-profile bytes and supplies them through the
existing public `sourceProfilePaths` installation input. Its closed authored
`constructor-oracles.json` identifies the expected duplicate-binding primary.
It records the actual initialization error, original cause/primaryFailure,
cleanup-pending value and exposed handle presence without invoking a handle.
A generic initialization error is not the selected primary or proof of
nonacceptance. With no returned Client, there is no public close call or ACK.
Live scoped descriptor observations after rejection remain separate; absent
roots are recorded as absent and never counted as empty descriptor proofs.

The shared installed-module preflight forces the lazy generated installation
to load and checks its four original exports before Host construction. Its two
portable mechanism fixtures import synthetic packages only and create no Host,
keys, TLS or normal software. They stay in the already selected
`preparation.test.mjs`; no package-command or workflow registration is added.

The two new ordinary controls are explicit artifact consumers. Select one file
through the existing bounded/nonzero local-check wrappers, with
`ACTQL_REST_CONFORMANCE_INPUT` bound to an actual same-source normal-five
manifest, fresh output and explicit Account inputs. Retain artifact verification,
the default npm lifecycle, actual source qualification and original failure
records. Do not substitute a checkout module, replacement manifest, old failed
state or a claimed cleanup result.

Both ordinary controls retain the current Darwin `/usr/sbin/lsof` observation
dependency, Node/npm/openssl tooling and a live parent-owned TLS event loop.
They are not selected by default package commands or Ubuntu CI. The existing
`check:distribution-client` selection remains `preparation.test.mjs` only;
that source/preflight coverage cannot establish these ordinary lifetimes.
Publishing caller sources does not supply matching runtime artifacts, qualify
current-main ordinary execution, or make the fixture's diagnostic tag a new
stable public error contract.
