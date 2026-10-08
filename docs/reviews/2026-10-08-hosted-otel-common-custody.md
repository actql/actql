# Portable observation scope and custody

This component supports Hosted observability; it is not Hosted public-path
acceptance. SDK/exporter I/O, Workspace authorization, optional storage CAS,
Native interval observation, and Worker integration remain Host responsibilities.
Run execution, approval, publication, release, and Evidence capture are unchanged.

## Owner boundary

`host_observation` binds an already authorized Workspace, authority scope,
destination revision, disclosure revision, and purpose before aggregation.
The diagnostic scope key is not a CID or an authorization token. Customer
telemetry and service operations always have distinct scope keys.

Its opaque budget retains request identity and cumulative record/byte limits.
Only a freshly committed request can initialize absent optional custody. An
existing request with missing, malformed, foreign, or changed custody cannot
reset the allowance. The Host must suppress further optional observation and
keep execution going. A pre-Run request may use its existing request label;
neither a Run nor a Program CID is fabricated for a rejected check.

Charge precedes persistence and queueing. Queue overflow cannot refund the
Run allowance. Repeated facts suppress only diagnostic emission, never actual
execution or evidence. A storage error cannot make a charged fact deliverable:
the Host retains the charged snapshot or disables subsequent observation.

The snapshot is optional telemetry metadata, not a replacement execution
journal. The Host must bind physical storage to the original request and
perform its existing CAS/transaction checks before delivery. Different scopes
do not share a budget or an aggregate. Changing a scope on an existing request
does not replenish that request's cumulative allowance.

## Public adapter

`@actql/run-host-core/observation` exposes opaque scope/budget handles and exact
snapshot copies from the common owner. It has no Node imports, SDK globals,
network, timers, callbacks, or Run-state decisions. Exporter credentials and
URLs never enter this owner. The package's normal prepack generator builds
the runtime; ignored bundles are not committed.

The owner caps a record at 4,096 bytes, request custody at 2,048 records and
1,048,576 bytes, and a fact label at 512 ASCII characters. Hosts may use smaller
limits and must separately bound serialization, total queue memory, scope
count, in-flight exports, outbound windows, and shutdown. These limits do not
claim an invoice bound or complete tenant isolation by themselves.

## Focused verification

- `node scripts/local-checks.mjs test moon -- --target js src/host_observation`
- `node scripts/build-runtime-packages.mjs run-host-core` through the existing
  bounded local-check supervisor.
- `node scripts/local-checks.mjs test node -- packages/run-host-core/observation.test.mjs`
- `moon info src/host_observation src/client_values_host_abi` through the same
  bounded supervisor; generated interfaces are reviewed source.

Independent fixtures cover exact and one-short consumption, restart custody,
missing/corrupt custody, foreign Workspace/request/revision, repeated verified
facts, and forged adapter handles. They do not establish Worker/Native public
execution, collector delivery, or CI success. CI remains stopped.
