# Local Compute RelA completion plan

Date: 2026-09-18. Owner: Local Compute.

Fixed baseline:
`5a305f3ce5cdac421985fb9a71878bc22af51237`.

Paired plan:
`actql-lowering/docs/reviews/2026-09-18-engine-site-implementation.md`.
Prerequisite:
[retained correctness and the Local Compute boundary](retained-correctness-local-compute-readiness.md).

## 1. Objective

Complete Local managed execution for every author-visible RelA operation that
the fixed normative specification and machine contracts define. The normative
inventory, rather than the checker's current implementation, defines the
scope. A checker omission is a shared implementation gap; it does not shrink
the Local completion target.

For every operation and major variant, the required path is:

```text
author source
  -> checked operation
  -> common typed lowering
  -> standard Host candidate selection
  -> Local execution
  -> managed completion
  -> two downstream Computes
  -> independent consumer release
  -> final reclamation
```

A kernel call by itself is not support. Support includes meaning, ownership,
admission, measurement, completion, downstream use, and lifetime management.

Formal Named Result publication is Engine milestone E4 and is not part of this
completion claim. Local must nevertheless preserve an actual publication or
identity requirement and reject an incompatible candidate before execution.
It must not downgrade that requirement to an internal completion.

## 2. Normative scope

The author-visible RelA set has 29 operations:

```text
filter select rename drop derive sort take top_k top_k_by row_window
window_group lag watermark_rows pivot unpivot json_pick unnest join nest
group distinct dedupe_rows assert_rows append values except intersect
cross_join analytic
```

The machine-readable coverage manifest is
[2026-09-18-local-compute-coverage.json](2026-09-18-local-compute-coverage.json).
It records the source operation, canonical operation, variants, current
layers, fixtures, and explicit gaps. The manifest is checked against the
normative operation inventory and canonical mapping; it is not generated from
Local implementation code.

The independent
[normative scope](2026-09-18-local-compute-normative-scope.json) freezes each
operation's variants, applicable type classes, and semantic obligations at the
baseline. Status entries must match that scope exactly. Evidence is not a file
existence claim: every record binds an exact test ID, its registered execution
suite, and its targets. A fully complete operation must additionally account
for every normative variant, type class, and obligation, and two-consumer
completion requires an actual standard-Host fixture.

Coverage states have these meanings:

| Normative and implementation state | Treatment |
| --- | --- |
| Defined and accepted by the checker | Required Local scope |
| Defined but rejected by the checker | Required shared implementation gap |
| Explicitly future or reserved | Outside this fixed scope |
| Accepted but normatively unclear | Contract inconsistency to resolve first |

Operation names are only rows in the matrix. Completion also requires every
normative variant, allowed operation/type combination, nullable and compound
keys, parameters, ordering, failures, demand, and capacity obligations.

## 3. Ownership and shared boundaries

Local owns its candidate compatibility, physical kernels, Local storage
choices, operation tests, and performance evidence. Common typed lowering,
connector admission, Host selection, attempts, managed completion, retention,
and publication remain shared Engine boundaries.

Before changing a shared boundary, Local informs the Engine owner of:

1. the API to change;
2. the missing fact and concrete counterexample;
3. why the change is required;
4. the files expected to change.

Local may prepare the implementation and tests, but the shared change remains
an independent semantic commit. Local-specific kernel work is not mixed into
that commit. Local never compensates for a missing boundary by traversing
frontend syntax, reconstructing ownership, adding a second candidate chooser,
or defining a second completion model.

Parallel integration compares the contract and content, not merely commit
identifiers. Rebase is permitted only while this branch is unpublished and
single-owner. Every integrated boundary change receives a standard Host E2E
test even when no semantic change was intended.

## 4. Lowering and kernel policy

The normative specification, machine contracts, and common typed lowering are
the semantic authority. Existing `execution_relation` evaluators are preferred
reuse targets and useful comparison implementations, but are not themselves
the specification.

Missing behavior may be implemented by extending an existing evaluator or by
adding a Local physical kernel. Both must consume the same checked typed view,
preserve ownership and obligations, and use common completion. A Local kernel
may choose a different layout or algorithm; it may not define a different
meaning contract.

Candidate fallback occurs only before execution starts. A semantic failure,
budget exhaustion, cancellation, or physical failure after start is reported
as that attempt's outcome and is never hidden by retrying another kernel.

