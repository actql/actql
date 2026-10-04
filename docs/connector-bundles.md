# Rebuild-time connector contributions

These are source-checkout Host implementation interfaces, not a dynamic plugin
loader, sandbox or a stable public Connector SPI. Common candidate comparison,
dispatch, reservation, ownership and completion checks remain in the shared
libraries. Connector factories provide implementations, not success authority.

This version provides implementation contracts for Acquisition and fixed Compute.
Transfer and Effect remain distinct responsibilities; their author contracts will
be added when those capabilities are introduced. Adding an implementation of an
existing capability is different from extending the SDK with a new capability.
Registration never requires implementing every capability. Existing fixed-data
transfer, resource reservation and recovery operations support current Compute
realizations; they are not a finished standalone Transfer or Effect bundle SPI,
nor a general Cloud resource-provisioning contract.

## Typed Compute composition

Each connector may own a `compute-bundle.json` under `src/connectors/<name>`.
The declaration identifies its configuration type and pure construction function,
opaque configured module type, exact registration accessor, contribution factory
and the two diagnostic error types. It also declares the typed execution function
and its result (`Unit`, a named type, or a bounded tuple of named types). The contribution factory
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
Generated `dispatch_<connector>` entrypoints retain the configured module and its
error projection, reject omitted implementations without starting work, and call
the connector's exact typed execution channel. They do not erase result types or
create completion authority. The standard application's execution calls use these
generated entrypoints rather than manually wiring connector execution functions.

An optional `estimate_policy` or `resource_policy` declaration supplies a typed
settings shape, preparation and installation functions, and the implementation's
work inventory. `null` means that no separate policy installation is needed;
the independent numeric connector fixes its estimate during construction.
Generated policy preparation retains the exact module, prepared policy and error
projection without installing it. `install_configured_estimate_policy` invokes
that captured installation only; it cannot target another module. The connector
still checks duplicate installation, resource ownership and prior execution.
This separation lets the application validate all policies before enabling its
shared adaptive Host. Neither preparation nor installation creates resources or
completion evidence, and charged planning work is not refunded on failure.

Pass configured modules to `connectors_builtin.open_configured_compute_host` with
the exact Host registry, fixed-input capacity, bounded inspection limits and the
implementation count bound. This standard entry retains the original module
driver and delegates to `physical_host.open_compute_host`; it does not require
any particular implementation or unused provider settings.
`configured_host_runtime` provides the common Host for policy installation.
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
and Local work through the same shared Host. Its generated execution entry returns
only success or failure; callers do not drive numeric attempts or publish results.

### Basic in-process Compute authors

`physical_host.prepare_compute_author_context` checks neutral `CompletionPreparation` handles against
the exact checked task owners and retains an immutable handle collection.
`compute_author_sequence` exposes a task's owned completion preparation, not
mutable DAG state or Local evaluator contexts. Build it with
`execution_relation.prepare_completion` from admitted registry contracts and a
typed semantic sequence. Local's `GeneratedSequence` is not required. See the
[typed Relation boundary](design/typed-relation-boundary.md) for semantic
projections, common fragment requirements and storage ownership.
`charge_compute_author_planning` and `propose_compute_author_work` charge the
existing cumulative ledger and construct offers for that same run. A basic
implementation need not traverse the DAG or import the resource ledger package.

The independent numeric driver uses this context and
`execute_compute_author_work`. The connector supplies its typed preparation and
in-process calculation; the common operation consumes the exact dispatch channel,
reserves the selected capacity, verifies owned completion evidence and attaches
result holding atomically. Returning success from calculation does not constitute
completion evidence. Failure closes the exact execution without discarding
independent completed outputs or consumed work.

This operation is restricted to synchronous, in-process work: return from the
calculation confirms no external work remains. It is not an adapter for a pending
Promise, native job or cancellation request. Asynchronous implementations keep
the explicit stopped/settled protocol and pending cleanup responsibility. The
context is implemented below composition, without importing planner or strategy
types back into `connector_sdk`. Resource-reuse author APIs remain separate.

