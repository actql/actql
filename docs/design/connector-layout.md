# Connector ownership and repository layout

## Original UPDATE selection boundary

`run_publication_host/client_effect_target_selections.mbt` and its package-local
original-data projection retain the checked selection, its original prepared
Owner, canonical bytes/CID and saved-material admission. The eight selection
fields and the existing installation preimage have one MoonBit meaning. The
original prepared/allowed/Run readers still bind the independently retained
Compiled Plan and Run Definition, authorization and optional selection presence.
An equal CID, a copied JS array or parsed saved data cannot construct the opaque
selection or replace those original Owners. Existing absent-context identities
and all canonical preimages are unchanged.

The Node adapter observes the actual installed row factory's configuration,
Mapping inventory and generation, converts those facts, and retains their
physical lifetime. Common compares them with the original selection; JavaScript
does not define another selection schema, digest or canonical equality. Current
checks remain before physical work and after asynchronous boundaries. The
private request-journal installation uses the same runtime's bounded DATA
reader, and owner-only recovery returns the original saved admission evidence;
neither path grants disclosure, write, dispatch or retry authority.

The generated private DATA codec snapshots values once and transports JSON. Its
byte/node/depth ceilings come from that same Owner; it has no semantic field list,
normalization, CID or opaque constructor. Public DATA named `$tag`, `_0` or `_1`
is ordinary data here, not a MoonBit compiler representation. Compiler Result and
tuple interpretation uses the existing generated private binding.

The JS projection borrows the same prepared/selection/runtime references for
the projection's lifetime. DATA conversion temporarily overlaps the input,
bounded detached snapshot/keys and encoded wire; Common admission additionally
uses its bounded source/decoder/canonical writer workspace. These are not free
memory, physical retirement ACKs, capacity reservations or a numerical profile.
Releasing references or completing a synchronous comparison makes none of those
claims. The original Run, Store, Checkpoint, Unknown and cleanup responsibilities
stay with their existing Owners.

The repository layout must make implementation ownership visible. Connector-
specific planning, execution, transport glue, and foreign interfaces belong to
that Connector. Common scheduling, assembly, and cross-Connector verification
remain outside every Connector tree.

## Owned implementation

The DuckDB implementation uses these roots:

```text
src/connectors/duckdb/
  acquisition/        source acquisition
  adapter/            SQL and physical-value compilation
  compute/            fixed-input Compute support
  driver/             common Host lifecycle integration
  host/               acquisition Host bridge
  host_native/        native Host bridge
  host_node/          Node Host bridge
  adapters/native/    DuckDB-specific native FFI
  conformance/        test-only real-engine fixtures

adapters/connectors/duckdb/node/
  ...                 Node I/O and native DuckDB integration
```

The native FFI is Connector-owned because its ABI, loading rules, and physical
behavior are specific to DuckDB. `src/platform_native/` is reserved for
product-neutral operating-system capabilities such as filesystems, HTTP, and
SQLite access.

The conformance package is deliberately inside the Connector tree so its
subject is clear. It is not a product Host, a public SPI, or a dependency that
product packages may import.

### Meaning and physical transport

Connector-specific meaning belongs to that Connector's MoonBit owner, including
request identity, ResourceRef derivation, response interpretation, page
completion and recovery matching. The foreign adapter performs the selected
physical operation and returns its observation. It retains the original opaque
request and cleanup responsibility instead of reconstructing them from fields.
Static Catalog or Command declarations can remain data; this does not move their
identity or recovery algorithms into an independent host-language implementation.

Moving a representation or digest computation does not change its existing
preimage, refusal behavior, authorization or unknown-outcome semantics. Separate
changes to those contracts require their own semantic decision. Shared
approval, dispatch, reconciliation and accounting remain with the existing
common owners. Adding a Source or Command must not introduce a Connector-local
Run scheduler, retry authority or approval state machine.

Bulk physical conversion can preserve Arrow, file or engine representations
without materializing every value as a MoonBit object. Its schema, absence/NULL,
numeric and encoding rules, order, chunks, EOS, custody and simultaneous copy
bounds must still satisfy the selected contract. See the
[bulk execution resource boundary](implementation-port.md#bulk-execution-resource-boundary)
and [language binding boundary](portable-execution-boundary.md#language-bindings-and-artifact-correspondence).

## Composition and integration

Rebuild-time assemblies remain in `src/connectors_builtin*` and
`adapters/connectors-builtin/`. They select installed Connector contributions
but do not own Connector behavior.

Cross-component verification remains in packages such as
`src/query_integration/`, `src/node_host_conformance/`, and the corresponding
adapter tests. Integration code may depend on Connector implementations;
common Host and scheduler packages may not.

## Enforced boundaries

Repository gates enforce three constraints:

1. Common execution packages have no direct or transitive dependency on a
   package below `src/connectors/`.
2. Product packages do not import conformance packages.
3. A Local-only bundle contains no DuckDB package, Node adapter, native FFI,
   addon, or linked DuckDB library marker.

These constraints apply to future Connectors as well. Adding Salesforce,
Neo4j, or another backend must extend the Connector-owned roots instead of
creating new product-specific top-level platform packages.
