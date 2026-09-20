# Connector ownership and repository layout

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
