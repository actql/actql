# Frontend migration: independent source checkpoint

This ledger separates implemented source, public execution evidence and remaining
migration work. The integrated main baseline is
`11fde3441fdcf0766c583c5173ccf8e788a09751`, including the JSON composition in
#246. Results below retain their own verified source/package identities; they
are not blanket execution evidence for this baseline or the full migration.

The earlier Graph development integration combined B
`b19ed2cfb0bdce93832d47a8c3a7a8da95266c14` and C
`51376bca11d57b775aa22d42453176f8ad1f681b`. Fresh packed Local/HTTP acceptance
passed at clean `a6675aa5945389e66aa15978c9ed0ae66cbe69a1`, as recorded in
[public acceptance](2026-10-03-property-graph-public-acceptance.md).
That result does not establish all Graph consumers or completion of the migration.
Earlier checkpoints below retain their original source and package identities.

## Pure two-Source JSON/text composition checkpoint (2026-10-04)

The adopted main for this independent acceptance change is
`7dee31c1cc61b081f0feb12761b2bd5c2f41c12c`, including A #292 Native/Broad
acquisition and the formal cancellation/cleanup foundation. Fresh packs from
clean `27dc783a4c1b8dca34c496d21362c42866250513` passed
`node scripts/test-packed-public-query.mjs --two-source-only` through external
Local and authenticated HTTPS installations with no runtime MoonBit toolchain.
This is fixed-SHA local packed evidence; automatic PR CI is a separate check.

The submitted text is retained verbatim in
`adapters/host-node/fixtures/two-source/two-source-join.aql`. Both independent
JSON and text inputs specify Source predicates `id >= 0`, the same id equality
JOIN, `max_output_rows`/`MAX_OUTPUT_ROWS` 100, result column order
`id,left_amount,right_amount` and ascending order on those fields. Existing
expected rows/types/nullability remain unchanged. Matching negative Source keys
are deliberately present in both inputs' databases so losing the Source
predicates changes the joined output; duplicate rows and NULL amounts are preserved.
This does not introduce deduplication, a different lowerer or a new executor.

The existing harness now covers 12 normal cases (the previous 8 and 4 text
Native/Broad Local/HTTPS cases), 12 fresh-process retained cases and the same
12 recovery/failure scenarios. Each used Source has exactly one physical read
session. Unused Source installation opens no unused provider. Fresh attach,
row/description/stream reading, request lookup and resubmission of the exact
stored document/format return the same Run with zero provider opens or SQL I/O.
JSON and text Program/Run CIDs need not agree across different submissions;
generated Stage structure is allowed to differ without changing these semantic
and physical observations.

Second-input failure, cancellation, started-unknown recovery and cleanup retry
reuse the original owner/harness. A generation-drift fixture republishes its
alias against the deliberately changed valid SourceView, allowing the existing
Run dependency refusal to execute before I/O. An initial failed attempt at
`d7d8f7d7f238142e8ee81a2c3dc2ff28aa257f30` reached all normal/retained cases
but failed this fixture's Host alias initialization; it is not counted as a
complete acceptance pass. No product check was relaxed to repair that fixture.

Successful evidence is retained locally in
`public-query-evidence-DxoLOl/two-source-acceptance.json` (21 child command
records, zero unexpected failures); the earlier failed attempt is retained in
`public-query-evidence-B1bvYj`. Both live under the workspace `.codex-scratch`.
The packed local-node SHA-256 is
`f09bf206ecb80841375d93f3a56956c7aa61a4df3ac3b63bb42814ef0e9ea06c`;
run-host-core is
`ae96f379933ec3199cd02c4d2dac7b373815a37bb6d0345cf0f836b096209d2e`.
The pack manifest binds all five distributions to the fixed source above.

This closes the selected pure JOIN JSON/text comparison. Temporary confirmed
cleanup and zero byte/reservation observations remain distinct from an explicit
active-hold inventory and durable Named Result retention. The cumulative ledger
`holdings` count is not an active count. Graph→INFER→Effect Result Policy binding
and public acceptance remain D/A work in Draft #304; this pure JOIN acceptance
does not establish that Graph composition or its approval/restart boundaries.

## Implemented versus execution evidence

