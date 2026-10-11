# JOIN ON ordinary range precedence

Status: local Frontend correction; packed acceptance and hosted CI are separate evidence.

## Counterexample and existing contract

```sql
SELECT l.id
FROM (SELECT 1 AS l, 2 AS id) l
JOIN (SELECT 1 AS id) r ON l = r.id MAX_OUTPUT_ROWS 10
```

The bare `l` denotes the complete ordinary row, not its number column `l`.
The existing range rule in `docs/spec/query-text.md` applies to JOIN expressions;
column selectors such as USING have a separate lookup contract. The common JOIN
key contract (`value_contract.key_comparable` and `relation_join_shape.check`)
does not admit object keys. Therefore this text must refuse the unsupported
whole-row key rather than become the valid, semantically different `l.l = r.id`.
This unit does not add object-key comparison or redefine common equality.

At baseline `3591781012eb38bb8ae829e6abf9d75634e91872`, three exact refusal
regressions fail while the qualified/USING controls pass: `run-nz2E8e`, 1/4.
These are compiler regressions, not a claim of incorrect published rows at that
baseline. The unchanged baseline test source is retained separately. Additional
diagnostic-test compilation failures are test-development evidence only.

## Minimal correction

`join_requires_group_scope` now examines ON in its actual operand range scope,
so the specialized column path cannot reinterpret an ordinary range name.
`join_chain_reference` resolves admitted value-table receivers first, then
refuses a bare ordinary row key before looking for same-named scalar columns.
Qualified fields and USING retain their existing column resolution. No changes
are made to parser vocabulary, common checker, execution owner, identity,
capacity limits, serialization or grammar pins.

## Independent checks and public acceptance obligations

- Focused JS: 24/24, `run-kmZtb2`; ordinary left/right, quoted Pipe CTE,
  direct and script entry points, qualified/USING controls, existing value-table
  keys, alias ordering and FULL/USING callers.
- Independent fixture/inventory Node checks: 49/49, `run-3tZhJH`. Formatting
  and diff checks pass. Authored inventory counts are registration, not execution.
- A hand-authored object-key JSON Program rejects under the ordinary checker;
  the same independent declared object/number contracts yield precisely
  `IncomparableKeys("row", "id")` at the common JOIN boundary.
- Four authored positive public cases include an independent scalar-key JSON
  control, qualified left/right fields and a colliding USING column. Four typed
  refusals cover ordinary operands, quoted CTE and an acquired Source.
- The existing composition and normal corpus registrations compare Named
  Result rows, types and column order without repairing generated Programs;
  refusals must show zero durable Run admission and zero provider I/O.
- Packed Local/HTTPS requires normal five-package production at the clean
  submitted SHA, digest correspondence and complete terminal receipts. Until
  checked, this is pending. Hosted CI, full Core, other backends, other packed
  cohorts and vendor differential execution are unverified. No merge is made.

The parent value-table scope correction is #1364. Its exact prior SHA evidence
must not be represented as this branch's or the updated parent's success.
