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
six cases use synthetic package/digest and provider DATA without importing
normal software or creating a Host, keys or TLS server. The separate
`conformance.test.mjs` caller-mechanism cases currently require Darwin
`/usr/sbin/lsof` for their same-process scoped descriptor observations; they
are not registered in the Ubuntu distribution job. Those mechanism cases
do not qualify the normal case or establish a portable descriptor observer.
The prepared ordinary case retains that same explicit observation dependency.
