# Conditional serial Relation allocation-capacity evidence

This extends the existing chain proof without changing production allocation,
reservation, lifetime or public interfaces. The guarantee concerns allocations
covered by the existing Host reservation, not process heap/RSS. It is a
**conditional upper bound**: child/base allocation bounds, exhaustive coverage
and the parent allowance have not become proved facts.

## Scope fixed before proof

`allocations.json` was committed before the model in `d57251d4e`. Its SHA-256 is
`4dfd632af58dd025e44661bc69be6a761328e6666fa6ee0efe78818d57ad2957`.
The gate requires that exact inventory; relabeling a request or shrinking the
inventory cannot discharge an obligation. The inspected main is
`01ee57ea17dd5ee9308360fd9744e335718283cc`.

The inventory includes every child Session/provider state, staged and completed
output, intermediate backing arrays, newly made exact edge wrappers, and parent
Refs/closures/children-array backing capacity. Borrowed external payloads are
charged to their existing owner; each newly allocated wrapper/copy is included.
Driver imports/final independent conversion have separate reservations in
`src/connectors/local/driver/managed_dispatch.mbt`; that whole Host envelope is
not proved by this theorem. GC/allocator metadata, fragmentation, stacks, code
pages and RSS are excluded from this unit, not from an allocation census by
renaming chain-owned objects.

## What is proved

`Capacity.lean` contains 14 theorems, checked at the existing Lean pin with
consumer-side expected types and `#print axioms`. Only `propext` and `Quot.sound`
may occur in dependencies. No custom axioms, unfinished proof or unchecked native
decision is accepted.

A registry contains unique physical allocation IDs, stable nonnegative sizes and
live predicates. Shared references do not multiply IDs; equal-value copies do.
At any phase, including handoff overlap and pending cleanup, assume:

1. Every live allocation is in the registry and covered by base, child or parent
   ownership. Borrowing does not erase coverage; a new copy requires a fresh ID.
2. The base retained allocations fit `base.retained_bytes`.
3. Each child's live allocations fit `child.retained_bytes + child.execution_bytes`.
4. Parent-control and uncovered edge allocations fit `count * 256`.

The theorem then establishes:

```
live allocation bytes
  <= base.retained_bytes
     + max(base.execution_bytes,
           sum(child.retained_bytes + child.execution_bytes) + count * 256)
```

The upper bound is intentionally conservative when several children share an
allocation. The live-byte observation counts it once; sums of child allowances
may count its capacity more than once and remain upper bounds. Releasing a
reference is not a proof that the allocation died. A confirmed decrease in live
IDs cannot increase live bytes; terminal or false/error cleanup alone is not such
a decrease. Arbitrarily many finite children and arbitrary sharing are permitted
by the model; this is not an arbitrary-DAG ownership theorem.

Mathematical checked addition preserves exact sums up to Int64 max and rejects
the next byte. The subtraction guard is equivalent only when the subtrahend is
nonnegative and representable. A nonnegative Int32 child count makes `count * 256`
fit Int64. Actual Int64 arithmetic and compiler representations remain connected
by finite boundary tests, not an implementation refinement theorem.

## What is still assumed

| Premise | Existing evidence | Undischarged obligation |
| --- | --- | --- |
| Child/base live-byte bounds | Guarded workspace/value ceilings and declared capacity formulas | A complete per-child allocation census and sizing derivation, including transient/copy growth |
| Physical identity/coverage | Exact producer bindings and physical material/holding identity | No production census maps every Session, closure and container allocation to model IDs/byte sizes |
| Parent `count * 256` | Added by `7c8342c0a811ad74f0db5dae373806d25a2f4ac7` for child sessions/provisional outputs/handles | No enumeration proves parent Ref/closure/array capacity fits the allowance on JS/Wasm/native |
| Post-Compute retention | Accepted output can intentionally retain upstream `_producer_inputs`; the Host makes an independent output conversion | Reservation-to-retained handoff must cover allocations until their actual last owner disappears |

`ExecutionCapacity` is documented as Host-private conservative container
allowances (`execution_capacity.mbt`, physical-strategy design). The presence of
the same 256 coefficient in the general node formula is not a chain sizing
derivation. Tests of the arithmetic formula cannot establish that derivation.
This PR therefore does **not** close an unconditional chain live-byte guarantee.

