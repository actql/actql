# Original TimeSeries normal installed completion

This child of Sequence #1946 connects the existing F05 `time_series` primary
matrix to the same normal four-release-package source-free worker. It adds no
generator, evaluator, Source, Calendar engine or new authored acceptance case.
The original nine normal and seven refusal inputs remain byte-identical in
`scripts/fixtures/time-series-primary-source-input.mjs`: JSON/SQL/AQL-text,
bare primary, half-open UTC grid, typed empty output and bound Parameters.
The default IN/UNNEST 4+6 and Sequence 18+9 cohorts are unchanged.

The closed consumer flag is `--time-series-only`. All eleven test-only modules
in the relative-import closure are copied outside `node_modules`; installed
product files come only from the normal four unchanged release archives.
Original Client factories, transport, I/O guards, durable Store and cleanup are
reused. Same-process completion retains original Run/Submission references,
compared values/full schemas and replay/refusal observations.

After each original worker exits, a second OS process reopens that transport's
same durable state. It uses the exact saved Submission/Run references (never a
new nonce), independently compares rows/schema, performs lookup and resends the
unchanged source with original Parameters, requiring the same Run and unchanged
admission/Source counters. The test's synthetic authorization keys are retained
only inside the private consumer directory with mode 0600 for this restart.
No key or credential body is committed or added to acceptance receipts. The
default IN/UNNEST worker does not persist this fixture authorization. Sequence
and Temporal reuse this retained-custody seam for their own closed reread cohorts.

## Bounded commands and qualification

```sh
node reviews/2026-10-14-time-series-release-matrix/prepared-checks.mjs <clean-source-sha>
```

Node-only, non-Heavy 60 seconds/TERM grace 5 seconds, focused child 30 seconds.
Component/syntax checks do not execute TimeSeries or the installed product.

Only after allocation of each original shared public window:

```sh
node reviews/2026-10-14-time-series-release-matrix/prepared-release-public.mjs --producer <clean-source-sha> <new-absolute-RC>
node reviews/2026-10-14-time-series-release-matrix/prepared-release-public.mjs --consumer <same-source-sha> <same-RC> <new-absolute-receipt.json>
```

The producer and complete consumer (both transports and separate-process
rereads) each preserve 300 seconds/TERM grace 5 seconds. No producer, consumer,
Moon/compiler or public E2E is executed by the Node recipe. Original declared
limits and expected rows/schema are not changed to fit the window.

Installed 9+7 Local/HTTPS completion and fresh-process reread remain unverified;
new public E2E is zero. Vector #1952's shared captured-suffix repair is owned by
Root and is not duplicated here. Optional Calendar runtime remains unfinished.


## Independent installed-result audit

`public-audit.mjs` compares the actual saved Local/HTTPS observations with the
unchanged original nine normal and seven refusal declarations. It requires
21 rows and complete timestamp contracts per transport, including typed empty
results, exact UTC parameters, original refusal codes with zero admission/I/O,
same-request replay and a different process rereading all nine Named Results
without another admission. Missing/incomplete observations are not success.
Synthetic mutation controls exercise the audit but do not establish product E2E.

The standing autonomous verification policy supersedes this note's historical
per-window permission wording. The original producer/consumer 300s/TERM5 and
shared guard resource/Owner admission remain unchanged. Source and artifact
identities are fixed separately from any later main integration.


### Existing installed qualification, independently reconciled

G's immutable source `b999fddb4ef6a54847dc557ee269103f74345d86`,
manifest `47cf24d01e68e5d68f7d0e8017d93b8362b06516f700edaf4c8c52db0ac57de9`,
completed the normal four-package cohort with Local/HTTPS each nine normal,
seven pre-admission refusals, 21 rows and nine fresh-process rereads. The six
actual child commands ended zero (`run-bpLJ1P`); Owner/group and locks were closed.
The original receipt is workspace
`reviews/2026-10-11-integration-owner/g-b999fddb-timeseries-consumer-receipt.json`
(SHA256 `6e9113f1f704cd20b7bac81c7bafe044abaa98347c96e1f2ab9ab5eb8d8fd863`).

This audit accepts that exact retained receipt and the unchanged independent
fixture (`c5f43f34dc7ea62b13aff023cb8188a2a1cfa5dafedfa663c875e4fc92f6c900`).
No original Run, DB, request or artifact is reopened/replayed/reinterpreted.
It is a second read of existing evidence, not a new E2E scenario or a latest-main
product PASS. Node 25/25 at `42dee1b480b1f6ebdf702a8046e9c863c1f33df8`
(`run-5KFHSz`) covers the finite audit mutations and existing release selections;
this section is the only subsequent documentation change.
