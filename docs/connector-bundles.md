# Rebuild-time connector contributions

These are source-checkout Host implementation interfaces, not a dynamic plugin
loader, sandbox or a stable public Connector SPI. Common candidate comparison,
dispatch, reservation, ownership and completion checks remain in the shared
libraries. Connector factories provide implementations, not success authority.

## Typed Compute composition

Each connector may own a `compute-bundle.json` under `src/connectors/<name>`.
The declaration identifies its opaque configured module type, exact registration
accessor, contribution factory and the two diagnostic error types. The factory
returns `physical_host.ComputeContribution`, pairing pure proposal and preparation
entrypoints over the same installed module. It must not perform transport or
construct unchecked completion evidence.

With the pinned MoonBit tools on `PATH`, regenerate and check the assembly:

```sh
node scripts/connector-compute-bundles.mjs --write
node scripts/connector-compute-bundles.mjs
moon check --target all --deny-warn
```

The generator uses pinned `moonfmt` through stdin/stdout. Check mode does not
rewrite files. `src/connectors_builtin` is the generated composition root, not
a common planner dependency. Do not hand-edit its imports or contribution list.

`assemble_compute_contributions` accepts the Host registry, an entry bound and
optional typed configured modules with diagnostic error projections. Omitted
modules remain absent even when their implementations were compiled. The bound
is checked before contribution construction. The SDK rejects foreign or duplicate
registrations and a closed registry, snapshots the installation and orders it by
the Host's registration order. Connector directory order does not become a new
tie-breaking policy. There is no append or replacement operation.

Project `.prepare` from the resulting installation for `open_dispatch_host`, and
`.propose` for `open_adaptive_dispatch`. The projections retain the exact same
registrations. Execution still consumes the connector's typed dispatch channel;
a diagnostic projection cannot supply a successful result or bypass reservation.
Configured module construction, source authorization and provider settings remain
the responsibility of the owning connector and explicit Host setup.

Local, DuckDB and the independent numeric reference implementation provide typed
declarations. The reference implementation supplies Compute only; it does not
need an Acquisition implementation. Its conformance path selects numeric work
and Local work through the same shared Host, including cancellation and settlement.

## Node transport composition

Node execution contributions are separately declared by connector-owned
`node-bundle.json` files and generated with `connector-node-bundles.mjs`.
`adapters/connectors-builtin/strategy.generated.mjs` supplies the enabled transport
factories to the common serial Node driver. A typed Compute declaration does not
by itself implement Node I/O. The standard Node application currently configures
Local and DuckDB; the numeric reference path exercises the portable common Host.

The registry key identifies an implementation, not a resource or data location.
Distinct resource bindings can belong to one implementation. Reuse requires an
exact live owned copy and matching binding; equal names or content CIDs do not
discount transfer or grant access. See the [resident boundary](design/duckdb-resident-execution.md)
for the existing multi-binding DuckDB realization.