Conformance uses independent expected results and counterexamples. Differential
comparison is additionally used where two implementations support the same
scope, but agreement between implementations is not semantic proof.

## 5. Storage and lifetime

Independent generations mean independent holding and use rights, not mandatory
deep copies. Initial implementations may share immutable managed storage.

The following rules apply:

- An output retains managed immutable storage, not a temporary input read.
- Holding is secured before completion is published.
- Releasing an input scope does not invalidate a retained output.
- A physical allocation is reserved once and remains reserved through its last
  holder. Per-consumer logical charging remains independent.
- A small view retaining a large backing allocation charges the complete
  allocation plus any selection or index storage.
- A planned copy may reduce retained capacity, but its allocation, copy work,
  and peak overlap are charged before it begins.
- Failure and cancellation release only references acquired by that work.
  Cleanup responsibility remains until actual access has stopped.
- The final reference reclaims the allocation exactly once.
- Corruption or loss of trust in shared storage invalidates every dependent
  view; an ordinary consumer failure does not.
- A transfer to another Site is not implemented by relabelling a handle.

If current shared storage cannot express these rules, storage ownership is a
separate shared-boundary commit rather than a Local-only refcount subsystem.

## 6. Measurement and accounting

Local computes only measurements required by the common contract, mandatory
Host policy, selected request, or known downstream requirement. It does not
precompute every possible statistic, canonical byte count, or content identity.

Completed-output facts are separated from execution accounting:

- exact row count, measurements tied to the output view, and retained
  allocation identity describe the completed output;
- scratch, input/output overlap, peak capacity, and execution work belong to
  the attempt and settlement record.

A physical amount is labelled as either an exact guaranteed measurement or a
contract-safe reservation bound. Measurement reuse additionally binds the
contract, schema, view, generation, unit, selected columns, row selection,
ordering, duplicate treatment, and derivation. Input totals are not exact
output totals after filtering merely because they are conservative.

Generation-time measurement is preferred but is not an absolute one-pass
rule. A later required measurement may scan retained data after a separate
admission. Failure of that later request does not invalidate the original
completion. A known guard is enforced before completion rather than discovered
after publication.

## 7. Failure and diagnostic preservation

For the same semantic input and request, Local preserves every normatively
specified value, failure, priority, demand range, logical occurrence, and
ordering rule. It does not evaluate non-demanded expressions to search for
errors, and filtering does not hide validation that the input contract requires
over the complete source.

If the specification determines a first failing row or error precedence, a
kernel follows it even when its physical discovery order differs. Otherwise,
different physical traversal order need not manufacture the same incidental
representative error. Internal array or SQL positions are translated to the
author-visible operation occurrence and any required logical row or expression
location.

Semantic work, demand, and limits remain charged after optimization. Physical
memory exhaustion, deadlines, and cancellation need not happen at the same
instant across targets, but must not be disguised as semantic failures.
Cleanup occurs after stop confirmation. Cleanup failures supplement rather
than replace the primary failure.

## 8. Target and type portability

Every operation/type/variant combination admitted by the fixed contracts is a
JS, Wasm, and native completion requirement. Host-specific Node, filesystem,
or DuckDB facilities are not portable-kernel requirements.

Type support is operation-specific. Being able to retain a value is distinct
from being allowed to compare it, order it, use it as a join or group key, or
aggregate it. Fixtures use independent expected values for ranges, precision,
overflow, NULL behavior, text ordering, temporal boundaries, compound keys,
and parameters. Target agreement alone cannot validate a shared mistake.

## 9. Performance floor

Semantic support and performance-floor support are reported separately, and
both are required for completion. Let:

- `N` be input rows;
- `B` be processed value volume;
- `E` be required expression-evaluation work;
- `R` be output volume.

Unary operations do not add avoidable repeated scans or copies over these
quantities. Stable sorting uses `O(N log N)`-class comparisons, accounts for
comparison cost and auxiliary storage, and preserves logical input order for
ties. A stable sort followed by limit is an acceptable first TopK kernel.

Applicable equality joins have an indexed path. Output caused by duplicate-key
multiplicity may itself be quadratic, so complexity is stated with `R` rather
than falsely claimed linear. Distinct and group do not linearly search the
entire prior history for every row. Unnest scales with parent input and actual
expansion, detects bound arithmetic overflow, and does not allocate the maximum
possible expansion in advance.

