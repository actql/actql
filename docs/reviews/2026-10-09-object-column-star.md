# Closed object column star connection

## Baseline and scope

Initial main baseline: `4aa66a85ebd90f037b9a5a4af3d0850ed91b1bd1`.
This branch started at #1055 `935cca732b3ab9015ee23f13a395ca7489ed106f`.
#1053 and #1055 subsequently reached main. The #1055 adopted head
`a1f67d0a3c6106959b5f7c8d1acb356ab2ee7336` is an ancestor of adopted main
`7448151e13e9eff680077cf42b0f73c6136cb04b`. Ordinary integration merge
`ed441a86c4c864014001f26dea737ad7d156e923` completes without conflicts;
the PR now targets main with no remaining unmerged parent dependency.

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

## Clean packed acceptance and artifact correspondence

Normal producer/source SHA: `09a47b6d5207e60919ec4e3bfd08fbfd4fb048f3`.
The ordinary five-package producer, independent digest verification and
`node scripts/test-packed-public-query.mjs --computed-object-property-only`
all pass. Wrapper `run-7EBHaX` finishes passed/complete, exit zero. Receipt
`public-query-evidence-mrJ1hs` records ten complete successful commands, each
observing that same clean checkout; no evidence errors, and successful temporary
installations were removed by the existing harness.

Embedded Local and real HTTPS each finish **27 positives, 12 preparation
refusals and one expected execution failure**, retaining every original case.
All nine new positives and four exact `ClientProgramInvalidInput` refusals pass.
Seven exact refusals are individually logged per boundary; five original
refusals are established by the reviewed common loop and completed consumer,
not invented extra log lines. Named Result rows/describe preserve NULLs,
canonical star and SELECT column order, full types, duplicate rows, original
versus current slots and no internal field exposure. Source acquisition is once
per positive; attach and unchanged same-request replay do not acquire again.

Independent five-tarball rehash and retained log inventory:
`/private/tmp/actql-b-object-column-star-20261009-acceptance-audit.json`.
Normal package SHA-256 digests:

| Package | Digest |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `5e28c1fabbf8acbb5a00ea2d77a8ce8e3b5aefc04ed849d767b25ac477e29acf` |
| run-host-core | `bdeaef6c2ac908f5906439ff94a8098b0565221f0dec3bcd53ccde20dd17e87f` |
| local-node | `266fb4a202b32740dd5ae403a06f2664c5b3e51deb6cd596b2e865884fc82412` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The initial subsequent review-record commit
`17d6958678f2f09cc4d6bed3d0bc067adba74a27` changes only this document.
The later main integration adds existing submission/read test fixtures,
mutation validators, diagnostic fixtures and the parent's review record.
The compiler, runtime implementation and this cohort's fixture/consumer files
are unchanged from the packed source. This is not a new clean-HEAD packed
campaign or a claim of independently rebuilt final-HEAD package bytes.

After integration, the same two focused Node files pass **15/15** at clean
`ed441a86c4c864014001f26dea737ad7d156e923`, with pinned Node 22.22.0:
attempt `run-UDakvY`, evidence `focused-test-blSrUW`. An earlier Node 22.23.2
diagnostic also passed 15/15 (`run-Xe97Do` / `focused-test-2pZXOx`) but is not
the pinned check. Two sandbox-limited pinned launches stopped before tests
when the existing supervisor could not inspect its owned process group;
they are not executed test failures or successes. The successful pinned check
uses the unchanged supervisor. The final evidence update is documentation only.

Required submitted-HEAD CI, full Core, Wasm/native, broad packed campaigns and
ordered STRUCT conformance remain unverified. Draft preparation is not a full
integration gate. No merge or manual CI retry is performed.