| Surface or boundary | Implemented checkpoint | Acceptance still required |
|---|---|---|
| Retired AQL/PROGRAM/STAGE and STEP/OP public entry | Typed refusal; no compatibility parser or formatter | Preserve existing SQL/Pipe and machine-input regressions when integrating the unified owner |
| JSON/YAML Program | Existing machine admission remains available | Machine execution is not evidence that replacement text executes |
| Relation DATA and explicit RESULT | Shared script parsing and lowering; public preparation retains named roots | Three authored source examples and the independent JSON control passed fresh packed Local/HTTP at `93f4689f3b5029b0a11b5435be6d1f0d5444718c`, as detailed below; this does not cover Graph DATA |
| Pure PROPERTY GRAPH | Bounded parsing and ordinary Program construction connected to C's unified owner | Fifteen keyed source cases passed packed Local/HTTP with exact rows and descriptions; common JSON snapshot controls and authored-source snapshot/TRAIL tests passed separately; source-specific exact snapshot CID assertion remains unexecuted |
| Named SGA calls | Nineteen adopted names and argument roles parsed by the shared query parser; DATA aliases and normalize-before-MATCH lower to retained producers | Adapted common Carrier/schema contracts for remaining calls; all promised examples through Named Results |
| Public Graph source | DATA constructor lowers to the unified ordinary Program; standalone retired Graph aliases remain refused | Packed Local/HTTP passed 18 successes, 3 execution failures and 12 input refusals per transport; required final CI and native CLI acceptance remain pending |
| Source INFER KEEP/AS | Selected source-free execution is in main through #261; common owner is reused | Seven positives/four typed refusals per Local/HTTPS transport passed at `1ba6c06670f991594a8404d7f61a28ab5bdb5789`, including NULL, complete descriptions/streams and fresh-process capture replay with zero Model redispatch; acquired-source text and wider compositions remain separate |
| INNER/LEFT/CROSS JOIN chains | #266 lowers ordinary SQL/Pipe, DATA and CTE chains to existing JOIN operations | Nine positives/four refusals remain the packed Local/HTTP target. Submitted `d4ba0a96ed94d3ba78e8ae126cf1577b5d283c86` CI failed on an imported-main history declaration before product jobs; updated source execution is unverified |
| NEAREST KEEP/AS | Independent source/Program/row/type fixtures and public consumer are prepared; explicit-profile common checker/Plan diagnostic succeeded using historical packages | Standard installed Host capability/source connection is coordinated with D, not waiting for a C artifact; public Local/HTTP execution remains unverified |
| Other target Effect, VecA and TEA surfaces | Adopted targets and machine capability are distinct from public syntax support | Feature-specific source, checker and real execution evidence; no bulk completion claim |

The public Graph refusal retains standalone installed Graph aliases; DATA pure constructors now lower to the unified ordinary Program.
No retired property-label route, simple-Graph conversion or old consumer fallback
is enabled. Syntax-only normalization must not be reported as common Graph
checker or kernel acceptance.

## Evidence and handoff boundaries

The [unified-source separation record](2026-10-03-property-graph-unified-source.md)
lists the constructor, checker, Graph identity, MATCH/TRAIL and public snapshot
interfaces required from C. Its retained authored fixtures specify independent
schema, rows, parallel edges, composite keys, static labels and NULL exclusions.
The [named-call checkpoint](2026-10-02-sga-query-calls.md) records B's parser,
lowering and canonical identity tests; its provisional-dependency results are
explicitly historical.

`src/source_frontend/unified_dependency_test.mbt` verifies keyed DATA lowering,
typed refusals and Relation DATA/RESULT preparation. It does not itself observe
Host counters, deliver a Result or roundtrip a snapshot. Separate packed evidence
now covers the selected Graph sources. The later
[source-INFER acceptance record](2026-10-03-source-infer-public-acceptance.md)
closes the selected source-free KEEP/AS cases, not the full INFER corpus.
The [JOIN chain record](2026-10-03-join-chain-frontend.md) separates ordinary
JSON diagnostic success from updated source execution still required in #266.
The [NEAREST connection report](2026-10-03-nearest-public-connection-boundary.md)
identifies its installed Host boundary and prepared, unexecuted acceptance cases.

C's earlier submitted candidate `8c052888503e130e3d6c5f5a5ea74037be407e3f`
and provisional #164 `125a186ae9396fbfc7865641922e8e8a4ffc87d9` are historical,
not current dependency inputs. The pushed unified SHA `51376bca11d57b775aa22d42453176f8ad1f681b`
was the development input for that Graph checkpoint. The user authorized connection before C's
all-CI or merge completion. Both parent SHAs, clean acceptance SHA and package
digests are recorded in the linked acceptance report. Formal adoption still
requires review and necessary CI. No unsubmitted worktree is a release dependency.

The [architecture and migration obligations](../design/frontend-language-migration.md)
remain broader than this implementation checkpoint. Existing JSON/YAML inputs
are retained capabilities, not completed replacements for withdrawn text paths.

## Historical main integration and Relation packed acceptance

The integration commit is `7a5d7c62148066ea1bfe0a4cc487161dc7ca1168`;
its source-registration resolution is recorded independently at the verified
SHA above. No C unification commit was adopted. Three merge conflicts retained
main's stronger DATA-task input-port checks and the existing packed controls,
while preserving B's authored source acceptance group. The group now reuses
main's independent JSON fixture rather than maintaining a second inline copy.

