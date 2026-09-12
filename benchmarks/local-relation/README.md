# Local Relation sequence measurements

Build and measure with the repository's pinned MoonBit toolchain:

```sh
moon test --target native src/execution_relation/sequence_scale_wbtest.mbt
node scripts/measure-local-relation.mjs
```

The default executable is the native **debug** whitebox test binary. An explicit
binary path may be supplied as the first argument. Each of twelve shapes runs
three times in a fresh process. The runner checks the exact test-result event,
not merely the executable exit code. macOS `/usr/bin/time -l` reports bytes;
GNU time on Linux reports KiB, converted to bytes in the report.

The measured scope includes startup, fixture construction, checking/lowering,
input decoding/admission, execution and assertions; it excludes compilation.
Peak RSS includes test fixtures and the runtime, not just live Relation tables.
Logical budgets do not claim to cap this RSS. These figures do not establish
browser/Worker capacity, production latency or performance on other machines.

Cases cover 100/1,000/10,000 rows, 2/64 columns and equal/different grouping
keys. Unique input IDs make the grouping winner independently predictable.
The same generated sequence performs rename, identity drop, stable sorting,
projection/distinct/take and an alias branch with dedupe/sort/take. Closed-form
expected values check both outputs and retained payload. Nonselected intermediate
outputs must be released. Scalar-domain and logical-budget boundary tests remain
separate from this size matrix.

Reports record source commit, worktree state, executable and test-source hashes,
host identity and all samples. Rebuild before measuring after source edits; a
report is evidence for its recorded build, not for a later revision.
