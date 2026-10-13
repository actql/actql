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
No key or credential body is committed or added to acceptance receipts. Default
and Sequence workers do not persist this fixture authorization.

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