To verify extension without modifying the common implementation, run:

```sh
npm run check:connector-addition
```

The check requires committed product and assembly sources so its revision identifies the
tested input. It creates an isolated source tree with Local/DuckDB declarations,
without the numeric connector or integration package. It checks that baseline,
adds the independent connector and reused integration fixtures, regenerates only
the composition roots, and runs the standard installation with Local alone,
the numeric connector alone and both on JS/Wasm/native. It also runs these
subsets through the same standard Node entry and generated bridge using a real
captured input, without DuckDB Compute settings. File digests include the
handwritten standard entry and bridge template, rejecting changes outside the
connector, generated composition and integration directories. The tests exercise
normal execution, retained results, recovery and cancellation before dispatch;
separate prepared-execution tests retain post-start cancellation
and settlement order checks. The isolated sources, per-phase logs and
machine-readable change inventory are retained at the printed temporary path.
This is an implementation-addition check, not proof of a new provider's semantic
conformance or an unimplemented transport capability.

`check:spec` also runs the connector dispatch boundary gate. It checks common
source files for concrete IDs, closed execution variants and literal dispatch
tables, with negative cases and positive opaque-lookup cases. Comments and
transported labels are not interpreted as dispatch. This lexical regression check
does not establish a security boundary against obfuscated code; dependency/API
checks and the isolated addition/build tests provide separate evidence.

## Occurrence-indexed execution declarations

The synchronous and prepared execution SDKs take join output ceilings as an
ascending array of `(step, ceiling)` declarations. Steps must be distinct and
inside the exact request's checked pipeline; ceilings must be nonnegative. The
SDK copies the array before retaining it and exposes only per-step lookup, so
later caller mutation cannot change an admitted preparation. These declarations
are trusted implementation commitments, not checked capacity claims: the Host
must still compare them with the original owned task obligations before start.
The common DAG compares every occurrence before either synchronous or prepared
start. It exposes the frontend-owned local Unit obligations through
`graph_task_operation_count/at`; imported producer visits are not re-executed.
Connector eligibility must reject unsupported execution checks before offers.
Local currently supplies at most one selected join ceiling, at its actual step,
and excludes tasks needing multiple ceilings. DuckDB retains its compiler's
bounded operation profiles. The DAG itself does not branch on operation names
or demonstration step counts; Local sort/take uses the standard Host unchanged.

For Relation semantics, use the readonly lowering views described in
[the typed Relation boundary](design/typed-relation-boundary.md), including
`kernel_dedupe_key_at` / `kernel_dedupe_order_at`,
`kernel_distinct_projection`, and the prepared join rules. Local evaluator and
preparation code are subject to the same no-frontend-traversal gate as Connector
code. Charge a projection's field count before requesting its defensive copy.

Common `SequenceRequirements` are matched by occurrence and exact request, not
their enumeration order. Reordering them does not change the semantic sequence.
DuckDB still rejects selected `common_fragment: Some(...)` requirements before
comparison; Local-free DuckDB preparation does not imply enforcement of every
common logical budget.

## Node transport composition

Prepared execution authors supply `ExecutionOperations.retention_released` as
an installed physical cleanup fact. Memory-only implementations may confirm it
after synchronous disposal. External files and provisional retained outputs must
not confirm it merely because execution stopped, cancellation was requested, or
the result was revoked. After disposal, `refresh_task_execution_cleanup` polls
this fact for the exact execution; it cannot assert deletion or native stop.
Cleanup retries belong to the implementation and do not retry computation.

`bind_prepared_execution` optionally accepts an installed `retained_bytes`
measurement. It runs after readiness and execution settlement, before holding
attachment, and must include every still-owned result allocation and metadata
allowance. The common driver rejects negative values and values exceeding the
original reservation. Omitting it retains the admitted capacity. A measurement
does not prove output validity: finish, exact publication and cleanup checks
remain mandatory. Unused reservation is released only on successful completion
or confirmed cleanup, not merely because the measured output is smaller.

