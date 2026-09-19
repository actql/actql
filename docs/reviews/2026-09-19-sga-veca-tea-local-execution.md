# Complete portable Local execution for SGA, VecA, and TEA

Status: active implementation work order.

## Fixed authority

The implementation baseline is
`0886df5ab75ff77edcd68291470f487346fc1cc4`. Its Linux CI run
`35414883771` completed successfully in all five jobs. The normative
inventory is frozen from the specification and machine contracts at that
revision. A later feature on `main` does not enlarge this milestone
automatically. Corrections to contradictions or defects in the frozen scope
remain in scope and must be recorded in the coverage manifest.

The implementation must complete the normative SGA, VecA, and TEA families,
their required Carrier bridges, and the VecA scalar expressions. Existing
RelA execution remains part of the final portable Local claim.

## Required result

Every supported authored path must use this boundary:

```text
Program and admitted inputs
  -> checked typed occurrences
  -> canonical typed AoA
  -> common ordered task inputs
  -> capability and representation selection
  -> managed Local execution
  -> common completion
  -> real downstream computations
  -> optional formal Relation publication
  -> independent release and final reclamation
```

An isolated kernel, a checker-only path, or an unsupported rejection does not
count as execution support.

## Frozen decisions

### Canonical lowering and inputs

- Repair the AoA inventory before implementing family kernels. Each operation
  binds its input and output Carrier, parameters, obligations, and laws.
- Distinguish a missing-contract correction from an incompatible change.
  Change a version only when the repository version policy requires it.
- When a canonical body changes, update its CID, pins, metadata, and
  independent vectors in the same change.
- A finite input list is one typed authored occurrence. Its ordered edges keep
  position, semantic role, producer, output port, exact binding, authority,
  and logical charge. Repeated material in different positions is not
  deduplicated.
- The common DAG owns the ordered input structure. Family operation names do
  not appear in the generic scheduler.

### Carrier completion and storage

- One common lifecycle owns Relation, Graph, Events, and Vectors completion.
  Carrier-specific typed views expose content without erasing the Carrier
  contract.
- Relation-specific schema, row counts, and measurements are not universal
  Carrier requirements.
- A Carrier does not require a dedicated physical allocation. Immutable
  columns, buffers, and indexes may be shared when generation, view, lifetime,
  and accounting remain exact.
- A Bridge creates an independent output generation. It may share storage but
  never relabels the source generation or invents evidence.
- Representation, conversion, index, evidence, capacity, failure, and known
  publication requirements are selected before execution. Bounded adaptive
  work within that plan is allowed; retrying another kernel after execution
  failure is not.

### Identity and evidence

- Semantic entity IDs, operation occurrences, material generations, logical
  content CIDs, physical integrity, and publication identities remain
  distinct.
- Logical content CIDs are established only when a normative law, selected
  consumer, or publication boundary requires them. A caller omitting a CID
  request cannot waive a Carrier law.
- A late identity request receives separate admission against the exact live
  generation and view. Failure of that request does not mutate an earlier
  valid completion.
- Graph projection, event identity, and vector identity use their registered
  preservation laws and issuers. A row reader or physical digest is not proof
  of a semantic projection.

### Portable numeric execution

- Multiple VecA kernels are allowed, but a completely conforming portable
  implementation must exist for every normative case.
- Independent vectors cover binary32 admission, binary64 operation order,
  ties-to-even rounding, subnormal values, overflow, signed zero, square-root
  boundaries, nulls, and non-finite failures.
- FMA, reassociation, implicit SIMD behavior, or a host tolerance cannot
  replace the prescribed arithmetic.
- An optimized candidate that cannot satisfy the exact profile is rejected
  before start in favor of a conforming candidate.

### Bounded progress and cancellation

- Kernel state, semantic progress, and common execution control are owned by
  MoonBit. Environment adapters provide physical yielding, worker transport,
  clocks, and I/O.
- Start and resume calls are bounded. A resume reports monotonic progress and
  consumed work and returns Continue, Complete, or Failed.
- Intermediate state is private, attempt-bound, non-persistent, and never a
  completion. Concurrent, reentrant, and stale-token resumes are rejected;
  the next valid resume after Continue remains allowed.
- Cancellation prevents further computation but permits the dedicated cleanup
  path. Logical work is not refunded.
- Stop confirmation means the operation will no longer access material.
  Reclamation confirmation means allocations, pins, and reservations have
  been released. Cleanup can fail after stop; the unreclaimed responsibility
  and reservation then remain visible.
