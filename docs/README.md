# Documentation

- [Specification](spec/README.md): normative language and protocol definitions.
- [Authoring guide](authoring.md): source syntax and common patterns.
- [CLI guide](cli.md): commands and usage.
- [Development](development.md): setup, verification, metadata updates and versioning.
- [Physical cost helper](physical-cost-usage.md): source-checkout serial latency estimates and explicit unknown-cost selection; no Connector dispatch or Plan admission.
- [Local Compute attempts](local-compute-usage.md): synchronous execution using completed producer inputs; no source acquisition or durable capture.
- [Rebuild-time connector contributions](connector-bundles.md): typed Compute manifests, fixed Host installations and separate Node transport composition.
- [Connector repository layout](design/connector-layout.md): implementation ownership, composition boundaries and enforced dependency rules.
- [Portable execution boundary](design/portable-execution-boundary.md): Core/Host responsibilities, explicit runtime initialization and invocation-scoped Workers execution; [Workers verification](../adapters/workers/README.md) documents local workerd commands and deployment exclusions.
- [Query adapter boundary](design/query-residual-execution.md): acquisition-specific preparation above the fixed-input row engine; opaque handles and cumulative guard measurement.
- [DuckDB execution boundary](design/duckdb-relation-execution.md): internal adapter responsibilities, exact type transport and source/Compute isolation; [Node Host usage and conformance](../adapters/connectors/duckdb/node/README.md) covers bounded acquisition/capture and completed-input Compute, not durable Program/Run execution.
- [Local inner join](design/local-relation-join.md): checked binary steps, stable pair ordering, cardinality validation and intermediate output limits; separate from multi-input Host dispatch.
- [Serial physical strategy boundary](design/physical-strategy-execution.md): checked data/control dependencies, completed-input transfers, physical reservations and unstarted-work revision rules; distinct from canonical Plan and Program publication.
- [Serial strategy application example](../adapters/connectors/duckdb/node/examples/README.md): user-supplied Program/Environment and trusted local DB through capture, shared-input Compute, re-estimation and diagnostic explanation; no test-fixture dependency or formal Program publication.
- [Extension policy](design/extension-policy.md): extension boundaries.
- [Implementation guide](design/implementation-port.md): component responsibilities and implementation order.
- [Reference Host](design/reference-host.md): durable execution and secure defaults.
- [Host authorization design](design/host-authorization.md): agreed execution-account and delegated-decision model; normative/wire migration pending.
- [OSS Host authorization draft](design/oss-host-authorization.md): CLI/embedded behavior, durable decisions and pending product choices.
- [Acceptance scenarios](../spec/product-decisions/SCENARIOS.md): complete Programs and expected behavior.

Specification documents have status `adopted`: they define the design.
Implementation conformance is established separately by evidence for an exact
set of contracts and execution profiles.
