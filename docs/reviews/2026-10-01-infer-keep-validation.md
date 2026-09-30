# INFER KEEP/AS source construction: local evidence

Base: `6011cb8fb4bd85f832a62e16ff8358a45dcad44e`.
Implementation SHA: `ffc1cfcc97baa95f5c3b419c2eb0310f2db8541d`.
Source tree: `6c50aa99f3fc87593313894648da9840c360aa1c`.

This records the source-construction unit and explicit refusal before common
infer execution is available. It does not establish successful inference.
The [handoff](2026-10-01-infer-keep-handoff.md) identifies the independent
expected Programs and the exact common checker/execution dependencies.

## Executed local checks

Node 22.23.2 and the pinned MoonBit 0.10.12+1634b282e toolchain were used.
The spec job ran before a commit-message-only amend; its source tree equals
the implementation tree above. Subsequent job checks used the implementation
SHA directly. No tracked source was edited while a job ran.

| Check | Result |
| --- | --- |
| `node scripts/local-checks.mjs run spec` | Passed, including normative imports, pins, generated manifests, examples and metadata freshness |
| `node scripts/local-checks.mjs run lint` | Passed, including 0.1 versions, formatting, public interfaces, SDK types and the standard entry without DuckDB dependencies |
| `node scripts/local-checks.mjs run core --target js` | Passed: full check with warnings denied; 7,103/7,103 common tests; independent Run identity vector |
| `node scripts/local-checks.mjs run client` | Passed: 311/311 wire/SDK/Host tests, packed Node/browser and Checkpoint acceptance, native Client, raw public query, Result descriptions, 277/277 Salesforce adapter tests and Effect recovery/custody probes |
| `query_syntax` tests, JS/Wasm/native | 38/38 on each target |
| `query_expression` tests, JS/Wasm/native | 7/7 on each target |
| `query_program` tests, JS/Wasm/native | 83/83 on each target |
| `check_environment` tests, JS/Wasm/native | 192/192 on each target |
| `canonical_json` tests, JS/Wasm/native | 435/435 on each target |
| `node --test scripts/query-program.test.mjs` | 6/6; complete independently authored Programs compared through the rebuilt test bridge |
| Profile, compilation-manifest and independent Run-vector JS tests | 10/10 |

The first Client invocation stopped because the local DuckDB adapter's pinned
dependencies had not been installed. Installing its existing lockfile with
`npm ci --prefix adapters/connectors/duckdb/node --ignore-scripts` resolved
that environment failure; the complete Client job above was then rerun.
An initial Wasm package-prefix selector also selected the JS-only test bridge.
The corrected `moon test --target wasm src/query_program` passed 83/83.
These failed invocations are retained separately from successful evidence.

## Public entry and independent expectations

The existing packed public-query command rebuilt five real tarballs, installed
them outside the checkout, and used the normal SDK and Embedded Local/HTTP
Hosts with no runtime MoonBit toolchain. Both transports exercised:

- A working SQL/Pipe control and the existing scope/SGA regressions through
  Named Result retrieval and attach/reuse.
- Four INFER refusals: explicit KEEP, omitted KEEP, access through a removed
  alias, and a result-name collision. Each typed refusal left Run acceptance
  and acquisition I/O unchanged, and request lookup returned `not_found`.

The new successful/failed model row expectations remain explicitly `not_run`
in [expected-outcomes.json](../../spec/frontend/fixtures/infer-keep/expected-outcomes.json).
The nullable-object probe passes the normal checker and then observes the
common `ExpressionNotImplemented("property")` boundary without any model.
No alternate evaluator or capture record is supplied by these tests.

The Client job's existing Result.describe acceptance checks ordered,
composite and empty results, retention, authorization and bounds. Those are
ordinary results, not successful inferred-result evidence. Salesforce tests
use their existing test adapters; no real Salesforce org or paid model was
invoked. Linux CI is separate from these local results.

## Packed artifacts

Both public-query and Result-description runs recorded the implementation SHA
and the same tarball digests. Logs and summaries were retained; the successful
external installation directories were reclaimed by the existing harness.

| Artifact | SHA-256 |
| --- | --- |
| `actql-client-wire-0.0.0-development.tgz` | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| `actql-sdk-0.0.0-development.tgz` | `823149a8d04223425d9752b29596b72e72d3401ef168e6d164b7ec1557b38cf3` |
| `actql-run-host-core-0.0.0-development.tgz` | `54ce110c16d36413c84826bfaee2e401885a55ff02d6799152db91fe9d2e909f` |
| `actql-local-node-0.0.0-development.tgz` | `ea754f32de6a925c699cb23cff828a00d42e4bf0539cc6e29b5b1f1bdd8a104c` |
| `actql-node-0.0.0-development.tgz` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

Native Client mTLS binary digest:
`ef52c53fd8c6479d3bdc4f7c75448ba10acf37f6ff8cbf56a08ef9531cd4214e`.
The existing native public-source smoke also reached its Named Results.

## Compatibility and pending execution

The Grammar Manifest CID is now
`sha256:fbbd1ae95045ce44735086efc664fd37165857f18ba449f353e7055252053d49`.
Its changed grammar affects dependent Plan, Bound Invocation Template,
compiled-plan and Run identities. Pins and generated canonical vectors were
updated together. The changed Values Run identity was independently derived
from the hand-assembled preimage vector, not copied from an issuer response.
All owned contract versions remain 0.1.

Pending a separate common-owner implementation: checked infer, ModelTask
execution/capture and provenance, object/property execution, successful and
non-successful inferred rows, full inferred Result.describe, invalid-key
preflight, cancellation, and replay/reread without inference dispatch. These
remain the later packed execution acceptance, not completed by refusal tests.
NEAREST KEEP, old public-surface removal and Cloud are outside this unit.
