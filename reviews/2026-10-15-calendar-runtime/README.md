# Calendar calculation connection

This finite unit supplies bounded calculation cursors on the existing immutable
`calendar_transition.Table`. It implements the already adopted Calendar law in
`docs/spec/language.md`; it does not admit a Plan, select a profile, install a
Host capability, acquire data, publish a Result or add an evaluator.

The existing selected Calendar artifact, checked operation, parameter bindings,
occurrence/scope, policy ceilings and output-port ownership remain obligations
of the subsequent lowering and TEA execution connection. Those consumers are
not connected by this PR. Calendar Local/HTTPS E2E remains unverified.

## Calculation and retained work

`LocalResolution` visits the original offset segments, selecting the earliest
exact fold occurrence, or, if none exists, the earliest original transition
covering a forward gap. No coverage extrapolation or clamping is performed.
Each segment and finalization consumes one logical work unit.

`IntervalCursor` visits offset extrema and a finite window of aligned local
civil boundaries. It chooses the greatest distinct resolved UTC boundary at or
before the input and the least boundary strictly after it. Admitted Int32
offsets do not imply monotone local-to-UTC conversion; sorting or overwriting
the start by civil iteration would lose a valid boundary. No offset restriction
is introduced to make that assumption true.

For minimum and maximum offsets `m` and `M`, any resolved boundary for civil
coordinate `c` lies in `[c-M,c-m]`, including gap advancement. With offset spread
`d=M-m` and the unit's maximum civil span `s`, adjacent UTC boundaries, when
present, are contained in `[t-d-s,t+d+s]`. All candidate civil coordinates for
that bracket lie in `[t+m-d-s,t+M+d+s]`. The search scans aligned boundaries in
that conservative window, clipped to the existing civil year domain. Missing
representable adjacent boundaries fail; a skipped day collapses coincident UTC
boundaries. Extra candidates outside the table's inverse coverage contribute
no boundary. Inverse work exhaustion is propagated, not treated as absence.

Offset scanning, initialization, each candidate and completion consume work;
the inverse cursor's actual work is deducted from the same retained budget.
The Gregorian formatter/parser already owned by `value_admission` supplies
exact integer civil spellings. Day/week arithmetic here is arithmetic on local
civil coordinates, never a fixed-duration UTC substitute for Calendar.

`SeriesCursor` retains one interval cursor, emits full intersecting intervals
in UTC order and advances to the emitted end. It does not clip endpoints,
materialize a boundary array or emit duplicate/zero-duration intervals. Equal
ranges complete empty. Reversed ranges, row limits, work limits and invalid
week origins retain typed failures. All cursors permit a caller's existing
bounded kernel to observe cancellation between finite polls. They themselves
hold no resource, output, cleanup or publication authority.

## Independent controls

- Small offset-table controls cover folds, gaps, overlapping gaps, skipped days,
  nonmonotone conversion, original-table custody, exact large integers, terminal
  cursors and work exhaustion.
- Civil/series controls cover both weekly origins, Gregorian century/leap rules,
  month/quarter/year boundaries, DST lengths, domain edges, unclipped intervals,
  duplicate collapse and quantum-invariant logical work.
- The existing 28 hand-authored cases in
  `portability/corpus/calendar-boundaries.json` are copied by
  `scripts/generate-calendar-runtime-laws.mjs` into compiler tests. Expectations
  and selected artifact bytes/CID are unchanged. The generator does not run
  product code or the Python oracle to produce expectations.

The first nonmonotone synthetic input incorrectly applied the +10-day offset
back to year 0001, which introduced an earlier exact occurrence. The corrected
input first changes from zero to +10 days at the epoch, then to -11 days at UTC
day 20. Civil day 9 now resolves to UTC day 20, while day 10 resolves to UTC
day 0. The independent expected interval `[day 20,day 41)` is unchanged; the
earlier 17/18 failure is retained outside the source tree.

Tracked recipes accept a clean complete SHA:

```sh
node reviews/2026-10-15-calendar-runtime/prepared-checks.mjs <SHA> transition
node reviews/2026-10-15-calendar-runtime/prepared-checks.mjs <SHA> laws
node reviews/2026-10-15-calendar-runtime/prepared-checks.mjs <SHA> api
node scripts/generate-calendar-runtime-laws.mjs
```

The JS recipes use the existing nonzero discovery wrapper, j1, outer270/TERM5
and child240. The API recipe runs ordinary `moon info` for the two affected
packages on JS/Wasm/Native, with no Wasm/Native execution. Interface generation
is permitted only by that recipe; no hand-written public interface is used.
No full Core, all-target execution, Proof, packed producer, live Provider,
Hosted CI or formal publication evidence is claimed.
