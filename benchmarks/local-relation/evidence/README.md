# Selected machine-readable evidence

Read the [integrated findings](../REPORT.md) first. These JSON files preserve
selected existing results in Git; they do not remeasure, alter thresholds or
promote an incomplete diagnostic into acceptance.

| Files | Source and retained content |
| --- | --- |
| `layout-{additional,legacy,prepared,prepared-legacy}.json` | Four complete layout summaries: source/report hashes, host/compiler/method, every candidate case's time and RSS medians/ratios/intervals/directional findings. Phase details remain in the historical comparison appendix and raw summaries. |
| `layout-traffic.json` | All 177 construction/transfer observations, source and artifact identities; not allocator-wide counts or timings. |
| `historical-stopped.json` | 37 saved historical decisions and sample count 812. Original `running` status is retained alongside the explicit stopped interpretation; 14 trailing samples had no decision. |
| `frame-extraction.json`, `event-extraction.json` | Separate frame/event attribution diagnostics. |
| `frame-recovery.json`, `frame-residual.json` | First local improvement and its residual against the pre-frame baseline. |
| `completion-residual.json` | Post-completion residual, not direct attribution of completion cost. |
| `boundary-direct.json`, `boundary-recovery.json`, `boundary-residual.json` | Latest direct boundary comparison, one recovery patch, and old-baseline residual. |

`source_file` is a repository-relative local path, `source_sha256` hashes its
original bytes, and `raw_report_sha256` (layout summaries) identifies the
underlying timing report. `sources` retains measured commit/tree and fixture
overlay identities. `cells` contains selected exact recorded statistics, not
freshly recomputed or rounded values. `before`/`after` are separate medians;
`paired_ratio` is the median of per-pair ratios. Time units are microseconds;
RSS units are whole-process peak bytes. Directional `regression` is not the
same as crossing the practical threshold in `decision`. `extend` remains
uncertain; it does not authorize additional sampling.

The snapshots intentionally omit raw samples, output assertions, screening
history, binaries and build logs. Complete original reports and artifacts remain
locally under ignored `_build/layout-measurements/` and
`_build/revision-measurements/`. No external backup was made and no raw files
were removed. Losing `_build/` would lose full raw-audit capability, despite
the selected statistics remaining in Git. Do not delete originals until a
complete external/archive copy has been independently verified.

To reproduce or audit full evidence, use the maintained
[measurement instructions](../README.md) and original reports, not these compact
snapshots as input to the raw-report auditor. The archived prose is available
under `../archive/` and unchanged Git history records every implementation and
experimental step.
