# Closed object column star connection

## Baseline and scope

Main baseline: `4aa66a85ebd90f037b9a5a4af3d0850ed91b1bd1`.
This branch starts at #1055 `935cca732b3ab9015ee23f13a395ca7489ed106f`;
its final integration target is main, with that dependency retained until merged.

The existing parser accepts `SELECT id, payload.* FROM objects`, but the
lowerer resolves receiver stars only as Relation ranges. The independent
property Program in `object_column_star_test.mbt` passes the common checker,
while source compilation fails before this change. The red attempt
`run-PNN53d` / `focused-test-PX7ANV` ran two tests: one passed, one failed.
Its failed unwrap establishes a lowering rejection, not a published Run failure
or an exact typed rejection code.

The selected [GoogleSQL expression-star reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
allows table aliases and values with fields. This connection expands named
closed object columns and qualified property paths using their existing common
contract. Canonical object field order is retained, as in the existing closed
object UNNEST profile. This does not supply GoogleSQL's ordered STRUCT contract,
anonymous/duplicate STRUCT fields, or arbitrary computed star receivers.

## Connection

- The ordinary SELECT/GROUP/analytic expansion boundary resolves object fields
  through the actual lowered Relation prefix. It reuses `MemberResolution` and
  common operation/expression typing rather than inspecting values or copying
  initial schemas over later SET slots.
- `relation_prefix_column` extracts the previously existing UNNEST prefix lookup.
  Its UNNEST caller still requires ARRAY and returns the admitted element type.
- A temporary metadata-only derive lets the common owner inspect the receiver.
  It is not emitted into the executable Program, Result, or Source acquisition.
- Star fields become ordinary property projections. Common checking owns their
  types, nullable receivers and runtime obligations. EXCEPT/REPLACE retain the
  existing input snapshot, names/order and scope boundaries.
- Existing range/scalar-qualified-star diagnostics are retained. A missing nested
  object receiver now reports the ordinary `UnknownReference` with source origin,
  rather than the former generic unsupported-receiver diagnosis. The old range
  scope test fixes this exact cause.
- No checker, execution owner, provider, physical strategy, wire/schema contract,
  grammar, snapshot or identity-law implementation changes are introduced.

## Independent evidence

The MoonBit complete Program control explicitly derives the nullable score from
`payload`, selects `id, score` through the ordinary evaluated slot, and compares
SQL, qualified SQL and Pipe lowering. Additional cases retain current versus
original range values, GROUP, exclusions/replacements, exact refusals, canonical
fields on empty input and bounded work. Expectations are authored independently;
no compiler output generates expected rows or field contracts.

Focused JS: `node scripts/local-checks.mjs test moon -- --target js
src/query_program --filter '*star*'`: **54/54**, attempt `run-w8PLbr`,
focused evidence `focused-test-aPR7gr`. This includes the existing range,
replacement, source-free/correlated/joined UNNEST star consumers.

Focused Node: `node scripts/local-checks.mjs test node --
scripts/computed-object-property-source-input.test.mjs
scripts/public-query-profiles.test.mjs`: **15/15**, attempt `run-vNDakL`,
focused evidence `focused-test-A2xclH`.

These are dirty preparation-state results, not final-HEAD CI evidence.
Changed MoonBit files were formatted with the pinned formatter; `git diff --check`
is required before submission.

The existing computed-object packed cohort retains its original 18 successes,
eight preparation refusals and one expected execution failure, and adds nine
object-column successes and four exact preparation refusals. The new successes
include an independently authored JSON control, unchanged SQL/Pipe/quoted paths,
empty input, NULL receivers, duplicates, canonical field order, SET's current
non-NULL receiver versus its nullable original range, EXCEPT/REPLACE and GROUP.
The normal packed route and its existing focused selection share these fixtures.
The existing consumer checks Named Result rows and complete descriptions,
internal-column non-disclosure, Source acquisition count, attach and same-request
replay. Exact preparation refusals must precede Run admission and provider I/O.

## Unverified at preparation

Clean exact-SHA ordinary five-package Embedded Local/HTTPS acceptance is pending.
Required CI, full Core, Wasm/native, broad packed campaigns and ordered STRUCT
conformance have not been established by the focused checks above.
