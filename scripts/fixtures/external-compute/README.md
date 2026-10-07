# External numeric Compute fixture

This fixture exercises an external package through the existing generators and
common Host. Run `node scripts/test-packed-external-connector.mjs` from the
repository root with the pinned Node, MoonBit and npm dependencies available.
The harness copies source into an owned disposable build, invokes normal npm
prepack lifecycles, and installs both tarballs into a fresh external consumer.
It never edits Core to add the external module.

The external `fixture/external_numeric@0.0.1` module owns a small contribution
wrapper and Node adapter. It explicitly depends on `actql/actql@0.0.1` and uses
the public `connectors/reference_compute/driver` evaluator. It is not an
independently implemented numeric evaluator. Its contribution keeps the exact
Host driver, registry, and registration from generated configuration, and its
dispatch delegates to the existing common `physical_host` settlement and
completion boundary.

## Build inputs

- External module root: `external-numeric/`
- External module namespace/version: `fixture/external_numeric`, `0.0.1`
- External source root: `src`
- Compute manifest: `external-numeric/src/compute-bundle.json`
- Node manifest: `external-numeric/src/node-bundle.json`
- Selection key: `external_numeric`
- Host module root: `compute-host/`
- Host namespace/version: `fixture/compute_host`, `0.0.1`
- Generated Compute assembly: `compute-host/src/compute`
- Generated Node bridge: `compute-host/src/runtime`

There is no extra public content-manifest format. The harness supplies the
already resolved, trusted module roots and the existing two manifest paths to
the build helpers. Dependencies must resolve to the verified `actql/actql`
source and this external package through the build's normal local dependency
mechanism. The module declarations contain the versions; the harness owns local
dependency resolution.

## One runtime

`compute-host/src/scenario` is an authored source staging directory, not a
second runtime to exchange opaque handles with the bridge. The harness must:

1. Generate the assembly at `src/compute` and the bridge at `src/runtime`.
2. Copy `src/scenario/scenario.mbt` into `src/runtime`.
3. Copy the existing repository
   `src/node_host_conformance/fixture.generated.mbt` into `src/runtime` without
   regenerating or duplicating its graph/evaluator implementation in this patch.
4. Merge `src/scenario/moon.pkg` imports into the generated runtime's imports.
   The `builtin` alias points to `fixture/compute_host/compute`.
5. Build only the resulting single foreign-library runtime. Both scenario
   preparation and the generated dispatch bridge must use this same linked JS
   module and its Error tags.

The scenario selects only `with_external_numeric`; numeric limits match
`connector_conformance.configure_subset` mode 1. The common registry is the
ordinary `connector_sdk` registry. No scheduler, registry authority, completion
record, or output handle is reimplemented here.

## Consumer

The final pack harness imports `verifyExternalComputeFixture` from
`consumer.mjs`, then calls it with the single linked `moon` runtime, its generated
`installStrategyContributions`, and the unchanged common Host exports
`bindLocalJsHost`, `withScopedStrategy`, `runtimeCore`, and `checked` from the
normally packed package. These are trusted build inputs, not request data or
user-selectable runtime implementations.

The authored consumer asserts:

- Exactly three Compute tasks execute through both `bindLocalJsHost` and an
  explicit `withScopedStrategy`, and the final rows equal the literal `[{id: 3}]`.
- Only the generated `external_numeric` contribution is installed; diagnostics
  report the external adapter. The adapter returns no rows, output handles, or
  settlement authority.
- Saved common output handles become unavailable after scope close; asking the
  closed report for an output fails with `ReleasedStrategy`.
- Foreign-Host dispatch is refused without partial completion. The original
  Host can execute its own task once; replay is refused without ledger changes.
- Denied completion settles execution without publishing the task output.
- Cancellation while awaiting `beforeNext` dispatches zero tasks, consumes zero
  results, and completes cleanup.
- Held bytes and all transfer/retention/execution reservations are zero after
  cleanup.

The harness records the fresh runtime and generated-source hashes, tarball
integrity, copied Core input digest and actual consumer outcomes. Successful
scratch is reclaimed; failed attempts retain their evidence for diagnosis.
