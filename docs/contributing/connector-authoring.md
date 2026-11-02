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

## Declarative REST Source route

The repository provides a build-time toolkit to scaffold, project and check a
declarative Source package. It uses the existing manifest and installation
generators and does not execute or install a Source. A matching normal
framework distribution must separately provide the REST facade, common Host
service, managed reader and original initialization backing. The application
example below requires those runtime services; generated metadata alone does
not provide them. Source projection does not establish ordinary acceptance.

For a fixed HTTPS GET API with finite JSON pages, the declarative route keeps
connector-specific work to one definition and, only when necessary, one pure
JavaScript row-wire projection. It requires a normal framework distribution
with the standard REST facade and its common Host initialization and managed
reader. A registration table or generated package alone cannot supply that
service, physical backing or permission. Missing framework support refuses;
do not replace it with a source import, application funder or custom reader.

### The author input

A definition describes the original API and typed fields, not a new execution
owner. For example, `connector.json` can contain:

```json
{
  "version": "actql-rest-connector/0.1",
  "id": "acme",
  "origin": "https://api.example.invalid",
  "auth": {"kind": "bearer"},
  "sources": {
    "customers": {
      "fields": [
        {"name": "id", "type": "string", "nullable": false},
        {"name": "name", "type": "string", "nullable": true}
      ],
      "read": {"method": "GET", "path": "/v1/customers"},
      "pagination": {
        "kind": "cursor",
        "items": ["data"],
        "next": ["next_cursor"],
        "parameter": "after"
      },
      "limits": {
        "maxPageRows": 100,
        "maxPageBytes": 65536,
        "maxPages": 10,
        "maxRows": 1000,
        "maxNodes": 10000,
        "maxDepth": 16,
        "maxCursorBytes": 1024
      }
    }
  }
}
```

The field DATA enters the original Common declaration constructor unchanged.
These finite page and row ceilings constrain the connector; they are not a
Ledger, capacity reservation, permission or an instruction to raise the Host
policy. A selected implementation must cover them. The fixed origin/path
cannot be replaced with a URL returned by the provider. Credentials and
credential resolvers stay in the ordinary Account/Site setup, outside this
file and every author callback.

For a root array without pagination, use `{"kind":"none","items":[]}`.
The standard projector already preserves JSON row bytes and cursor identity;
an identity projection needs no extra JavaScript file. If a projection is
needed, `transform` names one relative `.mjs` file exporting synchronous
`decodePage(page, context)`. Its inputs are frozen row-wire/count/cursor DATA
and resource/column DATA. It returns only `rowsWire` and an optional unchanged
`nextCursor`, in a plain own-data record with `Object.prototype` or a null
prototype. Return primitive field values; Proxies, accessors, inherited fields,
extra fields and symbols are rejected. Compute transformed values inside
`decodePage`, then return them as own data properties. It cannot supply a row
count, run an asynchronous operation, access credentials or authorize another
read. The Host invokes it under the
same active reader; changed wire is bounded before allocation and checked by
Common. Avoid parsing provider numbers through JavaScript `Number` and then
reserializing them.

### Scaffold, build and install

From a checkout with the authoring toolkit, scaffold and project the package:

```sh
node scripts/connector.mjs init /absolute/acme-author acme
# Edit /absolute/acme-author/connector.json.
node scripts/connector.mjs build /absolute/acme-author/connector.json /absolute/acme-package
node scripts/connector.mjs test /absolute/acme-author/connector.json /absolute/acme-package
npm pack /absolute/acme-package --pack-destination /absolute/artifacts
```

`test` here checks projection freshness only. It never runs a Source or
qualifies authentication, currentness, charging, cancellation or cleanup.
Build produces the checked installation manifest, original views wire,
Source module, package metadata and lazy `installedConnectors` export. The
author writes no MoonBit package or per-connector Core/Host patch. The
original generated views wire is DATA for the Host's preparation owner, not
another author input or a way to acknowledge physical construction.

