# Analytic partition property paths

This unit connects already-parsed analytic partition paths to ordinary checked
property expressions. It changes only Frontend source representation, lowering
and independent acceptance fixtures. It does not change a common execution
Owner, key equality, capacity ceiling, wire contract or saved-value format.

## Counterexample and reference

```sql
SELECT id,
  ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos
FROM objects
ORDER BY id
```

At main `64046e37a1cadb2148edeab7cbf85b96d125b518`, the parser admits this
path but lowering requires it to resolve as one exact visible column. An
independent complete machine Program derives the nullable string property,
partitions on that private field, runs the ordinary analytic operation and
removes the field before publication. The ordinary checker accepts that Program;
the source compile fails before this fix (`run-sH5Ozc`, 0/1).

The selected [GoogleSQL window reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls)
defines partition expressions in the SELECT input scope; sibling SELECT aliases
are not visible inside OVER. This unit closes property paths within the existing
path grammar. Arbitrary partition expressions, named windows, optional ordering,
frame defaults and the wider GoogleSQL type profile remain separate coverage
items. This is not a claim of complete GoogleSQL analytic conformance.

## Connection

- Partition paths retain an expression owner with their actual token span and
  quoted name parts. No source printing/reparsing or synthetic source position
  is involved. The public source AST interface is regenerated with `moon info`.
- The existing analytic key lowerer resolves the input column/range prefix and
  delegates the remaining property path to `append_with_properties`. The common
  checker owns closed-object membership, null propagation and equality-key type.
- PARTITION and OVER ORDER share the existing evaluated-expression table and
  reserved private slots within one immutable input scope. Repeated partition
  keys remain in their authored order; a shared property is derived once.
- SELECT siblings cannot change the receiver. Pipe SET can change current
  columns while an existing range retains its original snapshot. AS replacement
  still removes the old range. Ordinary direct partition columns use no derive.
- Final projection removes private keys before rows and Result descriptions
  are published. No proof is inferred from an alias or fabricated by Frontend.

Source grammar and common Program semantics are unchanged, so this unit does
not mint a new grammar/registry/law CID or regenerate independent CID vectors.

## Independent obligations

The acquired Source fixture is unsorted and includes an excluded id=0 row.
Original payload buckets are A for ids 2,4; B for id 1; NULL for ids 3,5
(one NULL receiver, one NULL field). With ascending id within each partition,
the public positions by id are `[1,1,1,2,2]`. The other object has buckets A for
ids 2,3 and B for ids 1,4,5, giving `[1,1,2,2,3]`; this distinguishes input
receivers from colliding SELECT aliases and modified current columns.

The registered normal corpus includes a complete independent JSON control,
SQL property partitions, quoted qualified Pipe paths, shared/repeated keys,
SELECT alias collision, SET snapshot/current comparison, empty typed input and
an unchanged direct-column control. Every case compares exact public rows and
ordered `Result.describe().columns`; no emitted Program is patched by a test.
Acquisition, same-request resubmission, attach and reread use the existing public
acceptance checks. Refusals cover missing members, scalar receivers,
non-groupable objects, sibling aliases and removed ranges before Run admission
and provider I/O.

The source AST origin test and six new lowering tests passed. Existing analytic
callers also passed: `run-5in1Hw`, source origin 1/1, query_program analytic
selection 22/22, authored fixture/public profile Node tests 9/9. An earlier
post-fix comparison (`run-Vd7i0u`) found an authoring error in the independent
Program's id (`fixture.query_pair` rather than the Context's `fixture.pipe_slots`);
correcting that identity changed no expression, row, type, order or ceiling.

## Public verification

Use one normal clean-HEAD five-package producer and the ordinary external
consumer, serialized through the repository local-check guard:

```sh
node scripts/packed-client-packages.mjs <outside-checkout-directory>
ACTQL_PACKED_CLIENT_PACKAGES=<outside-checkout-directory> \
  node scripts/test-packed-public-query.mjs --analytic-partition-property-only
```

All new cases are registered in the full normal corpus as well as this focused
selection. The existing analytic-order installed profile and 512 MiB execution
budget are unchanged. Record the tested clean SHA, producer manifest, five
tarball digests and consumer evidence in the PR/handoff; parser/checker success
alone is not packed Local/HTTPS execution evidence. Full Core, Native, Wasm,
full packed acceptance and performance are not local obligations for this fix.
Hosted CI and content review remain separate from local success. No merge or
manual CI rerun is performed by B.