The two `client_data_set_task_wbtest.mbt` tests passed through
`scripts/local-checks.mjs`. The MoonBit formatting check, compilation-manifest
freshness and foundation source-history composition also passed. Grammar and
barrier pins did not change. An initial attempt used `-f` as a filename selector;
the runner rejected its zero-test result. Only the corrected two-test execution
is counted as successful evidence.

```sh
node scripts/test-packed-public-query.mjs --relation-data-only
```

At the clean verified SHA, normal prepack and an external installation passed
the same three authored sources and the independent JSON control on Embedded
Local and authenticated HTTPS: **4/4 positives and 3/3 preparation refusals per
transport**. Exact Named Result rows and declared columns, types, nullability
and order agreed with authored expectations. Internal sort columns were absent;
refusals left Run admission and provider I/O counters unchanged. The JSON control
returned `[{"id":1}]`. README controls, the existing planner-selection group
(22 Local/HTTPS cases) and the documented two-source example also passed.

All fourteen recorded commands completed successfully. The harness preserved
logs, command outcomes and digests, then removed its own temporary installation.
No whole local Core or Client gate was rerun for this integration.

| Normally packed artifact | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core-0.0.0-development.tgz | `ae2dce5569ed9e35db2b43b466e193c98574ba388c3c39e5837bbcb93deef512` |
| actql-local-node-0.0.0-development.tgz | `dcd251b0c70a27cbda77c9260ddc39f7252e176630d6a97003dcd644dfe771ec` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

[CI run 37078508563](https://github.com/actql/actql/actions/runs/37078508563)
completed successfully for the earlier implementation SHA
`5221799a271e2cb838d1806ea4db9d38b7d43135`. Conditional macOS/performance/probe
jobs were skipped. This is historical CI evidence, not same-SHA CI for the main
integration or evidence that new Graph/source-INFER execution works.

## Historical packed Relation DATA execution

Verified SHA: `979b59605ab4ff2d52ca3e772cfd93827b1816fe`. Its product sources
are unchanged from the checkpoint above; it adds the independent acceptance
fixtures and a narrow selection in the existing packed harness.

```sh
node scripts/test-packed-public-query.mjs --relation-data-only
```

The normal `npm pack`/prepack process built five packages from this clean SHA.
The installation was outside the checkout; the runtime had no MoonBit toolchain.
The ordinary installed Embedded Local and authenticated HTTPS Hosts both passed:

- Ordered DATA set input, hidden sort-slot reuse and LIMIT: `nodes = [{"id":1}]`.
- Quoted DATA reference and set ordering: `nodes = [{"id":1},{"id":2}]`.
- Explicit retained Results: `original` and `active` both contain `[{"id":2}]`.
- Independently authored two-root JSON Program with append, derive, sort,
  projection and LIMIT: `nodes = [{"id":1}]`.

Each transport passed **4/4** successful inputs and **3/3** preparation refusals
(forward DATA reference, duplicate DATA name and DATA supplied as SQL format).
For each success the harness compared exact Named Result rows and the complete
`Result.describe().columns`, including order and nullability. Hidden sort columns
were absent. Physical source-table reads were zero; attach, reread and identical
request resubmission did not increase admission or I/O counters. Each refusal
left those counters unchanged and request lookup returned `not_found`.

The independent JSON control also executes the formerly failing strategy shape.
It therefore supplies actual execution evidence beyond the earlier seven-task
preparation check; it is not a replacement for source acceptance. No strategy,
Graph carrier, provider, Host or common checker implementation was added by
this test commit. README Local/HTTPS quickstart and the packaged missing-wire
asset refusal also passed as the harness's existing controls.

| Normally packed artifact | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `9fd8d7c7019eafcd1401fa1804108644f13875b2197bb3d3e012abbb5428143e` |
| actql-run-host-core-0.0.0-development.tgz | `7360f0c9d09b8748cd0518df95045f509f14c62bd9da2cd9b2fb67f6d9ef7ad0` |
| actql-local-node-0.0.0-development.tgz | `6c204bb1c1ecb677fb350f9a491f7dd3f05be6e8829701cb2748009a3ce48798` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The harness retained command results/logs and these digests, then removed its
own successful temporary installation. This is local fixed-SHA acceptance;
it is not a same-SHA Linux CI result, Graph/snapshot acceptance or source-INFER
execution evidence.

## Historical development Graph connection

The connection target is C #164 public HEAD
`51376bca11d57b775aa22d42453176f8ad1f681b`, integrated with B
`b19ed2cfb0bdce93832d47a8c3a7a8da95266c14` in an isolated development
branch. This supersedes the historical submitted-candidate status above.
Starting acceptance does not require C all-CI or merge success, and is not
formal adoption or migration completion. Follow the linked unified-source
record and public acceptance report for executed tests and remaining coverage.
The later source-free INFER acceptance reuses the common owner already in main;
no frontend executor is introduced. JSON composition in #246 does not establish
equivalent authored-text composition or all Graph/VecA/TEA surfaces.
