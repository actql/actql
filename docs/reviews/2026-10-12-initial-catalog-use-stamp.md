# Private initial Catalog-use preparation

## Original transaction and responsibility

`Journal::accept` delegates to the same existing acceptance implementation. Only the explicit private `accept_with_initial_catalog_use` path supplies its additional callback. The callback runs after the transaction's authoritative second dispatch read has proved absence, before inserting the initial dispatch and committing. The original canonical request bytes and initial marker are written in that same SQLite transaction. Normal accept, duplicate accept, restoration and cancellation-first admission never mint or backfill a marker.

The original request CID and canonical original request bytes bind Run, dispatch, task/attempt, Site generation, runtime and the other existing admission identities. No new public wire, CID or Run state is added. The marker's existing SQLite revision is initially zero and becomes one only through a successful first claim CAS. This is a private responsibility projection, not a language operation or another Owner.

A nominal claim is returned only after the claim commit and readback succeed. An uncertain commit returns refusal and does not reconstruct a new nominal claim from the stored marker. Already claimed, missing or foreign rows cannot issue another claim. The existing Site admission and transaction binding are rechecked before the CAS; a historical matching body alone is not current generation authority.

The existing Resource Owner must consume this same claim before selecting its original grant/use. `retain_initial_catalog_use` connects the same nominal use to #1497, with the existing exact grant/use/dispatch checks. It neither selects another grant nor grants permission to send. The subsequent original Host/Account/credential authorization, lifetime and revocation fences remain necessary. The actual Resource initial-claim installer is not connected by this unit; #1499 supplies the separate pre-send retention seam.

## Funding scope and unresolved installation

The explicit private preparation path takes the **actual original Run Ledger** and an explicit trusted Host-declared envelope. The existing `reserve_capacity` reserves retention and simultaneous workspace before constructing/writing the new private original-body projection. An envelope has no default or newly selected coefficient. Its record bound must fit the Journal's existing limit. Disk-record, retained-control/container and workspace ceilings must each be positive; their retained sum must not overflow. The reservation is `record_bytes + control_bytes` retention and separate `workspace_bytes` execution capacity. Those shape checks do not prove a physical footprint or establish a policy.

The Host caller must derive the Ledger from the original existing Run/capture Owner and supply the reviewed disk/container/control and scratch ceilings. A candidate wire, newly created replacement Ledger, mere body length or the positive-envelope predicate is not that trusted supply. This production supplier and its numerical cost policy remain **uninstalled and unaccepted**. Fixture envelope values exercise bookkeeping only, not a production coefficient, measured RSS or SQLite-page calculation. Production evidence-read remains default-deny. The actual Host must also retain the original Site-Journal custody/continuity: `open_journal` can create a new DB, so a fresh DB alone cannot prove first eligibility for a historical Run. The calling path must reject that missing original instead of selecting this initial preparation API. This installation guard remains incomplete; the replacement-credential-DB fixture below does not cover replacement of the entire Site Journal.

The same nominal custody is returned even when persistence or readback is uncertain. It retains the original `CapacityReservation`; no unconditional settlement, new send attempt or failed/sent Provider result is invented. Successful duplicate accept makes no second custody or reservation. There is no cleanup shortcut in this preparation API. Calling integration must preserve the original custody until actual physical/control cleanup and connect existing settlement/reconstruction without double charging or returning capacity early. That final cleanup/restoration connection remains incomplete and must be finished before production installation.

## Finite validation and remaining connection

| Boundary | Required result | Current evidence |
| --- | --- | --- |
| Initial new / duplicate | Same transaction contains both rows; one original reservation; no duplicate marker | SQLite fixture compile-only |
| Legacy absence | Duplicate acceptance does not backfill; no fresh claim | SQLite fixture compile-only |
| Funding / save failure | No successful initial admission on refusal; funded responsibility survives uncertainty | SQLite fixtures compile-only |
| Claim commit reply lost | Reopen observes the claimed original; no reissue/reclaim | SQLite fixture compile-only |
| Replacement credential DB | Empty independent DB does not reset the original Site claim | Journal counterexample compile-only; actual Resource continuity not yet accepted |
| Cancellation-first / Site generation change | No new eligibility; original marker and funding preserved | SQLite fixtures compile-only |
| Current Account/credential authority loss | Final existing Resource fences prevent GET; original custody retained | Resource connection/physical validation pending; #1499 fixture compile-only |
| Original cleanup / reconstruction | Keep the same charge pending, settle only on confirmation, no second charge | Calling integration pending |

The envelope refusal/acceptance predicate and its fixture are selected on Native with their actual implementation. The portable JS fixture exercises only Unsupported-target refusal. Neither establishes Native execution or physical funding. The envelope fixture and eight strict SQLite fixtures compile; fixture absence would fail execution rather than silently pass. Matching Journal and existing Resident caller compile are type evidence only. Actual Native, Provider, public approval/Effect/Result/release, Preview, Heavy and Hosted CI remain unexecuted. Source and failure receipts remain distinct from physical acceptance.

Final merge target: OSS main. The base includes Root's #1497 Native helper correction. D's Resource/Local assembly and submitted #1499 heads are not modified.
