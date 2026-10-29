# Connector authoring in the repository

How a Connector is added to the ActQL repository: where its code lives, what
it declares, what the common Host owns on its behalf, and what its tests
must show. This page is for contributors; during v0.1 the repository takes
Connector changes from the maintainers only (see
[Development](README.md#how-contributions-work-during-v01)). What a Connector is and how one is
designed is in [Building a Connector](../connectors/authoring.md); this page
is the in-repository mechanics.

The common semantics stay in the MoonBit Core and the common Host owners. A
Connector contributes a checked installation manifest and a physical driver;
the Core decides when its work is complete.

The [authoring completion criteria](#authoring-completion-criteria) below set
the required boundary for the refactoring. They are a target, not a claim that
the proposed standard authoring API is already available.

## Layout

A Connector owns its planning, execution, transport glue and foreign
interfaces under its own roots. Common scheduling, assembly and
cross-Connector verification stay outside every Connector tree.

```text
src/connectors/<name>/
  acquisition/        source acquisition
  adapter/            query and physical-value compilation
  compute/            fixed-input compute support (when the system can compute)
  driver/             common Host lifecycle integration
  host/               acquisition Host bridge
  host_native/        native Host bridge
  host_node/          Node Host bridge
  adapters/native/    Connector-specific native FFI (when needed)
  conformance/        test-only real-engine fixtures
  host-bundle.json    installation manifest (sources, Effects, exports)
  compute-bundle.json compute contribution manifest (when applicable)

adapters/connectors/<name>/node/
  Node I/O: HTTP, SDK sessions, native integration
```

Three constraints are enforced by repository gates:

1. Common execution packages have no direct or transitive dependency on a
   package under `src/connectors/`.
2. Product packages do not import conformance packages.
3. A Local-only bundle contains no DuckDB package, Node adapter, native FFI
   or linked library marker.

A new Connector extends these Connector-owned roots; it does not add a
product-specific top-level platform package. `src/platform_native/` is
reserved for product-neutral operating-system capabilities such as
filesystems, HTTP and SQLite.

## Declarations

1. Declare the Source and Effect roles in `src/connectors/<name>/host-bundle.json`:
   the profile versions, registration and revision, the adapter module, and
   the exact check, identity, publish and load exports. A read-only
   Connector declares no Effect.
2. Declare a pure codec package as `providerBundle` only when one is needed,
   and owned static files as `assets`. No implicit package resolution,
   external aliases or undeclared filesystem dependencies.
3. If the system can compute (filter, aggregate, …), declare the compute
   contribution in `compute-bundle.json`: its configuration type, pure
   construction function, registration accessor, contribution factory and
   diagnostic error types.
4. Regenerate the assemblies and check them:

   ```sh
   node scripts/connector-node-bundles.mjs --write
   node scripts/connector-compute-bundles.mjs --write
   moon check --target all --deny-warn
   ```

   The installation table and the standard package inventory come from the
   manifests. `src/connectors_builtin` is generated; do not edit it by hand.

5. Restore the typed Catalog and SourceViews through the common row-source
   Host (`client_row_source_host`), using its Mapping factory and
   check-environment permission checks. The driver never constructs evidence
   or accepts operations the Connector did not declare.

A row-addressable Mapping keeps a required non-nullable scalar identity. A
collection-only Mapping has no primary identity and a typed collection
identity, and permits create only. Unsupported operations are refused at
registration and check, never carried into a physical send.

## What the common owner does, and what the driver supplies

Reads: `createInstalledRowSource` owns checked acquisition, page charging,
capture, input binding and source evidence. The driver supplies a
`physicalTarget` and finite `readPages`, using the per-page authorization
and the scoped credential it is handed. It keeps no second ledger and issues
no success of its own. It observes bytes before projection and never
replaces an API error with empty input or `NULL`.

Writes: `createInstalledRowEffect` owns the checked Preview, Set approval,
the durable claim, the saved response, the receipt, publication and
recovery. For each write kind the driver supplies a pure `prepareRequest`
and `requestFacts`, a `writeOperation`, exactly one physical `send`, a
response `project` and a bounded `footprint`. The common owner compares the
exact values and selectors with the Program and the Preview before dispatch.

Target-addressed writes also supply the target observation and version
hooks. Custom recovery supplies `recoveryEntry`, `recoverRequests` and
`requestCid` together; registration rejects an incomplete set. Recovery must
reconstruct and compare the exact approved requests — retained data is not
authorization. Create-only drivers may use the default reconstruction.

Classify a refusal only from semantic facts observed before the send; a
refusal marker is not a catch-all for exceptions, rate limits, missing
responses or physical stops. A system with no authoritative lookup or
idempotency must leave a possibly-sent write `unknown`. Never synthesize
success from reading back an equal value.

Close and cleanup failures stay on the same retry handle; completion is
marked only after close succeeds. A retry releases resources — it never
repeats a read, a computation, a Preview, an approval or a send.

### Original SQL Job Source installation

BigQuery's `host-bundle.json` is a concrete Source-only registration using the
integrated Common and existing `readBigQuerySqlApi` driver. Its installed
factory preserves the exact Get Table bytes and scoped target in the standard
Account/Site identity, prepares the real query requirement once and retains
that original prepared read under its own nominal acquisition. It forwards
the same entered RowRun, current checks and authorization rather than opening
another acquisition or Ledger.

A Job's first POST requires the standard `withOriginalJob` port from that same
Source occurrence and Journal. The factory selects a provider Job name from
the actual original attempt identifiers; this DATA name is not the durable
CAS or permission to dispatch. Missing original-operation scope refuses before
the Job driver can send. The shared driver retains exact request/status/result
and failure cleanup. Preserve its Unknown and same-Job GET behaviour; a new
factory, copied row or matching metadata does not authorize another POST.
See [BigQuery installed Source boundaries](../../adapters/connectors/bigquery/site/README.md#standard-table-source-installation).

## Tests a Connector must pass

Reuse the common registration, value comparison, prepare-refusal, response
recovery and cleanup fixtures from the installed-Effect test suite under
`adapters/host-node/`, with independent data for your system, and add only
the system-specific boundary cases:

- supported registration and preparation; refusal of undeclared operations
  and incomplete hook sets;
- exact typed values, selectors, targets and request identity, including
  Unicode;
- zero sends before approval, one send per granted claim;
- saved-success and unknown reconstruction without a resend;
- refusal on current authority or target changes before the send;
- a failed cleanup keeps the record of the attempt, and a retry does not recompute;
- finite codec and transport limits, with exact and one-short cases;
- an external installation using only the public package exports.

A local responder stands in for the real service in tests; tests against the
real service are separate, and fixture results do not stand in for them.
Declare the query and write profile the Connector actually supports rather
than every language shape.

## Authoring completion criteria

Completing the resource-management refactoring also requires a small external
Connector to be practical to author. A common API alone does not establish
completion. Standard REST reads must work from one author-owned definition and,
where needed, a small JavaScript transformation. They must not require a new
MoonBit module, an internal bridge, manual capacity arithmetic, or changes to
the Core or Host for each new Connector.

### Responsibility boundary

| Owner | Responsibility |
| --- | --- |
| Core | Language meaning, types, checked declarations and Plan; original Program, Parameters and checked results used by execution and publication |
| Host | Connection and Credential scope, Run and Ledger ownership, reservation, current checks, attempts and transfer, reader lifecycle, cancellation, physical release and cleanup retry, Preview, Approval, durable claim, Receipt and reconciliation |
| Connector | SourceView, Mapping, Command and Capability declarations; provider-specific requests, paging facts, transformations, version guarantees, conditional writes and response evidence |

Ordinary Connector implementations must not create Runs or Ledgers, manipulate
`CapacityPlan` or `PreparationCapacity`, call internal Core Run checks, or own
a second approval, retry or cleanup state machine. A specialized SQL, file or
Native driver may supply the necessary physical operations and close evidence;
the same Host still owns their lifetime, accounting and authority.

The standard authoring surface is a thin build-time projection into the existing
manifest, SourceViews, Mapping, Command and Host installation contracts. It must
generate repeated registration, export and verification metadata from the same
author definition while retaining closed shapes, types, identities and ownership
checks. It must not introduce another runtime language, checker, policy engine
or resource owner. Proposed names such as `defineConnector` do not establish an
implemented API.

### Complete one ordinary path at a time

Start with one external REST Read Connector through the normal installation,
SDK and Host. A common ManagedReader must own original-reader acquisition,
Account and Credential binding, current and cancellation checks, attempt and
byte charging, response custody, physical stop and cleanup retry. Charge bytes
before decoding. Providers retain their actual request, cursor and response
semantics. Moving back to an unaccounted `readPages` path is not a migration.

Use that working path to replace duplicated Notion and Calendar reader
lifecycle code. Derive standard Effect request facts, write operations,
footprints, HTTP dispatch and request CIDs where the declaration determines
them uniquely. Providers retain request transformation, response classification,
target/version observation, conditional writes and authoritative reconciliation.
GitHub CREATE and Sheets append are representative Effect consumers; provider
confirmation rules remain mandatory. A lost reply stays Unknown without
authoritative evidence, with no hidden resend or inferred success.

Move Local Files Run creation, live-run retention, duplicate checks and
retirement to the common Host. Keep safe Root/FD operations, file content and
version comparison in the physical driver. Retired Runs must release their
references rather than accumulate toward a connection-wide limit.

For each completed path, remove its replaced lifecycle implementation,
compatibility aliases, dummy readers and old internal API dependencies in the
same coherent change. Existing supported behavior must work through the new
path; changing it to Unsupported does not satisfy removal. A simultaneous
rewrite of every Connector is not required.

### Acceptance evidence

Provide a scaffold and shared conformance harness, then use them as an external
author to add a new standard REST Read Connector. Verify the following:

- One definition and optional small glue code suffice. No custom MoonBit or
  per-Connector Core/Host change is required; an advanced driver remains
  available for genuinely specialized operations.
- Multiple connections remain independent. Program input cannot replace the
  installed origin, method, Credential, scope or provider identity.
- Zero, one and multiple pages, bounds, provider refusal, current loss,
  cancellation and cleanup failure use the common Host lifecycle. Physical
  close acknowledgement and retry retain the same original resources.
- Standard CREATE does not require authors to implement six internal hooks.
  There are zero sends before Approval and at most one per approved claim;
  lost replies remain Unknown, and restart retains the same request binding.
- Ordinary Connector code has no Run, Ledger or capacity-management machinery.
  Deleting the replaced interfaces still leaves supported normal paths working.
- Record handwritten files and lines, required commands, setup time, additional
  callbacks and Core changes. These are measured authoring costs, not arbitrary
  line-count limits. Separate provider-specific code from Host plumbing.
- At the same integrated SHA, the normal package, public SDK and actual Host
  execute, publish and release representative reads and Effects. Source checks,
  mocked ports and separate branch successes do not substitute for that result.

Keep the original Program, CheckedProgram, Plan, Ledger and authority through
these paths. Apply the [capacity policy](../design/capacity-policy.md) to real
resources and input-proportional simultaneous storage; do not make fixed
wrapper inventories another authoring or completion requirement. Compare
parse, check, compile, quote and external-current counts and representative
runtime cost so the facade adds no duplicate preparation or I/O.
