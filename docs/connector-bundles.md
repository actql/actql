# Rebuild-time connector contributions

These are source-checkout Host implementation interfaces, not a dynamic plugin
loader, sandbox or a stable public Connector SPI. Common candidate comparison,
dispatch, reservation, ownership and completion checks remain in the shared
libraries. Connector factories provide implementations, not success authority.

## Typed Compute composition

Each connector may own a `compute-bundle.json` under `src/connectors/<name>`.
The declaration identifies its configuration type and pure construction function,
opaque configured module type, exact registration accessor, contribution factory
and the two diagnostic error types. The contribution factory
returns `physical_host.ComputeContribution`, providing pure proposal, preparation
and exclusion-diagnostic entrypoints over the same installed module. It must not perform transport or
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

`configure_compute_modules` accepts typed connector configurations with their
exact registrations and diagnostic projections. It validates the entire selected
registration subset before invoking any connector constructor. Construction stays
inside the owning connector; it may perform bounded static preparation, but not
provider I/O or task start. The generated opaque result retains the configured
modules and their fixed contributions. `configured_compute_contributions` feeds
the common Host, while generated typed module accessors allow the corresponding
connector to consume its own execution channel. The standard application uses
this generated construction path; it does not call connector constructors itself.

Pass the assembled installation to `physical_host.open_compute_host` with the
exact Host registry, fixed-input capacity and bounded inspection limits.
`configure_compute_host_estimates` installs its optional adaptive policy once;
`prepare_next_compute_task` refreshes that policy before preparing a checked-ready
task. The Host internally projects preparation and proposal from the same fixed
installation. A foreign registry is rejected even for an empty installation.
Manual fixed strategy selection can use the same Host without an adaptive policy.

`compute_host_exclusions` collects explanations through that same fixed
installation, in registration order. Its inspection allowance bounds registration
visits and returned entries; encoding limits separately bound rendered text.
Connector callbacks must honor the remaining entry allowance. The Host rejects
unavailable registrations, over-limit responses and targets outside the Compute
tasks. Realization labels and rejection reasons remain opaque display data, not
dispatch keys or evidence. Reading diagnostics neither starts tasks nor revises
selection or resource accounting.

Execution still consumes the connector's typed dispatch channel through the opaque
`compute_host_dispatch` handle;
a diagnostic projection cannot supply a successful result or bypass reservation.
The lower-level `DispatchHost` and `AdaptiveDispatch` interfaces remain available
for implementation-level composition; the standard path uses their shared
`ComputeHost` owner rather than keeping a second copy of adaptive state.
Configured module construction, source authorization and provider settings remain
the responsibility of the owning connector and explicit Host setup.

Local, DuckDB and the independent numeric reference implementation provide typed
declarations. The reference implementation supplies Compute only; it does not
need an Acquisition implementation. Its conformance path selects numeric work
and Local work through the same shared Host, including cancellation and settlement.

To verify extension without modifying the common implementation, run:

```sh
npm run check:connector-addition
```

The check requires committed product sources so its revision identifies the
tested input. It creates an isolated source tree with Local/DuckDB declarations,
without the numeric connector or integration package. It checks that baseline,
adds the independent connector and reused integration fixtures, regenerates only
the composition root, and runs the numeric Host test on JS/Wasm/native. File
digests reject changes outside the connector, generated composition and
integration directories. The test exercises both normal execution and cancellation
with settlement through the shared Host. The isolated sources, per-phase logs and
machine-readable change inventory are retained at the printed temporary path.
This is an implementation-addition check, not proof of a new provider's semantic
conformance or an unimplemented transport capability.

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
