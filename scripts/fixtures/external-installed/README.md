# External installed Read and Effect fixtures

These are two independent MoonBit modules and npm packages. Neither module
contributes Compute. The Read module has only a `source` entry in its ordinary
`host-bundle.json`; the Effect module has only an `effect` entry. The manifests
use the established `src/connectors/<registration>` and
`adapters/connectors/<registration>/host` layout and existing installed Host
manifest format. There is no fixture-specific registration path.

| Role | MoonBit module and pin | npm package | Registration |
| --- | --- | --- | --- |
| Read | `fixture/external_read@0.0.1` | `@fixture/external-read@0.0.1` | `external_read` |
| Effect | `fixture/external_effect@0.0.1` | `@fixture/external-effect@0.0.1` | `external_effect` |

Both modules explicitly import `actql/actql@0.0.1`. Their JS foreign-library
packages import `actql/actql/source_value` for bounded JSON parsing that rejects
duplicate keys and preserves external strings. They implement their own small provider protocol; neither wraps
GitHub, Salesforce, nor an existing provider driver. Package installation runs
no network or setup hook; `prepack` only checks the authored adapter's syntax.

The build resolves these trusted module roots using the ordinary external
module mechanism and builds each foreign library at
`connectors/<registration>/host_node`. The composed Host selects both installed
manifests through the existing generator. Its Node distribution preserves
`@actql/local-node` as the common owner, so the external adapters' imports of
`@actql/local-node/connector-installation` refer to that same Host package.

The installed loader supplies the original bound `construction` to each
adapter. Both fixtures use it for accounted configuration reads, authored
declaration/Mapping preparation, Site acquisition and final adapter creation.
The same Host owner retains these originals and any failed prefix; an adapter
cannot replace that association by calling an independent public constructor.

## Provider boundary

The independently linked providers exchange only byte arrays, strings and
integers. Provider exports never accept a common runtime opaque handle. The
injected `moon` owns declarations, Mappings, acquisition, capture, credentials,
Effect claims and recovery. `providerMoon` owns only the following pure ABI:

The consumer's explicit HTTPS port uses Node Readable and Writable lifecycle
events, including observed binary reads and request close after response close.
It exercises the original Credential receiver without opening a socket or
supplying a physical socket cleanup acknowledgement.

- Read: `externalReadRequestJson(page)` constructs one of two fixed paths.
  `externalReadPageJson(bytes, page)` projects `items` to declared rows and
  admits only `next: 1` from the first page or `next: null`. Each page permits
  at most two rows, 4,096 bytes, 32 nodes and depth four. The common acquisition
  independently caps the run at two pages and four captured rows.
  The bound constructor retains the standard managed page reader and its
  implementation capacity before Source admission. Shared reader custody owns
  Credential binding, current checks, byte charging and cleanup; the external
  module supplies only synchronous request and page projections.
- Effect: `externalEffectRequestJson(key, note)` constructs the exact bounded
  create body. `externalEffectObservationJson(status, bytes, key)` admits only
  a matching typed 201 success or the declared 400 refusal. All other replies
  remain unclassified. Response parsing is capped at 4,096 bytes, 16 nodes and
  depth three. The Node adapter gives the common ledger the exact request CID.

The Effect package's `catalog-views.json` supplies the finite resource schema
required by the common Mapping declaration API. This is catalog metadata,
not a Source installation: the package has no source manifest entry, read
driver, read hook or Read adapter. The fixture creates values locally and
offers only the `events` create Mapping, with approval required.

## Consumer

The packed harness copies `consumer.mjs` into the fresh consumer and invokes:

```js
await verifyExternalInstalledFixture({
  directory,
  installedConnectors,
  providerBundleUrl,
});
```

The supplied table and resolver are the normal generated Host table and
resolver. The consumer imports public `@actql/local-node` APIs, opens each role
through profile selection, and imports the real provider bundles through the
resolver. It does not patch the registration table or either common runtime.

The only transport replacement is the consumer's captured `https.request`.
It answers two reserved `.invalid` origins without creating sockets. The
standard credential Site and exchange still sign and claim grants, authorize
the operation, resolve a synthetic token, record the observation and finish
the credential journal. All other network entry points are forbidden.
Ed25519 keys are generated for this disposable fixture only. No environment
credential or real provider credential is read.

The authored assertions cover:

- Exact role-only loading through generated manifests and real provider ABI.
- Zero provider requests and secret resolutions on Host startup.
- Literal three-row output from two bounded pages through common capture and
  a following common Compute stage before Result publication.
- Provider error, malformed page and cancellation through common cleanup,
  confirmed physical stop, awaited Client close and durable attach after root
  reopen without another provider call. This singular acquisition does not
  emit the multi-acquisition ledger's resource counter events.
- Account refusal with zero provider requests or secret resolutions.
- A whole-Set approval checkpoint, one create send and successful recovery.
- A reply lost after the mock provider accepted the create, retained unknown
  state across Host reopen, and zero recovery resends.
- One failed credential-journal close retained by the standard Host cleanup
  owner, a concurrent retry of the same handle, and exactly one physical close.

The fixture helper exposes its transport, profile and Program builders for
focused diagnostics. It reports facts from executed assertions; its presence
alone is not test evidence. Builds and runtime acceptance must run through the
repository's bounded serial verification gate.
