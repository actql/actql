# Offline retained CI artifact analysis

The existing evidence command accepts an exclusive offline selection:

```sh
node scripts/ci-evidence.mjs actql/actql --artifacts selection.json
node scripts/ci-evidence.mjs actql/actql --artifacts selection.json --json > analysis.json
node --test scripts/ci-evidence.test.mjs
```

No GitHub request, workflow run, executable import, extraction or cleanup is
performed. The existing evidence test gate imports the bounded reader and
projection fixtures. No workflow or acceptance gate is weakened.

## Explicit selection and provenance

[The retained sample selection](../scripts/fixtures/ci-artifact-retained-selection.json)
shows the schema and exact identities of four real archives. Place each already
retained ZIP at its `archive` path relative to the selection file, or edit only
that local path. The tool does not download arbitrary URLs. The ZIP digest and
compressed size must match the selected artifact. Keep the repository, full
run head SHA, full executed/report revision, workflow, event, run ID, attempt,
artifact ID/name/digest and outcome. PR run heads and test-merge execution
revisions are separate; an associated PR object's current head is not a
historical run head.

The selection is an explicit local assertion of API/log provenance, not an
independent GitHub attestation. ZIP hashes, report revisions and retained receipt
hashes are checked; the tool does not invent absent checkout evidence. Runner
region/image and cache state should identify the observation source; use null or
`unknown` when unavailable.

Reports are selected separately as `fixed`, `fresh`, and optional `capacity`.
They must use the existing mutation/structural-capacity report contracts. Supply
an independently known expected mutation inventory and targets. Missing inventory,
missing phases, malformed/negative/non-finite durations and target substitutions
are unknown/incomplete, never zero. The per-mutation projection retains anchors,
site digests, minimum/shrink/oracle fingerprints and candidate counts. Its workload
fingerprint omits observation occurrence IDs, not query IDs or semantic contents.
The exact source and site digests remain separate comparison dimensions.

An optional `timingEvidence` value can be a saved existing `ci-evidence --json`
report. Its selected attempt identities must match the artifact provenance; the
existing `ci-timing.mjs` projection supplies timestamp boundaries, job/step elapsed
time and observed pre-start intervals. Missing wall-clock evidence stays absent.
Parallel job durations, phase action sums, enclosing capacity durations and queue
time are never conflated. Compiler/hash/I/O splits and build counts are unknown.

The live timing projection also retains `runnerConsumption` for each explicit
run/attempt. `totalJobSeconds` sums distinct job intervals once; overlapping
jobs still consume separate runner time. `observedJobWallSpan` is retained
separately. Neither steps nor artifact phase sums are added to the total.
Setup, transfer and final verification inside the jobs are already included.
Missing/invalid times, incomplete inventories, unobserved runner allocation or
no executed steps leave the total null. `knownJobSeconds` remains a partial
observation. Failed/cancelled attempts may retain measured consumption but
cannot become successful samples; retries stay separate.

These are observed job seconds, not billed minutes or a causal savings verdict.
For Session reuse, select the actual producer and final-check owners from
authenticated source/applicability evidence and retain the complete attempt
total as well. The partial Session cost record explains subphases; it must not
be added to job totals. A claimed reuse saving still needs equal inputs and
obligations, qualified originals, comparable execution conditions and measured
fresh/reused attempts. The read-only timing report never authorizes reuse.

## Custody and storage boundaries

One ZIP reader serves both timing and storage projections. It rejects traversal,
absolute/ambiguous paths, duplicate normalized entries, links/special entries,
unsupported encryption/multidisk/ZIP64 and overlapping/inconsistent records.
Only stored/deflate payloads are read, with CRC and length checks. Defaults bound
compressed archives to 512 MiB, individual members to 256 MiB, total logical
members to 8 GiB, entries to 20,000, inflation ratio to 2,000 and JSON to 160 MiB.
Caller overrides may only tighten limits. The manifest is a regular file bounded
to 4 MiB before reading; archives are regular non-symlink files. Neither file
system traversal nor archive extraction is used.

JSON includes every selected archive member's logical and ZIP-member compressed
size, SHA-256, category, protected status and known referring receipt paths.
Archive compressed bytes include ZIP overhead; logical byte totals do not.
Receipt canonical JSON, source-map canonical bodies, and raw fixture/input/log
references are checked. Capacity archive mappings identify exact retained paths.
An original build path may instead resolve only by identical retained content;
that does not establish that its original path was preserved. Missing references
remain explicit and protected, including older mutation binaries not retained in
the archive. Unknown files also remain protected. A build-looking path or duplicate
content does not establish safe regeneration or deletion.

Duplicate groups report identical-content extra **logical** bytes. They do not
estimate filesystem allocation, equivalent compressed bytes or recoverable disk.
No deletion candidates or retention setting changes are produced. DBs, journals,
credentials and general filesystem inventories are outside this tool's scope.

`reportedRunSuccessful` preserves the supplied run outcome; it does not mean the
selected archive is sufficient for re-audit or merge readiness.
`selectedEvidenceComplete` is separate. `complete=false` and exit 1 preserve
partial output when references cannot be resolved or receipt validation fails;
failed/cancelled run outcomes alone do not make retrieval fail. Exit 2 means
invalid CLI options. ZIP/provenance/schema failures produce exit 1 without a report.

## Retained demonstration

The [measured summary](reviews/2026-10-02-retained-ci-artifact-analysis.json) was
projected directly from retained ZIP bytes. #825 and #836 are separate successful
baselines. #845 is a failed run and #849 is cancelled; neither is an accepted
after sample for #190. The command can select #190's final accepted artifact when
available without changing this reporting framework or relabeling older evidence.

All current cohorts have one selected sample and differing source, runner/event,
outcome or unknown cache dimensions. No stable or causal speedup is claimed.
Capacity campaign scope is reported separately from the eight mutation sites.
