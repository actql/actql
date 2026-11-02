# Existing Connector and Table interface references

This finite 53-module intake records the current implementation hash, every
operation (including private callbacks), every syntax export and each module's
initialization boundary. Python syntax exports also include imported names;
this does not publish them as SDK APIs or Capabilities.

The references point to existing contracts, semantic implementations, physical
owners and executable tests. They do not copy those specifications, assign new
Owners, move semantics, grant authority or add Connector operations. A module's
role is an explicit reviewed classification, not a rule about its directory.
The existing syntax and ten-attribute Readers remain the coverage gate. A new
helper/export, changed implementation digest or missing reference fails that
gate rather than inheriting an existing module's declaration.

## Responsibility boundaries

| Selected modules | Existing authority and physical boundary |
| --- | --- |
| 23 DuckDB Node modules | MoonBit acquisition/adapter/Compute and `connector_sdk` keep requirement matching, value admission, SQL construction and completion. Neo sessions own native transactions, prepared statements, scalar conversion, transport accounting and actual cleanup. Configuration estimates are not reservations or RSS bounds. |
| 5 GCS modules | Common RowSource declaration, listing cursor, Resource issuer, keyed capture and capacity owners keep their authority. The GCS adapter fixes installed scope and exact generation/metageneration requests and accounts original responses. Flat listing and identity encoding remain explicit limitations: no new prefix-page, gzip or Range conformance is claimed. |
| 5 GitHub modules | Portable GitHub catalog code owns fixed request/projection/response meaning; the installed repository publication supplies stable identity. Common row Source/Effect, credential and Ledger owners keep disclosure, approval, send-once and recovery. Lost comment replies remain unknown, not retried by content equality. |
| 3 Local Table modules | The generic Connector installation selects Source/Effect roles. Common Table/Effect and Preview owners govern checked input, current binding, approval and dispatch. Iceberg metadata/manifests/Parquet and the same SQLite Catalog transaction govern head CAS and the original operation receipt. File allocations/fences/deletion records are physical custody, not another Effect Ledger. |
| 17 Salesforce modules | Portable Salesforce catalog code owns resource/projection/request/response meaning. Installation binds exact org/Site/runtime/configuration. Common authorization, credential, Preview and Effect Ledger owners still govern current use and uncertain sends. Historical publication or request reprojection never restores authority. |

`scripts/connector-host-bundles.mjs::generateInstallations` consumes the existing
GCS/GitHub/Local/Salesforce `host-bundle.json` declarations. Those are static
installation data, not execution algorithms. Portable bridges remain generated
from their original MoonBit packages. The index does not relabel any authored
adapter as a generated binding. In particular, the pinned Neo Node SDK is not
the Python/C DuckDB ABI or a claim that their engine versions are equal.

## Qualification of verification and data references

The `verification` attribute locates existing tests; it is not a result record.
This unit executes only `scripts/connector-baseline-interface.test.mjs` through
the existing bounded, nonzero Node wrapper. That test reads 51 JavaScript
modules with the existing Acorn Reader and two Python modules with the existing
stdlib AST Reader. It imports no Connector implementation, Arrow, Iceberg, native
driver, credential supplier or provider transport. Mutation controls exercise
the real Readers and original coverage validator. Whole installed-product
coverage remains with the integration Owner; no new target-runtime, public E2E,
paid I/O, pack or capacity-profile success is inferred from these references.

Referenced physical tests retain their actual boundaries: DuckDB includes real
Neo tests and separately marked lifecycle/receiving doubles; Salesforce/GitHub
Host integration uses local HTTPS fixtures, not a live service; GCS transport
fixtures are not new live-GCS evidence. Local Catalog/custody tests exercise real
SQLite/Iceberg/Parquet, not public approval or whole-phase funding. Their prior
receipts and source qualifications are not rewritten by this index.

The separate Local data facet still references the existing Arrow/Parquet and
managed-process contracts: schema/field IDs, absent versus explicit NULL,
binary64 and exact Unicode, duplicate/chunk/order/EOS laws, original backing
ownership and copy overlap. Catalog snapshot file order is not a query order
witness. The bounded whole-Relation implementation is not converted into JSON
streaming, a new channel or an all-MoonBit array. Python cancellation or channel
closure is not stopped-writer, noncommit, physical release or cleanup ACK.

The existing Sheets and Local data sidecars remain independent facets. This
intake adds no interface schema, generic scheduler, approval/recovery state
machine, alternate registry or product SSOT. Unknown bounds and unexecuted
physical paths remain unverified; successful syntax coverage cannot fill them.
