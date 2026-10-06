# Session package directory index

## Preserved input boundary

`packageSourceInputs` previously scanned every Git path twice for every visited
package, even though only immediate members and nested unmodelled inputs were
needed. The replacement builds those two indexes once per invocation. Literal
imports still control traversal; manifest bytes/modes, transitive files,
directory membership, unknown configurations, unsupported modes and deep
unmodelled inputs retain the same observations and refusal reasons.

There is no cross-call cache. Each new invocation observes additions, deletion,
rename and import changes again. Path names are not normalized. The existing
object-verified length-delimited Git blob reader and manifest frontier batching
are unchanged. Unrelated package bytes are not prefetched by building the index.

## Fixed extraction measurement

Measured candidate: `bd007b18a1c22121aa555b52a78e0a3fc500fe78`.
Reference traversal: main `b98a50ff763d1367e344fdfa8aea380ec8749132`.
The existing profiler loads only the preceding traversal in the same candidate
parser/catalog/review context, so registration or input-schema differences are
not mistaken for this algorithm's effects. This is measurement code, not a
production compatibility path.

The complete actual Git input records and keys for all 30 actions match before
and after. Nine serial alternating-order pairs were fixed before measurement,
after two warmup pairs. Each extraction constructs a fresh Git tree. The local
OS/filesystem is warm; counting instrumentation is outside the timed pairs.

| Observation | Before | After |
| --- | ---: | ---: |
| Mean whole extraction | 4,339.596 ms | 1,767.908 ms |
| Git blob batches | 31 | 31 |
| Verified blob objects | 4,461 | 4,461 |
| Full entry enumerations | 5,337 | 61 |
| Path visits | 38,746,620 | 442,860 |

The mean paired reduction is 2,571.688 ms, with all 9 pairs positive. A
descriptive 95% paired t interval is 2,376.170–2,767.207 ms shorter. This is a
single-host warm extraction observation; it is not multi-host stability,
physical campaign speedup, billed minutes or net CI runner savings. The timed
interval includes Git and full input extraction, but excludes runtime capture,
compiler/proof actions, authentication, artifact transfer and enclosing jobs.
Raw observations and keys are retained unchanged in
[the paired record](2026-10-07-session-directory-index-pairs.json).

The existing bounded guard (`run-YpQYxT`) ran:

```sh
node scripts/profile-session-input-frontiers.mjs \
  /private/tmp/g-session-directory-index-pairs.json \
  --reference b98a50ff763d1367e344fdfa8aea380ec8749132
```

## Local execution and correspondence

At the measured source, the bounded selection of `inputs.test.mjs`,
`git-inputs.test.mjs` and `package-frontiers.test.mjs` passed 25/25 in
6,782.433 ms (`run-WlwHzu`, `focused-test-DXjVNo`). It checks independent
prefix/deep-nested/path/mode expectations, changed membership on subsequent
calls, raw binary Git protocol validation and complete 30-action equivalence.

The same clean source executed the existing local isolated entry using builder
`sha256:e894118949319b479bfc3e16e545cb2f85b7a2194aa86ea9cd4e29538f2b13c3`
and the retained pinned Linux MoonBit installation. Gate `run-juVjK3` completed
in 246,563 ms with complete output, exit 0 and released locks. Actual scratch
image `sha256:f914e18128b59acb91db5908d2856df1b64ff1858035f0baf418b303805dac60`
detected all 13 registered mutations with exactly one running assertion failure
each, restored original bytes and passed the scientific consumer. Compile
failure, timeout and absent/zero-test experiments do not count as detections.
Owner container/image cleanup completed.

Main's two unreviewed Native configurations remain unresolved in this
independent change, so the image contains all 4,428 source files via the same
conservative fallback. Their finite review is #664's separate scope. This
optimization neither erases those gaps nor qualifies a new runtime contract.
The local record has `reuseAuthorized: false` and retains local authority and
kernel/CPU/environment residuals.

The original 4,481,795 bytes have SHA-256
`64eb96741cc7ce7dd067803e1616bae31aa1a3837d858a4724a2411b479456e0`.
All logs, manifest/image observations and custody are retained losslessly in
[the local original](evidence/2026-10-07-local-isolated-session-bd007b18a.json.gz).
Exact submitted-SHA commands, correspondence and results are reported in the PR.
Later documents do not relabel the measured/executed source.

## Remaining operational evidence

The extractor's bytes are verification inputs, so this policy change
intentionally invalidates earlier action keys. Original evidence remains
immutable. Identical records for a fixed candidate demonstrate extraction
equivalence, not permission to apply an old-policy receipt.

Authenticated compatible main originals, real main comparison, ordinary PR
reuse, relevant-change fresh execution and net runner savings including capture,
authentication, transfer and final verification remain required separately.
No full performance matrix or additional workflow execution is introduced.