Every internal structure uses existing logical and physical limits. Allocation
is admitted before it occurs and long loops check interruption. Each algorithm
records applicability, complexity, peak retention, and fixed benchmark
diagnostics for comparisons, hashes, copies, allocations, value width, and key
distribution. There is no new universal wall-clock threshold, but unexplained
regressions are investigated.

## 10. Two-consumer acceptance

Every operation and major variant runs two actual downstream Computes through
the standard Host. Overlapping holding is required; parallel scheduling is
not. Releasing consumer A must leave B usable.

Tests verify both results, common completion, contract-specific logical
charging, independent release, and final reclamation. Physical storage shared
by A and B is reserved once, while either consumer's new output, index, and
scratch are charged separately. A consumer-specific failure or cancellation
does not revoke its sibling or producer, except when shared storage itself is
corrupt or untrusted.

The strict failure/cancellation matrix is applied per storage strategy
(independent allocation, shared buffer, selection/index view), with extra cases
for operations that introduce a distinct lifetime implementation. It need not
be duplicated for every operation/type pair.

## 11. Implementation sequence

1. Normative coverage manifest, current gap table, and standard Host E2E
   harness.
2. Walking skeletons for select, zero-input values, append, and group count.
3. Filter, derive, rename, drop, json_pick, and assert_rows.
4. Sort, take, top_k, top_k_by, distinct, and dedupe_rows.
5. Unnest, unpivot, and pivot.
6. Full append, except, intersect, cross_join, and join.
7. Full group, analytic, row_window, window_group, lag, and watermark_rows.
8. Nest.
9. Complete matrix and performance audit.

The first group-count slice includes empty input, multiple groups, NULL keys,
defined output ordering, and capacity exhaustion. Append proves a two-input
connection but does not prove join support. Join ports, demand, output bounds,
and self-join ownership are audited early. Pivot, temporal/window operations,
analytic, and nest contracts are investigated during the initial matrix rather
than deferred until their implementation step.

Every stage runs affected JS, Wasm, and native tests plus failure and lifetime
checks. The last stage is a final audit, not the first portable validation.

## 12. Coverage and CI

Testing is layered rather than a full Cartesian E2E product:

1. The coverage mother set comes from the fixed normative inventory and
   machine contracts, with manually recorded conditions where extraction is
   insufficient.
2. Every operation and major variant has a three-target standard Host E2E.
3. Every source variant has source-to-checked-to-common-lowering coverage,
   even when a heavy two-consumer E2E is shared with another variant.
4. Every normative operation/type combination has three-target kernel
   conformance with independent expected values.
5. Interacting axes receive dedicated fixtures, including nullable compound
   join keys, parameterized boundaries, ordering ties followed by take, and
   reshaped value ownership.
6. Lifetime failures are covered by storage strategy.
7. Performance evidence is linked to each adopted algorithm.

The manifest links every claim to fixture files and targets. A shared
implementation is not evidence without a rule test and source connection test.
Temporarily incomplete entries remain explicit gaps and do not count as
completion. Missing operations, unclassified layers, missing gap explanations,
or a claim of completion without the required fixture evidence fail CI.

## 13. Reporting and exclusions

Each increment reports the fixed SHA, changed files, operation/variant matrix,
tests run, benchmark conditions, remaining gaps, and Linux CI status. Local is
complete only when all manifest entries satisfy semantic, lifecycle,
three-target, and performance requirements.

This plan excludes Site provisioning, remote RPC, durable recovery, Effect
execution, a general distributed scheduler, and full support for other algebra
families. A RelA implementation may use a shared primitive also used by another
family, but that does not add the entire other family to this milestone.

This plan authorizes neither push, merge, nor deployment.

## 14. Review 20 integration order

The Review 20 fixes are applied in this dependency order:

1. `0f523e77` supplies the shared UTF-8 measurement correction from `main`.
2. `9edb5a65` and `d8f1ef95` add the shared and Local cross-join path.
3. `36abcfb8` changes the common managed reader to plan the complete input
   set before starting execution.
4. `bdc08d62` changes DuckDB tests to resolve pinned fixtures by name.
5. `1c067fc8` regenerates and formats the portable Host projections.

The complete-input reader change is the only shared execution boundary change
in this sequence. Public-branch owners can take `36abcfb8` after the UTF-8
measurement correction. The DuckDB fixture lookup and generated projections
depend on the rebased fixture set but do not change the reader contract.

No duplicate UTF-8 correction is present on this branch. The correction is
inherited from `main`, and the Local tests verify it through the retained
execution boundary.