- JavaScript execution must yield in a way that lets cancellation and deadline
  events arrive. Repeated resolved promises are not sufficient.
- Potentially large sorting, hashing, validation, index construction, Bridge
  conversion, and identity work must not be hidden inside one unbounded
  synchronous call. Define non-interruptible input, work, and allocation
  bounds and measure cancellation-to-stop latency on supported environments.
- Existing long-running RelA kernels are included in this requirement.

### TEA input scope

- TEA 0.1 covers finite snapshots and bounded changes observations.
- Transport pages that form one logical observation do not reset window,
  session, or sequence semantics. Different page splits of the same bounded
  input must produce the same values, order, and evidence.
- A changes checkpoint advances only at the existing successful commit
  boundary, not after page receipt or a kernel step.
- Watch mode, unbounded state, processing-time substitution, persistent
  multi-observation kernel state, and restart recovery are outside this scope.

### Publication

- Every Relation-valued family result and every Carrier-to-Relation Bridge
  connects through the existing Effect-free Named Result publication and read
  path.
- Graph, Events, and Vectors are not published through a new Local wire.
- Publication retains its ordering, identity, authority, storage, and atomic
  commit requirements. Internal completion is not publication success.
- Effect execution remains outside this milestone and is never silently
  ignored.

### Packaging

- Complete language checking and contract metadata remain common.
- Carrier lifecycle, ordered task inputs, and execution control are common
  runtime packages.
- SGA, TEA, and VecA kernels and providers are separately registered packages.
- Bridge execution is separately registered from family algorithms.
- A RelA-only execution artifact excludes unselected family kernels. Verify
  both the import graph and generated artifact; factory non-invocation or a
  string search alone is insufficient.

## Coverage and acceptance

Every formal operation and variant must be classified. A principal variant is
any combination that changes source form, Carrier inputs, arity, semantic
policy, output Carrier, lowering, kernel path, evidence, or lifetime strategy.

- Every author-visible operation and source form has a standard Host E2E.
- Every formal branch value appears in at least one standard Host E2E.
- Interacting branches that change behavior or code paths have a dedicated
  fixture.
- A successful Relation path performs two real downstream computations.
- A successful Carrier path performs one same-Carrier computation and one
  formal Bridge followed by a real computation.
- Consumer lifetimes overlap. One consumer's release or ordinary failure does
  not invalidate the other, and the final reference reclaims storage once.
- A failure-only branch verifies the prescribed failure, absence of completion,
  and cleanup through the standard Host.
- Type, null, parameter, and boundary classes use independent expectations on
  JS, Wasm, and native.
- Equivalent-path claims identify the shared lowering, kernel, evidence, and
  lifetime code plus the fixture that reaches it.
- Fixture registration, suite connection, and actual results are tracked by
  the manifest. An unclassified branch or missing fixture is a gate failure.

Resource acceptance includes checked arithmetic, admission before large
allocation, exact/one-short ceilings, partial-construction cleanup, bounded
search separately from output size, and deterministic work/allocation
diagnostics. Wall-clock measurements are evidence, not universal thresholds.

## Delivery sequence

1. Freeze the normative manifest and current gap report.
2. Reconcile canonical AoA inventory, arities, contracts, and pins.
3. Generalize common completion and ordered task inputs.
4. Prove bounded progress and cancellation with an early long-running slice.
5. Connect the minimum Carrier, Bridge, and isolated package path.
6. Implement early SGA, VecA, and TEA vertical slices.
7. Complete all operations, variants, and VecA scalar expressions.
8. Close cross-family composition, two-consumer lifetime, and publication.
9. Close resource, failure, cancellation, and portability matrices.
10. Verify all acceptance gates and Linux CI on one integrated SHA.

Shared contracts are committed independently and integrated early after
review. Each such commit must run affected Relation, DuckDB, Workers,
publication, independent Connector, generated-interface, portable API, and
three-target regressions. A public low-level API change includes the
compatibility decision and all migrations in the same change.

## Completion claim

Completion requires all normative RelA, SGA, VecA, and TEA operations,
required Bridges, and VecA expressions to execute through the portable
standard Host; formal Relation publication; cancellation delivery and kernel
observation; separate stop and reclamation confirmation; isolated family
artifacts; bounded resource behavior; and successful acceptance tests plus
Linux CI on one SHA.

Remote and Cloud deployment, new SaaS Connectors, Effect execution, ANN,
embedding generation, watch mode, and unbounded streaming are excluded.
