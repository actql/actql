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

The conformance preparation uses the existing `openHttpsExchangeFixture` to
supply an own TLS origin before generating the definition. Only that transport
input replaces the reserved origin. Program fields, response bodies and row
oracles stay authored independently. Normal packages and the actual C reader
service must be from one coherent source; no existing installed software is
retagged or overlaid. First successful read precedes reporting author file/LOC,
command/time, Core-delta and callback metrics.

The fixture has explicit empty, one-page, two-page, provider-error, cursor-cycle
and byte-limit DATA modes. Their existence is preparation, not executed
runtime coverage. Multiple connections/current/cancel/cleanup and first-close
facts must be recorded by the same installed Host conformance caller.
