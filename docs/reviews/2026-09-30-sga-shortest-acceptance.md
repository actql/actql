# Additional SGA path and rejection acceptance

This follow-up uses the already registered `shortest_path` surface. It adds
no syntax, execution engine, provider-specific lowering or contract version.
It does not close the newer PR #92 edge Result order regression.

## Fixed inputs and changes

| Input | SHA |
| --- | --- |
| Frontend baseline (#63) | `2e21a039245ba681a90a7f18a3fd6e2797265107` |
| Retained Graph provider included in that baseline | `bf9813c65d423ee3fa854036868fd80dd7a783bb` |
| Verified source, clean throughout the gates | `5835d644410e702223c0b77250a9a154abfcabea` |

Branch: `feat/frontend-sga-shortest-acceptance`. The four commits after the
baseline, in dependency order, are:

1. `0faa6da01919963bb42691cbac63e69baf74ca20`: connect Shortest capacity
   applications to the existing Host ceilings and exact checked Program
   proofs. Output guards narrow the Host ceiling; they do not authorize a
   larger budget. Reach and Traverse retain their separate subjects.
2. `468ec676c1f19de0a09b9a7c2e759fb1658d12b5`: independently authored
   shortest-path source, Program and expected Result; focused packed selection.
3. `0a44c1824f03ef16f59484ce2d2100ca94044d86`: selected native CLI cases and
   public rejection/counter checks.
4. `5835d644410e702223c0b77250a9a154abfcabea`: project typed Graph query
   input errors through the existing common diagnostic categories. Internal
   scope failures, incomplete Graph evidence and ownership mismatches remain
   unclassified. Resource/configuration failures retain their own categories.

The diamond Graph has equal-cost A-B-D and A-C-D paths. The independently
authored fixture selects A-B-D under the existing node-identity tie break,
with cost 2, two hops and the A-B/B-D null-label edge tuples. No Result sort,
materialization or placement is implicitly added. The existing native CLI
and SDK continue to submit source to the Host and use the ordinary Run owner.

Before the category correction, invalid `max_hops: 0` reached the checker but
surfaced as `SubmissionUnknown`. At the verified source it returns
`ClientProgramRejected` on both Embedded Local and HTTP before acceptance.
The packed driver counts accepted Runs and actual source reads. A rejection
adds neither; it is not converted to an unknown outcome or retried.

## Executed validation

Using the pinned MoonBit toolchain and Node 22:

- Focused `program_check` JS: 343/343; source-to-Program 26/26 and common
  preparation 6/6 passed.
- `node scripts/local-checks.mjs run core --target wasm`: 7,034/7,034.
- `node scripts/local-checks.mjs run core --target native`: 7,096/7,096.
- `node scripts/local-checks.mjs run lint`: passed the version, format, public
  API, SDK type and portable dependency checks. The no-DuckDB batch passed
  62 tests with its one configured skip.
- `node scripts/local-checks.mjs run client`: passed. Client/Host 295/295,
  Embedded Checkpoint 7/7, Salesforce Site 277/277, packed Node/browser,
  native Client mTLS, and the existing Effect/capture recovery probes passed.
- `node scripts/check-core-without-connectors.mjs`: all targets passed for
  the isolated production closure of 101 packages, without Frontend imports.
- `npm run check:spec`: passed after the acceptance documentation update.
- Default `node scripts/test-packed-public-query.mjs` within the Client gate:
  all fourteen named SGA sources passed through packed Embedded Local and
  HTTPS Remote, including the original eight and the additional shortest
  path. SQL/Pipe controls and native CLI `normalize-rows` also passed.
- `ACTQL_TEST_SGA_CASES=shortest-path node scripts/test-packed-public-query.mjs`:
  the shortest-path Named Result passed both SDK transports and the Node-free
  native CLI. The negative bound added no Run acceptance or source read.

Packed acceptance preserves lookup, exact attach, same-request resubmission,
reread, normal stream termination and already-terminal cancellation. Its
schema-shaped expectations check row shape and values, not public schema
metadata: the current Result API does not expose schema/nullability/column
order. The common typed Program and kernel tests remain separate evidence.
These are local tests, not real external Graph provider or pushdown tests.

## Artifact correspondence

Both packed runs used the verified source and these SHA-256 digests:

| Artifact | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `8831e97c0f431c0d0e60c52ba1b0eebad755f2fd2403963912daf82862cbfd8b` |
| `run-host-core` | `80c672c5db61d24f3532f8573e55f042d5c39e9e1ec9c3ff06bbeaed424a4294` |
| `local-node` | `fb1da9ffcd2a91b51403ec8952d000682327172c490570bc515383b84cc8cb8e` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |
| Native CLI binary | `919d05e1d5728e2d40825f4d830a5a3a75f63056b32a0e5cc34c5fd8dbe770d4` |

Evidence directories under the shared workspace are
`worktrees/.codex-scratch/public-query-evidence-gZ4DVo` (targeted path) and
`worktrees/.codex-scratch/public-query-evidence-XwH8kX` (full set).
Both retain source revision, tarball digests, command outcomes and logs;
their installed artifacts were removed after preservation. Gate logs remain
under the worktree's `_build/local-checks/sga-5835-*.log`.

## Integration status at the recorded source

This branch has not adopted PR #92's
`682ebfb4f45943dc30480d6263fe9b173620d61c`. The isolated A/B integration
verified at `70730f963681b7294139171d8e2954d5c45835c6` passes
`graphs-equal` on both transports but rejects `diff-apply` on both;
`mean-graphs` has the same independently diagnosed edge Result order gap.
Neither authored order nor expected rows have been weakened.

At that recorded source, PR #63 stayed Draft. The required next step was to
adopt a contract-compatible order witness and
rerun the original eight sources through the same
packed public Local/HTTP path. Current-main acceptance and a new Linux CI result
are not established by this record. The requested public Host Reach
Relation-selector cases (duplicates, empty selection, missing IDs, capacity
excess and cancellation) still need their own packed evidence; focused
checker/kernel tests are not substitutes. Real external Graph providers and
broader profile combinations also remain outside the evidence above. The
fourteen passing cases do not prove the full SGA goal complete.

The subsequent main integration includes the checked Graph order correction
and merged PR #63. Its original eight packed Local/HTTP/native CLI results
and the remaining Reach selector boundary are recorded in the
[follow-up](2026-09-30-sga-selector-host-followup.md). The earlier rejection
and Draft status above are historical, not current integration blockers.
