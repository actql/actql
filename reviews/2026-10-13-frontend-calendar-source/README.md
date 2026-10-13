# Optional Calendar source connection

Adopted main: `0c6e9546f400c7972008c95ec195ac959642e014`, normally merged into
the preserved private Calendar branch. Original implementation commit
`d040303e2ac333e6d3c3070d8920226543b0e3b0` and all earlier failures remain in history.
This implements the already adopted Calendar surface in LANGUAGE_CHANGES.md and
`docs/spec/language.md`; it adds no default profile or alternative Calendar engine.

## User source and ordinary Program

```aql
WITH days AS (
  calendar_series(start: '2000-01-01T00:00:00.000Z',
                  end: '2000-01-03T00:00:00.000Z',
                  unit: 'day', timezone: 'UTC')
)
FROM days AS d
  |> calendar_bucket(time: d.start, into: month,
                     unit: 'month', timezone: 'UTC')
  |> SELECT start, `end`, month
  |> ORDER BY start
```

The existing Relation generator owner emits `calendar_series`; the existing
Carrier continuation emits `calendar_bucket`. Their exact bodies are compared
with the independently authored JSON control in `calendar_source_test.mbt`.
No Program is patched after lowering. Field and OutputName roles use the existing
resolvers; unit/timezone/week_start remain decoded literal strings, and endpoints
retain literal or whole Timestamp Parameter roles. The common checker owns unit,
zone, week-start, timestamp/NULL, interval, cardinality and resource validation.
A generator cannot consume a Pipe input. The fixed signature key `end` remains
available, while the ordinary leading column name must be backtick-quoted.

The checked Result has authored fields `start,end,month`; its canonical schema
field order is `end,month,start`. All three are required and non-null. Month is a
closed object with non-null Timestamp members start/end. Both the JSON and text
Programs must satisfy this same independently specified schema. The UTC two-day
rows and January bucket values in expected.json are **independent expectations,
not observed runtime results**.

## Selected profile ownership

Expose the existing CheckEnvironment's exact optional SelectedCalendarProfile
through one read-only accessor. Carry it through Context, publication/local
context binding, and both binding check-only/strict paths. Missing selection
remains a common refusal. Catalog and ModelTask owners must agree physically
with the selection's environment; equal CIDs do not make a freshly admitted
foreign environment the same owner. The frontend does not acquire TZDB bytes,
read host locale, authenticate raw profile text, or approximate civil days.

The UTC test artifact and complete environment envelope are independently hashed
in the Node control. Their bytes are shared with the direct MoonBit API control,
not obtained from an installed issuer or product serializer.

## Identity projections

Existing generators update only the authored query grammar/rules hashes and
containing grammar CID. The grammar manifest schema, barrier manifest, operation
inventory, expression rules, program/value identities and policies are unchanged.
The protocol-contract document's pin and four imports are the necessary metadata
projection; canonical generation changes only that current manifest case.

Retain the complete parent grammar/rules and Values preimages. Independently
assemble current Values preimages using the existing non-product oracle:

- Parent grammar: `sha256:04b977020143daec12a5e49925ef1024491d397ef56832339880f37170ef3700`.
- Calendar grammar: `sha256:bfe7a8b864c3c4562654e69145e755c7428b074a2e6950d95ba2a03d550ac9d0`.
- Parent Values Run: `sha256:bb1e2674cd4c88bf8e3d44f72194e0adf9e392a433f211be53d08ee8bd726b52`.
- Current Values Run: `sha256:32df49c43a64752de8f410f8312f75c3c02f55389856f62c2053a648f2fc8f45`.

Historical vector-score literal tests now read their exact retained parent rules;
their original preimages are not overwritten with Calendar identities.

## Execution boundary still open

The direct public preparation call `client_local_preparation.prepare_local_input`
reaches common checking with the exact selected profile, then returns
`Preparation(Lowering(OperationNotImplemented))`. Existing
`lowering_relation/prepare.mbt` maps Calendar to None. Normal Node environment
admission also has no selected TZDB artifact installation input. This is a
remaining common implementation/installation connection, not a Frontend runtime
fallback opportunity or successful Run.

No Calendar Local/HTTPS Named Result, installed runtime values, publication,
replay or cleanup acceptance is claimed. No new evaluator, default Calendar
profile, timezone data source, cast, capacity change or strategy workaround is
included. Native/Wasm execution, package production and Hosted CI are unexecuted.
New completed external installed E2E scenarios: **0**. The original frontend
completion goal remains open until its required public boundaries are closed.

## Limited evidence

Owner-local raw cohort: `2026-10-13-b-calendar-source-evidence` (not published).
Original source-free control 1/3, source parse and helper compile failures remain
preserved. They are not promoted to successes. The earlier six/ten-case passes
belong to their precise working-source overlays, not the current submitted source.

After main adoption, `run-50rQCh` ran the original ten JS cases successfully, and
`run-dT0jmn` ran five independent Node cases successfully. These precede the final
full-schema assertions; final fixed-source results are recorded separately in
the handoff. `run-GP7c7l` generated the three changed public interfaces from the
pinned JS compiler. Reviewed generator and formatter guards completed without
shared Heavy acquisition. No full Core, new Native, Provider or producer run.

Reproducible selections (existing Node/MoonBit pins, 60 seconds, TERM grace five,
nonHeavy; never run competing guards in one worktree):

```sh
node reviews/2026-10-13-frontend-calendar-source/prepared-checks.mjs
node reviews/2026-10-13-frontend-calendar-source/prepared-checks.mjs --node
node reviews/2026-10-13-frontend-calendar-source/prepared-checks.mjs --freshness
```
