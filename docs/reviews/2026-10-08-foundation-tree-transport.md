# Complete foundation tree transport: local cost comparison

## Scope and retained obligations

The shared `currentFoundation()` path is consumed by pipeline audit and producer
artifact sealing. Its previous per-revision tree reads dominated the recorded
Git cost. This change batches the transport, preserving a complete selected tree
for every revision. It does not select fewer commits, protected files, declarations,
merge bases, tests, targets or evidence obligations.

Actual first-parent edges come from the complete unsimplified Git graph. Bounded
raw/NUL deltas populate invocation-local maps; boundary and older-base trees still
use independent `ls-tree`. Both merge parents and every maximal base participate
in the existing acceptance rules. Added/changed blobs retain independent type and
existence checks. Missing, reordered, truncated or malformed transport, nonregular
entries and mismatched prior identities fail closed.

Source/parent/blob/mode bindings, declaration introductions, dependency groups,
immutable historical originals, index and working-tree checks remain mandatory.
The new module and fixtures are themselves protected inputs. No persistent cache,
receipt rewriting, selection policy or production compatibility path was added.
Trust in the actual Git object's extraction and local execution environment
remains; matching hashes do not prove product semantics.

## Fixed sources and comparison protocol

- Adopted main: `04b1e822091b3b02fded57e88d13591d0e5dfa29` (including #874).
- Implementation: `3bda433873fbfd7cddc7a67c984d950e90d4169d`.
- Clean measured candidate: `91b253676406d6d2e2789ea2078481e7285a7a02`.
- Reference validator source: `57eb0b70b27befcd0b67c1c8ccb465f550885a30`.
- Reference validator bytes: SHA-256 `f0bdc16ff55046584ba85077ce3320b128f32cf469cadb0e94dc85c735a73ebb`.
- Current validator bytes: SHA-256 `969b9516d892c2710f4f67e433041dc9e319214fb15ad8978d07bfef9c4e2b5b`.

The reference loader uses the previous validator and the candidate's **current**
history entry point, protected paths, immutable inputs and actual repository.
It changes only the reference module's inventory import URL and the copied history
module's two import URLs. Both variants validate the same clean candidate rather
than different revision ranges. Every Git command runs unchanged; no successful
gate mock is used. The original reference bytes and exact loaders are retained.

The order was fixed before execution: before, after, after, before. All four runs
are retained. Each uses a fresh Node process, the same Git database and OS cache,
and the same transparent Git timing observer. Caches were not flushed. These are
local cost diagnostics, not a calibrated cold/warm benchmark or statistical claim.
Observer overhead is included equally and is not subtracted. The worker-process
elapsed time includes Node startup, complete validation, serialization and local
manifest writing; the composer time is also reported separately. Reference-loader
preparation and outer guard setup are outside those per-worker durations.

## Observed results

| Order | Variant | Whole worker, seconds | Composer, seconds | Actual Git calls |
| --- | --- | ---: | ---: | ---: |
| 1 | before | 205.000 | 204.802 | 6698 |
| 2 | after | 129.917 | 129.822 | 2601 |
| 3 | after | 144.923 | 144.833 | 2601 |
| 4 | before | 195.870 | 195.751 | 6698 |

The whole-worker means were **200.435s before** and **137.420s after**:
**63.015s (31.44%) less per complete local validation**.
The input is this fixed repository history; the result is not generalized to all
workloads or converted into hosted runner savings.

Every run accepted **89 protected files, 236 declarations and 194 integrations**.
All four complete serialized manifests are byte-identical (SHA-256
`0facf0d0fa1a05d42c0c4b2ccb792fbb952cdf43f69011d6544ad3157ecfbaa4`). Each output records the actual candidate SHA;
the final existing exact-source consumer also accepted it. The candidate's latest
normal merge retains both actual maximal bases without synthesizing a single base.

Tree transport used 3760 `ls-tree` calls before,
versus 8 boundary `ls-tree` calls and
15 bounded `diff-tree` calls after. Those
call counts repeat in both invocations of each variant. Every invocation still
validates all current source and declaration history.

## Local commands and evidence

Working-diff diagnostics before the implementation commit:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- proofs/relation-pipeline/foundation-trees.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 600 -- proofs/relation-pipeline/foundation.test.mjs
```

Results: **22/22** transport cases and **176/176** existing composer cases, no skips.
These were working-diff runs, not pristine runs of the final publication SHA.
The cases include independent real-Git tree comparison through branch/merge,
binary/mode/membership changes and multiple batches; malformed transport, missing
objects, exact source/dependency/immutability and multiple-base refusals remain.

Clean-candidate comparison and exact-source consumer:

```sh
node /private/tmp/g-foundation-comparison-guard.mjs
```

This existing heavy guard had a predeclared 1,200-second bound and completed both
steps successfully. It ran four complete actual `currentFoundation()` validations
and the existing nonzero exact-candidate binding consumer. No competing gate,
source edit, merge or switch occurred during the measured execution.

The [compressed local original](evidence/2026-10-08-foundation-tree-comparison-91b253676.json.gz) preserves all four raw
manifests, per-command counts/times, exact scripts and reference loaders, the
completed guard and raw fixture outputs. Decompressed original: **6347324 bytes**,
SHA-256 **`30997d3146108337b6f133191ed791ee87269abb7288151af04ee91cc253e03e`**. It can be inspected with `gzip -dc`.
The temporary diagnostic scripts are archived rather than installed as another
verification framework. Their recorded root/paths and source identities delimit
the experiment; changing them produces a new diagnostic, not this original.

The subsequent publication adds this review and compressed original only. It
does not relabel the measured candidate as a later execution SHA.

## Outstanding acceptance

No Hosted Actions checkpoint or end-to-end pipeline mutation campaign was run
for this transport-only change. Product/Native code, compiler pins, workflow,
job selection, tests and scientific acceptance rules were not reduced.

Authenticated successful main Actions originals, compatible later-main
qualification, ordinary-PR `mutations-js` reuse, related-input fresh execution,
and transfer/authentication/checker-inclusive net CI savings remain unverified.
They resume from a successful full-main original under the existing policy.
This local complete-validator speedup does not qualify any additional action for
reuse and does not turn local evidence into an Actions original.
