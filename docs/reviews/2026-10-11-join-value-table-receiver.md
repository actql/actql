# JOIN value-table receiver preservation

Status: Frontend correction, public acceptance pending at submission. This unit depends on the JOIN row scope work in #1361; it does not complete the broader language surface.

## Fixed counterexample

```sql
SELECT r AS value
FROM (SELECT 7 AS id) l
CROSS JOIN (FROM UNNEST([1,2]) element) r MAX_OUTPUT_ROWS 10
ORDER BY value
```

The independent expected Result is `[{"value":1},{"value":2}]`, with one non-null number column. A named value table denotes its original element, rather than a row containing the compiler's private element slot. The same receiver in `ON l.id = r` denotes that element. Nullable objects retain their original root nullability; adding `WITH OFFSET` instead makes an ordinary row with declared fields.

At parent `5bdb523c103bfe5317ce2ed086b878d827b9b5d9`, an independent JSON Program passes the ordinary checker, while both authored text cases reject with `UnknownColumn` (`run-M4nRlA`: 1/3 passed). The initial test also retained the failure (`run-raKQRd`); the diagnostic-only test compile failure in `run-6dThS6` was caused by using Debug on an enum without that trait and is not product evidence. Baseline tests are retained separately before the product correction.

## Cause and correction

`lower_script_join_relation` forwarded only the first producer's `JoinChainScope`. The chain lowerer rebuilt every right operand from physical field names and a relation qualifier. This discarded the right derived query's value receivers, declared columns, range snapshots and star layout. A derived alias may be retained inside that scope rather than in `JoinPart.source_alias`.

Forward each right producer's existing scope, use its logical names for ON/USING and visible columns, and remap its existing slots through the ordinary JOIN select. Resolve value receivers on either operand before ordinary columns. Do not infer value-table kind from row contents, private slot spelling or the number of columns. Keep output root/field nullability, equality, key evidence, limits and execution in their existing common owners. The whole JOIN output remains an ordinary relation.

No parser vocabulary, common value/JOIN contract, serialization, owner or grammar manifest changes are needed. The current grammar and its independently recorded Run/Unit/ResultPlan identities remain pinned. The independently authored public inventory is updated only for new registrations, not from product results.

## Verification boundaries

- Corrected focused JS tests: 31/31 (`run-uVSVMh`), covering both scalar operands, receiver/column collisions, nullable scalar and object roots, LEFT extension, OFFSET row kind, prior ordinary JOIN rows, RIGHT/FULL/USING and UNNEST continuation.
- Independent fixture/inventory Node checks: 48/48 (`run-ppAaBw`).
- Exact rejection tests retain `Expression(UnknownReference)` for the displaced inner receiver and `UnknownColumn` for scalar star. Duplicate range names retain invalid-input refusal.
- Nine new normal and three new refusal cases are registered in the existing packed composition selection and the normal corpus. JSON control, nulls/duplicates, empty input, quoted Pipe names, ON, null extension, nullable objects and OFFSET use authored rows, type contracts and column order. The harness does not patch the generated Program.
- Exact submitted-SHA five-package Local/HTTPS execution is pending until terminal receipts are checked. CI, all Core/targets, other packed cohorts and vendor differential execution are unverified. No merge is performed.