No arbitrary replacement constant is proposed as a proven fix. A separate product
PR is required if the inventory/sizing work establishes that reservation is short.
Its acceptance must enumerate parent allocations, bounded array growth and edge
wrappers, identify covered versus separately charged storage, derive an upper
bound for each selected runtime, update the existing reservation before resource
creation, reject arithmetic/envelope overflow, and retain exact/one-short and
pending-cleanup regressions. Increasing the literal without those grounds or
calling it a convenient logical charge is insufficient.

## Executed evidence, kept separate

* **Formal model:** conditional arbitrary-finite allocation union/reservation
  theorems; not the MoonBit implementation's byte sizing or lifetime proof.
* **Finite correspondence:** checked three-row TimeSeries/filter/select chains of
  lengths 2/3/4 through existing registration; actual child capacity sums; actual
  pair, cumulative, handle and exact/one-over Int64 boundaries; live predecessor
  during handoff and false/error cleanup. An execution-relation fixture inspects
  real backing-array identity for a borrowed view versus independent copy.
* **Existing ledger mechanism:** identity, shared holding, distinct copy,
  pending reservation and capacity/overflow rejection tests remain authoritative.
  This does not automatically attach a holding to every internal child container.
* **JS mutation detection:** max-child substitution, omitted retained capacity,
  omitted handles, unchecked overflow, premature cleanup success and aliasing an
  independent copy must fail running assertions. Native/Wasm mutation coverage is
  not claimed.

The inventory/gate rejects profile/provider/child relabeling, omitted assumptions,
unconditional or RSS claims, changed inventory, unrelated execution, missing
identity evidence and stale source/artifacts. Source/artifact hashes bind evidence
to code and do not discharge size assumptions. All old capacity/workspace,
algorithm, Store/process and backend tests remain; no test is deleted.

## Delayed-stop callback: separate runtime regression

`node proofs/relation-capacity/repro-delayed-stop.mjs` copies the fixed fixture
briefly into the real integration package, invokes **existing**
`prepare_local_compute_module(managed_providers=[family])` and
`local_module_managed_provider`, and retains the independent equality and
the execution log. Only its own newly created test copy is removed afterward.
The fixed fixture and reports remain. This is not accepted capacity evidence.

With Compute budget 1 and quantum 1, the callback runs Compute once, accepts
cancel, then confirms stop after three one-unit stop polls. The observed values
were child work 4 and parent work 3 before the accounting correction: the chain
dropped the final stop poll's work. The same fixture now requires child work 4,
parent work 4 and diagnostic cumulative work 4, with one Compute entry. This is
a registered callback-path runtime regression, not formal certification of
arbitrary delayed-stop providers or a new capacity scope.

The adopted contract makes `max_work` an admission budget for new Compute and
handoff. Mandatory stop work is counted and may make the cumulative total exceed
that budget; it cannot resume Compute or turn budget failure into success. There
is no independent stop budget. The existing execution owner performs checked
accumulation; diagnostic getters remain available after failure/close. Runtime
regressions also cover upper drivers, cleanup false/error, duplicate close and
sticky accounting errors. See [the accounting contract](../../docs/design/local-provider-work-accounting.md).

The prompt-stop pilot and its premises remain unchanged. Evidence gates still
reject an uncertified callback. Source-bound reports must be regenerated; the
runtime regression does not discharge allocation sizing or stop-liveness
assumptions.

## Reproduction

```
node --test proofs/relation-capacity/model.test.mjs proofs/relation-capacity/evidence.test.mjs proofs/relation-capacity/proof-check.test.mjs
node proofs/relation-capacity/check.mjs
node proofs/relation-capacity/repro-delayed-stop.mjs
node proofs/relation-capacity/mutations.mjs
node proofs/relation-capacity/run.mjs all
```

Use the pinned MoonBit toolchain and Lean `leanprover/lean4:v4.30.0-rc1`. Run one
gate at a time without editing the tree. Regenerate all final reports after every
mutation/reproduction batch: restored source alone does not ensure incremental
binary freshness. CI retains `.artifacts/relation-capacity/` beside both existing
evidence sets. Model, finite correspondence, JS mutation detections and the
corrected delayed-stop runtime regression are separate report categories.
