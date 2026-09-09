# Acceptance material

The [specification family](../../docs/spec/README.md) owns the design.
These cases and vectors define independent acceptance expectations.

- `acceptance-cases.json`: 253 behavioral acceptance cases.
- `SCENARIOS.md`, `SCENARIOS.json`, `examples/`: ten complete Programs and synthetic Catalog/Host assumptions.
- `IDENTITY_DEPENDENCIES.json`, `REFERENCE_HOST_PRESET.json`: identity dependencies and Host fixtures.
- `d11/`: ordered derive and field-selection examples and semantic vectors.
- `reference/`: direct/extracted graph expectations and symbolic evidence bundles.
- `traceability.json`, `adoption.json`, `CHANGE_REGISTER.json`: requirement and decision mappings.

The source syntax uses [stages](../../docs/spec/language.md#stages),
[derive](../../docs/spec/language.md#derive), and explicit select.
The stage execution contract is [Run Graph](../../docs/spec/protocols/run-graph.md#stage-lowering).

Acceptance definitions are not execution reports. Synthetic contracts and
authentication are fixtures, not provider or Host authorization. Execution
verification includes checking, capture, crash, recovery and cross-target tests.

Automatic compatible Connector-lock renewal and cross-Run model cache are
outside the adopted feature set.
