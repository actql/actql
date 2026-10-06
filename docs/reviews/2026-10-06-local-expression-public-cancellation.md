# Retained expression comparison: public scanning cancellation

## Existing implementation and missing evidence

The inherited expression frame already steps long Text operand charging and
UTF-16 comparison. Its binary/membership continuations retain operands and
roots; the bounded filter uses that same frame. Reimplementing comparison or
Run cancellation would duplicate existing owners.

The missing connection was evidence from ordinary public execution with a real
retained Store: the earlier component/managed Host tests did not deliver public
cancellation inside the actual expression scan. This unit adds that evidence
and requires it in the filter route's completion gate. Production runtime,
authorization, cancellation finalization and publication code are unchanged.

## Ordinary Program and synchronization

[The public test](../../adapters/host-node/public-expression-comparison-retention.test.mjs)
uses the normal installation and account authorization:

```text
Values [{id: 1, tag: a 256-character string}]
  -> filter tag = the same literal -> select id
  -> producer Named Result and two separate consumer tasks
```

The producer is one fused task. Each of `published`, `consumed_a` and
`consumed_b` is read through the public Result API and compared with the
independent literal `[{id: 1}]`. The Host observes `retained-file`; repeating
the same request attaches to the same Run without new dispatch or Compute.

For cancellation, the existing Host hook first observes Values completion and
the child-start transition, then suspends after three 256-work filter advances.
The matching core fixture verifies a pending `CompareBinary` in its UTF-16
phase, with an offset inside the long equal prefix. This is a phase assertion,
not a sampled exact work limit or a fixed sleep. If Compute completes before
the synchronization point, the public test fails explicitly.

Public cancellation records the request while physical stop remains unconfirmed
and the Run is not cancelled. Releasing the barrier allows confirmed stop;
all three Results remain unavailable and cannot be read. Compute/dispatch
counts stay fixed through cancellation and same-request resend. Store snapshots
are empty after cleanup. The fused input is held by the completed-input owner,
not an invented intermediate Store lease.

The companion core fixture checks the actual input root and expression frame
remain live through `Stopped`. Cleanup closes the frame and releases roots and
workspace exactly once without refunding logical/control work; the caller's
input remains valid. It also compares successful results and cumulative work
at quanta one, seven and 256. Empty public snapshots alone are not claimed as
a complete Ledger reservation census or physical stop-latency guarantee.

## Executed checks

Focused JS passed 18/18 (`run-YQl0D5`, `focused-test-U25Uix`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/public_expression_barrier_wbtest.mbt \
  src/execution_relation/expression_text_comparison_wbtest.mbt \
  src/execution_relation/expression_roots_wbtest.mbt \
  src/execution_relation/expression_frame_wbtest.mbt
```

The reused independent expression vectors include logical work 1032/1031,
live bytes 516/515, measurement workspace 11/10 and control work 527/526.
Their one-short failures preserve typed causes. These are expression/component
bounds, not newly established whole-Run exact budgets. Existing operator,
NULL, prefix-length and supplementary/BMP UTF-16 expectations remain unchanged.

The public boundary passed 1/1 (`run-KGbgzt`, `focused-test-lvuE5m`):

```sh
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-expression-comparison-retention.test.mjs
```

Resource/evidence-index tests passed 203/203 (`run-fuAN0C`,
`focused-test-xI2p9L`: 199 + 4):

```sh
node scripts/local-checks.mjs test node -- \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

Mutations remove each required long-expression role or the public environment
role separately. Another mutation removes the actual installation-suite import.
Each missing connection is rejected; a manifest name alone is insufficient.
The existing immutable loader already captures the installation suite source.

The initial phase-location diagnostic passed 1/1 (`run-97vUM7`,
`focused-test-uBYSAW`) and reported the third quantum's scan offset. Its debug
printing was removed before the final 18-test check; that diagnostic is not a
separate acceptance or an independently authored resource expectation.

## Source and artifact correspondence

The base is `53c97c71f455f39a7a3a3aba0b9267f04df38130` (#517). This unit
changes tests, their gate and records only; all production MoonBit and Host
runtime inputs match that parent. The existing scoped JS runtime generated for
the parent's implementation was reused without a rebuild or tarball production.
Local Node and Run Host runtime freshness are checked separately; ignored
runtime bundles are not committed. This is checkout public acceptance, not a
pristine packed Local/HTTP campaign.

Tests ran before committing the unchanged test/implementation tree and record
the dirty parent revision. The PR identifies the submitted complete SHA; prior
clean-SHA success is not substituted for that revision's CI.

## Remaining coverage and responsibility

Keep the unmerged #517 parent (and its #513/#510/#506 dependencies) until main
adopts it. The eventual merge target is main; no dependency-branch merge is
authorized. D's Model/Run cancellation recovery and H's Ledger/value fixes are
not modified. This evidence does not make them depend on this PR.

Wasm/native, packed/HTTP, full Core, integrated CI, new Store fault campaigns,
whole-Ledger reservation measurements and wall-clock stop latency are unverified
here. Registered targets are not executed results. Intrinsic concatenation,
long field/wire transitions and other operator scans remain separate from this
already connected Text binary-comparison route. No all-Local completion claim
is made.