Node execution contributions are separately declared by connector-owned
`node-bundle.json` files and generated with `connector-node-bundles.mjs`.
`adapters/connectors-builtin/strategy.generated.mjs` obtains the actual configured
module keys from the owned MoonBit setup. It validates the whole subset before
loading any module. Only selected entries in the fixed, generated loader table
are imported; omitted SDK dependencies are not resolved. All selected modules
must load before any pure factory is called. Load failure stops installation,
without fallback. Omitted factories, settings and finalizers are never used.
This is not arbitrary dynamic plugin loading. Workers keep explicit static
build-time compositions. These keys do not replace exact capability
registrations or resource bindings. Unknown and duplicate keys are rejected.
A typed Compute declaration does not
by itself implement Node I/O. `connectors_builtin_node` generates typed bridge
operations from the same configured modules and their manifest execution entries.
Use `runCapturedStrategy(setup, moduleOptions, signal)` from
`adapters/host-node/entry.mjs`. `moduleOptions` is indexed by generated module key;
its provider-specific value is read only by that installed module. For example,
DuckDB accepts `{duckdb: prepareDuckDBStrategyConfiguration({transportLimits, importLimits})}`;
import that pure preparation function from `adapters/connectors/duckdb/node/configuration.mjs`
without loading the SDK. The standard entry snapshots the outer mapping before
awaiting, retaining exact immutable Connector-owned handles without copying their
contents. Accessor properties in that mapping are rejected. In-process Local or
numeric-only setups require no transport options. The entry fixes its runtime,
ABI checking and driver; execution options cannot replace them.
The standard entry includes the checked Program's named Result identity floor.
Caller policy can strengthen that floor but cannot disable it. Implementations
which cannot establish a required identity are excluded before task start; this
does not by itself publish a Result Artifact. The separately named
`runCapturedInternalStrategy` entry is limited to task-only execution and makes
no Program Result publication claim. Choosing that entry, rather than passing a
false policy value, is the explicit distinction between the two execution
targets.
Installation failure or cancellation before execution rejects the call without
starting a task. Cancellation stops further loads and factories, but an already
started import is observed until settlement; it is not abandoned in the background.

Local-only, numeric-only and mixed Compute installations use this same entry and
generated bridge. The independent numeric Node contribution calls its owned
in-process execution entry; conformance does not drive attempt settlement or
completion. To add an existing capability implementation, provide its module,
typed `compute-bundle.json`, optional Node `node-bundle.json` contribution and
application settings, then regenerate the two composition packages. Neither the
standard bridge template nor common Host/driver changes.

A contribution may declare a typed asynchronous dispatch result and an optional
`synchronous_dispatch` function returning `Result[Unit, DispatchIssue]`. The latter
is eligible for the generated in-process entry, not an instruction to coerce
asynchronous work into synchronous execution. Local uses this split for retained
input conversion: its own wrapper drives bounded Store reads after common
reservation, while its synchronous entry accepts only a no-I/O prepared plan.
The manifest owns both entrypoints; neither the common driver nor the generator
branches on Local or DuckDB names.

`node scripts/check-node-without-duckdb.mjs` executes Local-only, numeric-only and
mixed installations through that standard entry in a copied tree without
`node_modules`. It uses the actual compiled Core and a mock captured-input fixture,
not a substitute execution driver. Real DuckDB conformance runs separately.

The Local/DuckDB rate and resource profile in `connectors/duckdb/standard_host`
belongs to the dedicated DuckDB application profile. It returns the generated
standard installation; it is not a mandatory two-provider Host API. The old
top-level packages and DuckDB-owned standard Node entry have been removed,
without compatibility exports.

## Installed Host bindings

A connector the standard installed Host can bind as a source declares that
binding in its own `src/connectors/<name>/host-bundle.json`:

