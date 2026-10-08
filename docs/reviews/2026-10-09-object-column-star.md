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
  structural grammar, snapshot or identity-law implementation changes are introduced.
  The documented query rules change their grammar-manifest pin and dependent
  compilation/Run identities, as recorded below.

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
At that integration revision, the compiler, runtime implementation and this
cohort's fixture/consumer files were unchanged from the packed source. Subsequent
grammar-pin repair changes compiled metadata and Run identity. The original
package cohort remains evidence only for its recorded source SHA; it is not
a fresh packed verification of the repaired revision.

After integration, the same two focused Node files pass **15/15** at clean
`ed441a86c4c864014001f26dea737ad7d156e923`, with pinned Node 22.22.0:
attempt `run-UDakvY`, evidence `focused-test-blSrUW`. An earlier Node 22.23.2
diagnostic also passed 15/15 (`run-Xe97Do` / `focused-test-2pZXOx`) but is not
the pinned check. Two sandbox-limited pinned launches stopped before tests
when the existing supervisor could not inspect its owned process group;
they are not executed test failures or successes. The successful pinned check
uses the unchanged supervisor. The evidence update at `595a822a4240681f4ed22c38df0dc76b724fd72e`
was documentation only; the subsequent pin repair is not.

Required submitted-HEAD CI, full Core, Wasm/native, broad packed campaigns and
ordered STRUCT conformance remain unverified. Draft preparation is not a full
integration gate. No merge or manual CI retry is performed.

## Grammar-pin repair

During the computed-receiver follow-up, read-only compilation-manifest validation
exposed an omitted query-rule regeneration. This is a defect in this PR's generated
contract closure, separate from its recorded packed row results. Initial selected
Node evidence `run-XZLHqH` / `focused-test-ncmTMb` is 9/11: manifest freshness and
the independently assembled current grammar preimage fail.

The source generators update the grammar manifest, its CheckEnvironment constant,
document imports and canonical vector. Query rules hash is
`cf3c7ae714ecd006a8e350aa84d7ae4c322e7eb2d7a275db06078ffad0d9cee9`;
structural query grammar stays
`a9065e539f56e2d8d57bbd4b9e813abf1ad5340dcfaa846517bbd22371959538`.
Grammar manifest CID changes from
`sha256:4943caba75b011ab9aebfc07d4f30ea4a5aefa72c50bc2eab44724cc3e6aaff9`
to `sha256:f403b42dd4a19e8a22629ba7f14f6bb6de754490194277e4f083ae0f08515bb5`.

The independent Values preimage oracle derives the new Run CID
`sha256:aa93f66a057c74f6f2749d69e9cb0cd580f766e89755e77adb4926779e8aa351`.
The old `093170ff...` Run vector is retained with its old grammar input. Ordinary
Values Unit, proof and ResultPlan identities are unchanged; grammar-dependent
template, compiled body and Run identities change. No old Run is relabeled.
The full independent before/after preimages are retained at
`/private/tmp/actql-b-object-column-star-manifest-vector-audit-20261009.json`.
Historical grammar vectors bind their complete original Program schema closure
from `1402d256473b7c0facd17a1040291559db911b0a`, not the newly installed schema;
their fixed expected CIDs are unchanged.

Pin-repair preparation evidence:

- The five selected Node files in `run-f4dKlz` / `focused-test-ixylSz` pass 28 cases;
  the SGA test module fails to load because of a duplicate local variable introduced
  during the fixture edit. After that naming fix, the selected SGA file passes 1/1
  in `run-n5vFK1` / `focused-test-y99rkl`. The four other files were unchanged.
- `node scripts/local-checks.mjs test moon -- --target js src/run_publication_host
  --filter '*run materials rebuild exactly*'`: 1/1, `run-dpYCRv` /
  `focused-test-sTm756`. This exercises the real issuer and independently pinned
  Run identity, with existing mismatch refusals retained.
- Read-only `compilation-manifests.mjs`, `update-document-metadata.mjs`,
  `check-actql-spec-family.mjs` and `check-canonical-json.mjs` pass; metadata has no
  pending writes, 380 canonical vectors match, and the specification validator
  still reports `conformance:false`.
- Read-only `workers-fixtures.mjs` and then `node-host-fixtures.mjs` pass with the
  pinned formatter. These projected fixture sources require no generated edits.

These are repair preparation results. The prior `09a47b6d...` package evidence
is retained separately from the fresh repaired-pin campaign below.

## Fresh repaired-pin packed acceptance

The existing selected cohort now passes from clean source
`4952f42c9293ec7636c0d7b240ee9be4a3bc1a54`, using normal production of all five
packages and independently rehashed tarballs. Wrapper `run-tESgYy` is
passed/complete, exit zero. Receipt `public-query-evidence-BSWIlF` records all ten
commands complete with raw/verification statuses zero, the same clean source,
no evidence errors, and successful installation cleanup.

Embedded Local and real HTTPS each pass the unchanged **27 positives, 12
preparation refusals and one expected execution failure**. The original five
unlogged refusals remain verified by the completed common loop; seven exact
refusals are individually logged per boundary. Independent Named Result rows,
full descriptions/nullability, canonical/SELECT column order, empty results,
duplicates, private-column non-disclosure and Source-once/request-replay
assertions remain unchanged.

Independent artifact/log audit:
`/private/tmp/actql-b-object-column-star-4952f42c9-acceptance-audit-20261009.json`.

| Package | Repaired source SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `5e28c1fabbf8acbb5a00ea2d77a8ce8e3b5aefc04ed849d767b25ac477e29acf` |
| run-host-core | `69fbc2393a054d981a7317af6f77577fec868a54236159df276de97a72b4b226` |
| local-node | `23ca25e07e245e87cbabdb3e0c5345840ebf2973b4f17934c676b6702f3842d0` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

This subsequent evidence-record commit changes only this document. The package
campaign is attributed to `4952f42c...`, not relabeled as freshly built bytes
from the documentation HEAD. Required submitted-HEAD CI remains unverified:
the exact `4952f42c...` workflow lookup returned no runs. The PR remains Draft;
no manual retry, Ready transition or merge is performed. Full Core,
Wasm/native, broad packed suites and ordered STRUCT remain outside this evidence.
