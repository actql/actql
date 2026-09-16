# Resident identity reuse diagnostic

Fixed implementation comparison: `eae6e67904b931f190f9f0efd8b602e59d65e7cc`
before reuse versus `25e9ac2bd7e0e80d96035c1078e0945ba2dce9cb` after reuse.
The latter adds only the diagnostic entry after product change `1c45fcfb`.
[All 24 samples](resident-identity-pairs-25e9ac2b.json) are diagnostic, not formal
performance acceptance or evidence-calibrated placement.

Each case ran three alternating before/after pairs in fresh controller/worker
processes, in orders AB, BA, AB. The same generated source database was used by
both legs. Builds, source generation and the independent oracle were outside
timing. Host setup, acquisition, validation, required identities, first resident
import, independent holding, worker exit and final cleanup were included.
No resident copy was preloaded. Original fixture, 1 GiB independent retention,
4 GiB execution budget and timeouts were unchanged.

Both legs enabled resident candidates and used the same explicit diagnostic
`nativeMilliseconds: "20"` estimate. This is not a calibrated estimate and must
not be used to claim Q7 ordinary-selection acceptance. Actual selections are
recorded; unsuccessful resident eligibility was not overridden.

All cases below use `retained-large-output-downstream-reuse`.

| Layout / source rows | Selected path in both legs | Before median, including cleanup | After median, including cleanup |
| --- | --- | ---: | ---: |
| text-1024 / 1,000 | resident, three tasks | 1.067 s | 1.020 s |
| narrow / 10,000 | fresh native-file, three tasks | 0.861 s | 0.851 s |
| numeric-64 / 10,000 | fresh native-file, three tasks | 8.940 s | 9.013 s |
| text-1024 / 10,000 | fresh native-file, three tasks | 4.560 s | 4.584 s |

The resident case's summed input-verification intervals had medians of 147.161 ms
before and 98.696 ms after. Each of its three inputs reports reused identity
after the change, with the same independent expected final CID and successful
cleanup. These intervals are included in total time, not added to it. Three
pairs do not establish the registered seven-pair confidence gate.

The three large cases did **not** use resident identity reuse. Their timing
differences are not attributed to that optimization. The next product work must
reach large-case selected paths, not extrapolate from the small resident result.

The existing example offers a 128 MiB shared DB environment and conservative
copy allocations derived from admitted-value capacity. Source and output copies
must coexist before transactional retirement. This is distinct from the 1 GiB
independent-output retention limit. Inspection of a large-case strategy report
found its shared-capacity refusal mislabeled `retention_limit`; the follow-up
classification regression fixes this to `execution_limit` without changing any
capacity, candidate eligibility, execution behavior or threshold. It is not a
remedy for the conservative copy bounds or a completed resource-cost calibration.

Raw samples and full selection explanations remain under
`/tmp/actql-resident-pairs-retry.ZCowPn`. The initial attempt at
`/tmp/actql-resident-pairs.BsoJA2` is invalid as a paired comparison: baseline
dependency symlinks appeared as untracked files and the clean-checkout check
refused every baseline leg. Those failures are retained. After installing actual
dependency directories, both checkouts were clean for the complete rerun.

Reproduction: build the five shipped Node Host targets used by
`resident-data-profile.test.mjs` in each clean checkout, generate a fixture DB
with `create-retained-source.mjs`, then invoke `retained-case.mjs` with checkout,
database, holding directory, workload, layout, row count and estimate `20`.
The entry checks source cleanliness and HEAD before and after each leg. This
diagnostic does not replace all-27 conformance, the independent equivalent-duty
comparator, absolute-practicality review or the new-profile contract work.
