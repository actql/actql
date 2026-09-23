# Runtime bundle components in the initial 0.1 contract

The native DuckDB Site must load library bytes bound by its admitted signed
runtime bundle. A caller-supplied path is not sufficient authority. This is a
remaining acceptance requirement of the initial ActQL 0.1 implementation, not
a reason to introduce a bundle-only 0.2 contract.

## Version decision and compatibility audit

The earlier 0.1 body bound only one executable through `component_cid` and
`component_bytes`; it did not bind the DuckDB library. The bundle-only 0.2
proposal was withdrawn before publication. The corrected 0.1 body has one
closed `components` array. Entries are ordered by unique role and contain
`bytes`, `cid`, and `role`; exactly one `runtime_executable` is required.

The signed preimage and CID are computed from that exact body. The prior
single-component JSON body is not admitted by defaulting a missing inventory.
The old single-component API now prepares a one-entry inventory. It does not
give a DuckDB Site authority to load an unbound library. Fixed native test
signatures and CIDs have been regenerated independently for the corrected
body. The native Store now retains the component bytes as one bounded physical
allocation, concatenated in the signed role order. Signed lengths frame the
allocation, and each component is hashed independently before activation.
Its install command accepts an exact `role=name` mapping for each component.
The Node Store still rejects a multi-component inventory. Native DuckDB
execution also remains blocked until its loader consumes the Store-owned
library component rather than an independent path.

Repository fixtures and tests include signed single-component bodies,
including native Store restart cases; those vectors were regenerated as
independent expectations. Repository inspection does not prove that no external
installation persisted or distributed the old body. Before rollout, inventory
those installations. If any exist, preserve their exact historical records
and make an explicit migration or version decision; never overwrite their
body, CID or signature, and do not grant them current DuckDB execution
authority just because a historical signature verifies.

## Completion conditions

Each signed component needs exact byte verification, bounded physical custody,
capacity accounting, durable retention, release and cleanup. Native custody
uses one allocation for the complete ordered inventory, so reclaim and
capacity account for the whole bundle rather than an untracked sidecar.
The Node Store must remain fail-closed for multi-component manifests until it
has a corresponding physical lifecycle.
The native loader must consume the admitted library generation, not an
independent path argument, and must not create unaccounted temporary copies or
lose cleanup responsibility. Existing single-component installation must
also use the corrected canonical 0.1 body.

Independent body/CID/signature vectors, restart, rollback, corruption,
capacity and cleanup tests, plus the final native, JS and Workers gates are
required before the DuckDB bundle requirement is complete. Fail-closed
rejection during migration is not completion.
