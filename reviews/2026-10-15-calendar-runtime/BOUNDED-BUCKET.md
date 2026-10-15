# Calendar bucket through the existing bounded owners

The checked Calendar operation and immutable selected table remain the only
semantic inputs. The original IntervalCursor realizes civil boundaries and
handles folds, gaps, coincident boundaries, domain and work failure. This caller
retains one interval continuation and one row at a time. It does not introduce
a Calendar engine, fixed-duration grid, ambient TZDB or default profile.

Input cells use the existing receiving-column projection and resumable value
recheck. Every advance checks the same producer's availability. A thin common
presence observation distinguishes a present SQL NULL, an absent conditional
cell, unavailable completion and invalid coordinate. Present conditional cells
use the same existing recheck cursor; ordinary Required-only cell APIs keep
their original meaning. A confirmed that the common read hunk is not edited by
another owner.

Output uses the existing AdmittedOutputRowCursor for bounded structural recheck
and cumulative logical charging. Only the new closed two-timestamp object is
constructed. Original fields, values, physical order and presence are retained.
The existing trusted-completion owner binds the exact selected operation input;
a foreign equal-valued producer is rejected. Cancellation/failure retain the
same row cursor and output for cleanup. False/pending is not a cleanup ACK.

The first independent counter revealed a pre-existing static bug: bucket
changed a Conditional payload into Required (9f21daaa, run-FbUwri, 0/1).
The original complete Schema now retains its per-field presence through the
existing typed-row owner; untyped/qualified knowledge keeps the original path.
The counter passes at 3a2dd2cd (run-NaPAMf, 1/1). The initial counter's incorrect
String primitive spelling is preserved as d860025e/run-xNuDf6, counts null.

Actual component evidence:

- Bucket kernel 3/3 at 6bc2f4b6/run-iNV2qE: unchanged two source intervals and
  full month boundaries, original physical schema, quantum 1/7/64 with equal
  cumulative work, exact input binding, selected one-short quota, foreign input,
  cancellation and producer unavailability with retained cleanup.
- Selected managed provider 1/1 at af7187cf/run-wa0YyU: exact producer input,
  independent closed month values, original result binding, work deltas and
  retained result/input after cleanup. The supplied-input count refusal remains.
- Common producer presence 1/1 at fffb2e40/run-0G0eLk: original existing sorted
  fixture distinguishes value, NULL, absence, invalid coordinate and unavailable;
  present conditional values complete the shared recheck without coercion.
- Calendar admission 3/3 at 18bb0162/run-tnmLEm, including original qualified and
  untyped payload, original diagnostic locations and exact preparation budget.
- Ordinary JS/Wasm/Native affected API generation and consuming types complete
  at 18bb0162/run-yzg57Y, 25 tasks each. These are not Native/Wasm executions.

Initial kernel compilation b1d15735/run-ePMPIY failed before test discovery
(read-only Present construction and constructor-as-function); it is preserved.
No failed or older-source result is promoted to a latest-source pass.

This true child of #2157 normally adopts actual main
be5165b8dcfabe84333533071dad861a567f5f24 at 57dad963. Original public six
Calendar fixtures, independent rows/schema, table/pins and limits are unchanged.
Calendar normal-package Local/HTTPS E2E remains zero. The normal Node Host's
explicit artifact installation seam is still unfinished and is the next unit;
public preparation alone does not prove execution. No old Run/DB/Unknown,
package producer, Provider service, Hosted CI or formal publication is used.

```sh
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> presence
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> typing
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> kernel
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> provider
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> reader
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> api
node reviews/2026-10-15-calendar-runtime/prepared-calendar-bucket.mjs <SHA> format
```

Focused tests use nonHeavy270/TERM5, child240 and JS j1; API info is sequential
and scoped to affected packages. Read-only authored formatting uses nonHeavy60.
These commands retain nonzero discovery, source fences and original guard owners.
