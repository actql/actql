# Package manifest frontiers: lossless input extraction

## Scope and preserved obligations

The immutable Git reader previously started a separate `cat-file --batch`
process for an uncached package manifest during recursive dependency discovery.
Only after selecting the full closure did it batch the remaining source blobs.
Collect already-discovered manifests by dependency frontier instead. The same
bounded Git batch decoder verifies object identity, type, length and every blob's
actual content. Only reachable manifests are requested; no unrelated package
prefetch or closure memoization across calls is introduced.

Every action still records the same source bytes/modes/memberships, external
packages, configuration review, unresolved reasons, target, descriptor and
runtime. Missing manifests, unknown options, dynamic imports and nested data
remain unresolved. The mutation selector still expands to full source on those
gaps, and changes between calls are observed. No tests, observations, recipes,
required actions or fresh/reuse conditions are omitted or loosened.

The extractor file is itself a verification input. Its new bytes invalidate
previous policy keys normally. Equivalence here means the old and new functions
produce exactly equal inputs **on the same candidate tree**, not that an old
receipt can silently adopt a new extractor source.

## Actual-source equivalence and regression evidence

The regression compares all thirty actual Git action manifests, including their
keys and unresolved boundaries, against the exact preceding package traversal from
`92fb7a94b1c9776ce13eb516723dd3471f6152f3`. The surrounding registration,
shared-input inventory, parser and decoder context is held equal, so a later
legitimate added obligation does not falsely fail against a historical catalog.
Only two relative imports are relocated to the same candidate dependencies.
This reference is used only by tests and the measurement script; production has
one implementation. This checks the changed traversal under that shared
context, not every historical extractor behavior under arbitrary later changes.

Independent fixtures fix reachable diamond/cycle membership and external
imports, refuse missing/dynamic/nested inputs, observe new members/import changes
on subsequent calls, and never read an unrelated manifest. Existing source,
oracle, add/delete/rename, mode/target/runtime, unknown-input and Git corruption
refusal regressions remain.

## Paired local phase measurement

The original [nine pairs](2026-10-06-session-input-frontier-pairs.json) are
unchanged, recorded at clean implementation
`9ad58b9cda6d00f44b3a11690d28369c33e01d3f` by that revision's
`scripts/profile-session-input-frontiers.mjs`. That measurement loaded the full
preceding module; at that revision, its surrounding input-extraction context
was unchanged, with the package traversal being the only product-code diff.
The later reference loader isolates that prior traversal to keep future
registrations comparable; it does not rewrite the measured original.
Each invocation reconstructs a
fresh Git tree and extracts all thirty actions. OS/filesystem caches are warm;
there are two warmup pairs and nine alternating-order measured pairs. Separate
untimed instrumentation counts actual Git invocations without changing their
bytes or outputs. Every run also checks complete manifest/key equality.

| Observation | Before | After |
| --- | ---: | ---: |
| Actual `cat-file --batch` processes | 177 | 29 |
| Verified distinct blob objects read | 3,836 | 3,836 |
| Mean full-catalog extraction | 5,563.353 ms | 3,828.716 ms |

All nine pairs improved. Mean observed phase reduction was 1,734.637 ms;
the descriptive paired t interval (8 degrees of freedom, 95%) was
892.103–2,577.171 ms. No pair was dropped and no favorable rerun was selected.
Shared-host load is uncontrolled, this is one candidate and one local machine,
and this interval is not a universal performance guarantee. Counting was outside
all timed pairs. The bounded profile receipt is `run-FDTyyc`.

This includes actual Git process startup, tree enumeration, bounded blob
verification, dependency discovery, hashing and canonical action-key encoding.
It is source-extraction phase timing only: no compiler, Moon/Lean execution,
verification ZIP transfer, hosted final job or original authentication is
measured. `reuseAuthorized: false` and net runner savings `null` are retained.
Do not multiply this reduction by hypothetical CI calls or report it as a
complete CI before/after comparison.

## Integration and remaining acceptance

The change depends on #412's published shared source selector and targets main
after that parent is adopted. It does not modify #605/#629's local authority,
finite experiment review, immutable image/receipts, or the coordinator's workflow
scheduling. Existing end-to-end physical originals remain tied to their actual
source SHA, not this changed extractor. A fresh execution using this policy is
still needed for its protected-main original; local equivalence does not create
Actions provenance or authorize reuse.

Authenticated current main comparison, ordinary PR reuse, related-input fresh
execution and collection/transfer/checker-inclusive net runner savings remain
unfinished. This unit reduces a measured repeated input-construction cost while
those acceptance boundaries remain intact.