For that same supported source and normal distribution, install the generated
tarball alongside its deliberately matching normal framework packages using
ordinary npm lifecycle. The proposed application composes the existing
public installation APIs with the required REST implementation:

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

The profile, directory, authorization and secret resolver are explicit normal
application inputs. A connector package does not issue them or provide a
fallback grant. Keep their setup visible and separate from the one-file
connector implementation. The same Host owns checked declaration preparation,
original implementation/Site association, Request admission, response holds,
charging before decode, current checks, cancellation and physical cleanup.

### Ordinary conformance and author effort

Select the common external REST case under
`scripts/fixtures/external-rest/normal-case.test.mjs` through the existing
bounded local verification wrapper. Supply an exact normal-package manifest
and its hash, actual source identity, an explicitly authored Account, a fresh
output root and one selected fixture mode. No old installation or state is a
default. Set `ACTQL_REST_CONFORMANCE_INPUT` to that descriptor; its kind is
`actql-standard-rest-normal/0.1`, with `sourceSha`, `sourceTree`, `manifestPath`,
`manifestSha256`, `outputRoot`, `accountConfigurationPath` and `mode`. The
positive modes are `empty`, `one` and `paged`; fixture DATA for an error is not
evidence that an ordinary failure case ran. The provider fixture's literal
rows and request expectations are
independent of the product's output. A controlled HTTPS responder is ordinary
SDK/Host transport evidence; it does not establish support for an external
service's undocumented behaviour.

First prove a real public read and the actual first close with separate live
scoped-FD observations. Preserve the pending submission's original public
projection before its first await, and any returned Run reference before
waiting. The cold Saved check reopens only that successful original in a new
process, without another submission, provider request or secret resolution.
Keep empty/one/multiple-page, provider-error, byte-limit, current-loss,
cancellation, cleanup and multiple-connection frontiers distinct. A generic
Unknown, absent Run or process exit proves neither nonacceptance nor close.

Measure actual handwritten connector files/lines, optional callback count,
commands through first successful read, automated introduction time and
observed per-connector Core/Host edits. Report framework preparation,
generated output and Account/Site/application setup separately. Do not label
automated elapsed time as measured human typing time, or record zero edits
or callbacks merely because a registration table exists.

A migrated connector must also remove its replaced author API and duplicated
reader management after the same integrated normal path is verified. An
unused wrapper left beside a new export is not a completed migration. Keep
advanced provider-specific protocols only for their actual distinct duties;
this route does not authorize dropping their original lifecycle guarantees.

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

## Standard CREATE writes

Standard CREATE installations can select the existing Row Effect's `write`
declaration instead of an advanced `driver`. It fixes the operation, resource
kind and boundary identity, and the HTTP origin, method, path, nonsecret headers
and byte limits. The provider supplies `request(context)` and
`classify(context)`, plus a provider-specific subject or target `check` when
required. The Host derives request facts from the same immutable mapped input
and original request, the operation and footprint, and the scoped HTTP send.
An existing typed provider request keeps its exact `requestCid`; a plain HTTP
mapping receives an identity over the fixed declaration and exact transport.
There is no separate author `requestFacts`, `writeOperation`, `footprint`, send
or CID callback for that path.

The standard transformation receives only frozen `{resource, value}` DATA.
Classification receives `{resource, value, request, observation}` and the
original `headers` field when present. The resource and value come from the
same private request association. These callbacks receive no Run, Preview,
authorization, grant, current callback or child-preparation port. Existing
advanced conditional/read integration remains internal until its actual scoped
Host operation is selected; it is not part of this transformation contract.

GitHub comment CREATE and Sheets append select this declaration. Their original
repository/target checks, provider request codecs and outcome classifiers remain
provider-owned. The declaration does not turn a response classification into an
applied Receipt: approval, the durable claim, saved response, confirmation,
Unknown and cleanup remain with the existing Row Effect. Conditional writes and
reconciliation continue using the advanced path when their semantics require it.
This source migration has focused component coverage; it does not establish a
matching-package ordinary run or physical provider acceptance.

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
