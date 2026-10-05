# Salesforce Read through the neutral row owner

Refs #351. Initial baseline: `44e07a2de522d4dfc6d7924d4672e88d237aa6e3`.
Refreshed before publication to `6150587ab7774e2a1c81bb3ac7e6f1cd4478d77d`;
the intervening Native wire and frontend changes do not overlap this unit.

## Ownership and compatibility

The installed Salesforce Read now uses `client_row_source_host` for checked
input admission, candidate selection, issuer/attempt custody, transport
settlement, residual computation, bounded retention, capture and Source Evidence.
GitHub's JSON pages and Salesforce's already-typed pages use that same owner.
There is no alternate execution path or compatibility fallback.

The Salesforce connector retains its Site binding and current authorization,
retained describe recovery, declaration generation, projection/SOQL semantics,
query pagination, exact value decoding and credential grants. These are provider
codecs and installation responsibilities, not a second capture owner.

`installed_read.mbt` restores the same declaration from the same retained
observation and verifies the existing Catalog CID. `row_projection.mbt` binds the
current describe to the checked source and derives the existing exact integer
prefilter. Neither owns an execution buffer, attempt or captured source.

No Catalog, SourceView, schema, Mapping or contract identifier is renamed. The
existing Salesforce declaration generator and its canonical preimages are
unchanged, including write declarations. There is no conversion to the simpler
GitHub view specification and no loss of precision or scale.

The two typed admission entry points are common, provider-neutral functions:

- `prepare_declared_row_source` binds regenerated declared-view facts to the
  exact checked source reference, contract CID, connector, Resource and fields.
  It obtains field contracts from the checked input, never from row metadata.
- `accept_row_run_values` consumes named, already-admitted values. Names must be
  unique and cover exactly the checked columns. Row width and page bounds are
  checked. The existing `append_admitted_input` then requires exact contract
  identity, including decimal precision and scale, and charges retention limits.

Salesforce's number lexemes are admitted by its existing decoder as
`decimal(P,S)`, not converted through JavaScript Number or neutral JSON number
admission. Date and UTC datetime conversion, unsupported-type exclusion, nullable
missing-as-null, required missing/null distinction, and typed value violations
remain provider semantics. Provider pages remain bounded; no partial capture is
published on a later-page refusal or incomplete pagination.

A completed page chain still cannot capture until the exact transport attempt's
verifier confirms settlement. Each capture remains live only while its own
issuer remains open. The adapter retains the existing acquisition failure
classification and Site cleanup owner. Current read authority is checked again
before issuing Source Evidence.

## Removed paths and retained operations

Removed after caller inventory:

- `src/client_salesforce_host`, its dependency-manifest entry and generated imports
- The installed-Read Broad start/attempt/page/capture/Source Evidence bridge exports
- Salesforce's obsolete Broad execution, custody, captured-source and source-evidence
  modules, plus their provider bridge modules and `readSalesforceIssuedBroad`
- The superseded Broad-execution tests; projection and declaration negatives are
  retained in `salesforce_row_projection_wbtest.mbt`, and neutral typed handoff,
  lifetime, settlement and public pagination cases replace the execution coverage
- Dead observation/Catalog/page-count bridge exports with no remaining callers

Remaining common bridge Salesforce entries are the Site/retained-declaration and
provider query codecs necessary to decode within the checked Program's compiled
runtime. Opaque MoonBit values never cross independently compiled runtimes.
These live codec entries are explicitly not claimed removed. The main and RelA
assemblies are regenerated from the existing generator and dependency manifest.

The managed-output read path remains live for existing preview/Effect consumers.
Salesforce create, update, upsert, full-diff target observations, approval,
durable claims, uncertain writes and recovery remain under their current owners.
Those responsibilities are not removed or wrapped by the neutral create-only
Effect work. Salesforce Effect migration requires a separate scoped unit covering
those operations; #364's GitHub create-only contract does not establish it.

H's #357 is merged in the baseline. This unit does not modify #364's neutral
Effect factory, installed row-source adapter, GitHub installation or credential
Site changes. The connector manifest remains the installation authority.

## Evidence

The existing public Salesforce fixture supplies independent expected values and
provider observations. The migrated tests cover Named Result values, exact
15-digit decimals, scale/type refusals, date/datetime values, no I/O on denied or
foreign bindings, held reads across restart, cleanup failure retention, and
existing Effect approval/restart behavior.

Additional finite cases cover:

- retired execution exports absent, and two independent live captures
- a foreign field map or exact typed contract refused before capture
- a complete read refused without exact transport settlement
- a two-page locator chain producing independently specified final rows
- distinct required missing/null failure classification
- a later-page refusal discarding earlier admitted rows without replay

The provider projection checks preserve foreign Site, connector, Resource and
schema refusals and the exact checked integer prefilter. The ordinary neutral
row declaration/Mapping tests remain unchanged.

Local checks and final automatic-CI evidence are reported in the PR. Local
source-tree tests are not fresh packed Local/HTTPS acceptance. No full Core,
all-target, proof, performance or packed campaign is run locally. No live
Salesforce request, deployment, merge, manual CI dispatch or replay is part of
this unit.

Status is separated deliberately: Salesforce Read execution migration is this
unit; Salesforce Effect migration is not complete; overall connector-authoring
completion is not claimed.