```json
{
  "installation": {
    "registration": "salesforce",
    "revision": "salesforce/0.1",
    "providerBundle": "connectors/salesforce/host_node",
    "responseHeaders": [],
    "source": {
      "profileVersion": "actql-installed-salesforce-source/0.1",
      "module": "adapters/connectors/salesforce/host/installed-salesforce-source.mjs",
      "exports": {"check": "...", "identityParts": "...", "publish": "...", "load": "..."}
    }
  }
}
```

`connector-node-bundles.mjs` validates every manifest (registration equals the
connector root, revision under it, a `js` `foreign_library` provider bundle in
the connector tree, a `host/` module exporting the named entries, lowercase
unique response header names) and generates
`adapters/connectors-builtin/installations.generated.mjs`: the installed
connector table. `adapters/host-node/installed-source.mjs` selects one entry by
the installed Host profile's `version`, loads only that connector's module and
provider bundle, and refuses an unknown version before any I/O. The common Host
never branches on a provider name; DuckDB's built-in binding enters the same
table from the Host itself, with its exact physical target as an identity part.

The selected module's `check` checks the profile shape, `identityParts`
supplies the installation identity's documents without a credential value,
`load` returns the installed source adapter documented in
`installed-source.mjs`, and the optional `publish` is the explicit publication
step. A loaded adapter reports `connectorRegistration`/`connectorRevision`; the
Host refuses the installation when they differ from the declaration, so a
declared value is a verified claim, never authority.

Provider drivers reach the network only through the typed exchange
(`adapters/host-common/http-exchange.mjs`) and the credential resource: a
request is `{method, path, query, headers, body}` with lowercase, non-secret,
bounded request headers (`accept`, API version and `User-Agent` headers are
declared by the provider's driver, never hidden in it), and the response
observation carries only the header names the installation declared, under
fixed caps. An over-long or malformed header observation is a typed refusal.
`adapters/site-node/https-exchange-fixture.mjs` is the provider-neutral test
server for that boundary; it answers HTTPS and replaces no owner.

A connector whose Site driver returns pages of JSON rows does not need its
own capture code in the common runtime. `adapters/host-node/installed-row-source.mjs`
and the common package `src/client_row_source_host` (exported as
`clientProgramRowSource*`) do the following:
- generate the connector's SourceViews and Catalog from its view
  specification, for example `src/connectors/github/source-views.json`;
- reproduce the published Catalog CID on load;
- admit every row value against the checked input schema;
- run the same custody, residual, retention, evidence and capture owners as
  every broad acquisition.

The connector supplies its view specification, its physical target and its
page driver. Values must already be in ActQL spelling; for example GitHub's
whole-second timestamps gain `.000`. GitHub's Issue source is the first user.

An Effect installation is declared by the same manifest's optional `effect`
section. It has the same keys, its own profile version, and a module exporting
`check`, `identityParts(profile, read)`, `load` and optionally `publish`.
`installed-effect.mjs` selects it by the Effect profile's version and gives
`load` the Host's own Effect Ledger root. `load` returns the Effect Site
hooks: `environmentWire`, `connectorBindings`, the self-reported registration
and revision, `prepareCaptured`, `prepareRecovered` and `close`. The Host's
Run, Checkpoint, dispatch, Ledger and publication owners do not change.

Acquisition still uses the shared `CapabilityRegistry` and checked request/evidence
SDK, with mock/DuckDB preparation, issuer, retention and capture in their owning
packages. Those existing source Host entrypoints are not generated Compute
modules: source grants and acquisition settings remain separate. This does not
claim a unified generated Acquisition Node installer or a new SaaS capability.

The registry key identifies an implementation, not a resource or data location.
Distinct resource bindings can belong to one implementation. Reuse requires an
exact live owned copy and matching binding; equal names or content CIDs do not
discount transfer or grant access. See the [resident boundary](design/duckdb-resident-execution.md)
for the existing multi-binding DuckDB realization.
