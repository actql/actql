# Runtime bundle components in the initial 0.1 contract

The native DuckDB Site must load library bytes bound by its admitted signed
runtime bundle. A caller-supplied path is not sufficient authority. This is a
remaining acceptance requirement of the initial ActQL 0.1 implementation, not
a reason to introduce a bundle-only 0.2 contract.

## Version decision and compatibility audit

The current 0.1 manifest binds only one executable through `component_cid`
and `component_bytes`. It does not bind the DuckDB library. The earlier
bundle-only 0.2 proposal was withdrawn before publication. The existing 0.1
body in main is an incomplete development contract, not a completed DuckDB
bundle guarantee.

The correction must define one closed canonical 0.1 body with a component
inventory, including exactly one runtime executable and any library the
selected Site will load. Its signature preimage and CID must be recomputed
from that exact body. All current writers, readers, Store implementations,
schemas, pins and independent vectors must move together. The previous
single-component body must not be admitted by defaulting a missing inventory.

Current repository fixtures and tests contain signed single-component bodies,
including native Store restart cases. They must be regenerated as independent
expectations. This repository inspection does not prove that no external
installation persisted or distributed the old body. Before rollout, inventory
those installations. If any exist, preserve their exact historical records
and make an explicit migration or version decision; never overwrite their
body, CID or signature, and do not grant them current DuckDB execution
authority just because a historical signature verifies.

## Completion conditions

Each signed component needs exact byte verification, bounded physical custody,
capacity accounting, durable retention, release and cleanup. The Node and
native bundle Stores currently own one component; a multi-component manifest
must remain inadmissible there until the complete physical lifecycle exists.
The native loader must consume the admitted library generation, not an
independent path argument, and must not create unaccounted temporary copies or
lose cleanup responsibility. Existing single-component installation must
also use the corrected canonical 0.1 body.

Independent body/CID/signature vectors, restart, rollback, corruption,
capacity and cleanup tests, plus the final native, JS and Workers gates are
required before the DuckDB bundle requirement is complete. Fail-closed
rejection during migration is not completion.
