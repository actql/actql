# Frontend acceptance after the sole Graph migration

Owner: B. Adopted main: `b98a50ff763d1367e344fdfa8aea380ec8749132`.
Main was normally merged into `fix/frontend-distinct-join-order`; no history
was rewritten. Existing Graph contracts, definition domains and dependent
identities come from this main. Historical receipts and saved Runs retain their
original identities. This acceptance does not certify the complete Graph family.

## Integration and focused verification

The merge preserves both the acquired-Source JOIN assembly from #639 and main's
single-JOIN grouped-scope dispatch. The packed selector preserves main's current
Graph spelling and all normal corpora while restoring the DISTINCT JOIN selector.
No old Graph alias or compatibility fallback was added.

At `5f8045be0c685e5fb78db90f0b7b777f84c6ec73`:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/distinct_join_order_test.mbt src/query_program/acquired_join_order_test.mbt src/query_program/single_join_group_test.mbt
node scripts/local-checks.mjs test node -- scripts/distinct-join-order-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

JS passed 13/13 (`run-rrljYc`); Node passed 10/10 (`run-w4XPkT`).
After the fixture/selector corrections below, targeted Node passed 8/8
(`run-bpQTvg`), covering HAVING, DISTINCT JOIN and character-length fixtures.

## Normal five-package public acceptance

Producer commands used the repository-pinned MoonBit toolchain and normal
prepack, without manual runtime overlays:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-resume-20261007-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-resume-20261007-pack node scripts/test-packed-public-query.mjs --distinct-join-order-only
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-resume-20261007-pack node scripts/test-packed-public-query.mjs --replace-call-only
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-resume-20261007-pack node scripts/test-packed-public-query.mjs --character-length-only
node scripts/packed-client-packages.mjs /private/tmp/actql-b-resume-having-final-20261007-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-resume-having-final-20261007-pack node scripts/test-packed-public-query.mjs --having-aggregate-only
```

Consumers used `npm_config_offline=true`, `npm_config_include=optional` and the
existing B cache `/private/tmp/actql-graph-composition-probe-e90/npm-cache`
through `ACTQL_TEST_NPM_CACHE` and `npm_config_cache`. Installations were private;
temporary HTTPS listeners used the existing harness. All expected rows,
multiplicity, column order, ceilings and submitted Programs were retained.

| Corpus | Source/package SHA | Each transport: successes / refusals / execution failures | Evidence directory under `worktrees/.codex-scratch` |
|---|---|---|---|
| #639 DISTINCT JOIN | `b9a6fa77971de5c4704b07f231493c12c6dd8015` | 7 / 3 / 1 | `public-query-evidence-jEQBvB` |
| #608 REPLACE | `b9a6fa77971de5c4704b07f231493c12c6dd8015` | 11 / 7 / 1 | `public-query-evidence-bGvw6j` |
| #645 character length | `b9a6fa77971de5c4704b07f231493c12c6dd8015` | 6 / 4 / 0 | `public-query-evidence-1amKH9` |
| #509 HAVING, including main's added cases | `58c3db8aeabe77c60c479e5dee2d3c34cb012a94` | 23 / 9 / 2 | `public-query-evidence-iXCsbN` |

All four targeted commands exited successfully. Both Embedded Local and HTTPS
reach Named Results, compare complete schema contracts and rows, verify stream
completion and replay without extra admission/acquisition, and require static
refusals to leave Run admission/provider I/O unchanged. Execution-failure cases
publish no Result. #639's original Pipe LIMIT/OFFSET case is included and passes;
none of its known cases was excluded.

The two producer manifests have the following identical tarball digests.
Their source SHAs remain distinct: later changes affect acceptance fixtures and
the runner, not packaged implementation. The record's `dirty: true` reflects
preserved untracked `review-artifacts/`; the producer/consumer build-input checks
passed without modifying or bypassing them.

| Package | SHA-256 |
|---|---|
| client-wire | `27066b9ab7a1f4a3f15dec782b17ccdff5f04aca45ca2b3bf1496bb6bca329c3` |
| sdk | `d72e590dca3666fa0d2444492b2ec4559b056008a5b8575d4bc4ebe24159baa9` |
| run-host-core | `9c0a75dcbb234f43643e31ec44d189606c6d317b449c1c4b7f2e4ef7210f307f` |
| local-node | `5b6bc75fb7e3f4c07aa7c2b09956770c92aeb943a4f35ed101af292b2c88fd0b` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Corrected acceptance defects and retained failures

- Character-length registration checked that its selector was the first operand
  of the scope predicate. Integration added other operands. The test now checks
  membership in that predicate and preserves the normal/focused route checks.
- Initial HAVING acceptance at `b9a6fa77971de5c4704b07f231493c12c6dd8015`
  passed 21 Local cases, then failed the complete object-schema comparison.
  `public-query-evidence-8BFd5o` retains that failure. The fixture had copied an
  authored parameter contract into a checked Result expectation, omitting
  `additional_properties: false`. The correction explicitly authors the closed
  object required by language sections "Closed value contracts" and
  "REL.values execution parameters"; rows and scalar field contracts did not
  change. The typed-empty counterpart now checks the same complete schema.
- The corrected HAVING corpus at `5eb4166071383481353f13be561bd14f3eee9de2`
  passed both transports, but the driver then inadvertently ran Planner selection:
  the HAVING selector was absent from `narrowPublicQuery`. That separate command
  failed with `ClientProgramRejected` / HTTP 422 at
  `planner-selection-public-query.mjs:399`. Its logs, installation and Stores
  remain in `public-query-evidence-SAAzn2`. The registration correction is tested;
  normal/full and explicit Planner selection still run that corpus. The final
  HAVING command above succeeds. This does not resolve or dismiss the Planner
  rejection, whose cause remains unclassified.
- The earlier disposable #639 integration's long-running attempt lacked a
  confirmed capacity-refusal log. It is incomplete diagnostic evidence, not an
  established capacity failure or a successful public corpus.

## Disk recovery and remaining coverage

Reclaimed approximately 605 MiB in five owned, unused generated units:

- `/Users/t14i/workspace/20260822/worktrees/actql-frontend-query-expressions/_build/js/debug`
- `/Users/t14i/workspace/20260822/worktrees/actql-frontend-query-expressions/_build/js/release`
- `/private/tmp/actql-b-json-delta-pack-F00bCT/npm-cache/_cacache`
- `/private/tmp/actql-b-distinct-join-order-pack-FNM6Nz/npm-cache/_cacache`
- `/private/tmp/actql-b-ifnull-pack-AgmWiL/npm-cache/_cacache`

Compiler logs, reproduction sources, Stores/journals, npm logs, original receipts,
tarballs/manifests and borrowed node_modules/toolchain were preserved. The current
incremental build is retained. This is gross owned recovery, not the change in
global disk availability while other work proceeds.

Full Core, Wasm/Native, the complete packed/Planner campaign, Graph acceptance and
hosted CI were not executed here. GitHub API returned HTTP 401, so current PR
metadata/CI and body updates could not be confirmed. These results are local
evidence only. Remaining work is exact-HEAD review/CI and a separate classification
of the retained Planner rejection. No PR was merged or CI manually rerun.
