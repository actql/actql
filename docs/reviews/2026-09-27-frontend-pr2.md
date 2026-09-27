# Structural frontend PR-2 evidence

## Scope and source

The implementation starts from `292dbecc79eb0058bc3f89ff6ffb918f7ed730db`,
which includes the merged bounded builder from PR #8. The validated local
implementation is `d38ca5bbc26c667b334e9ad7d09fc8c27282cb2b`. The final
PR revision may add evidence-only documentation; its CI result is recorded
in the PR. PR-0 and PR-1 are merged; PR-2 is ready for review, not merged.

The public `aql_text` package parses structural AQL through the bounded source
builder and ordinary `stage_syntax` admission. Consumers pass its Program to
the existing `program_check` entries. The formatter retains the full admitted
source. Native DATA supports explicit sources, alias-only declarations and
closed OP chains. Query sugar and installed raw-text Client routing remain
later delivery units.

## Independent expectations and scope of evidence

| Evidence | Independent expectation | What it establishes |
| --- | --- | --- |
| `src/aql_text/parser_test.mbt` | Hand-authored JSON Programs | Envelope fidelity, alias lowering, deterministic helper avoidance, exact resource boundaries, original spans and ordinary admission rejection |
| `src/aql_text/lexer_wbtest.mbt` | Explicit original offsets and lexical cases | Unicode, escapes, comments and token ranges |
| `src/program_check/structural_text_test.mbt` | Existing checked input fixture and explicit authored reference coordinates | Same checker identities and evidence requirements; forward references rejected at original source positions |
| `scripts/aql-text.test.mjs` | Imported orders JSON, existing SDK Values JSON and documented Programs | Full-source roundtrip, composite defaults, metadata, explicit no-ops and ordered bodies |
| Closed OP matrix in that script | Current Grammar Manifest and explicit expected step bodies | All registered spellings retain their bodies; this is not operator typing or execution coverage |
| `scripts/compilation-manifests.test.mjs` | Literal canonical preimage and independently calculated SHA-256 vector | New grammar/rules bindings; historical vector retained |
| `src/run_publication_host/client_compilation_manifests_test.mbt` | Current pins and altered manifest fields | Host admission rejects substituted structural pins |

The original 140-case imported index remains a requirements inventory. These
suites do not establish completion of cases that also require later query,
Effect execution or installed source routing. Valid metadata locations follow
ordinary admission: an exported root Result does not gain a new `meta` field.

## Local worktree checks

### Imported case correspondence

These associations describe the exercised part of each imported requirement;
they do not convert broader runtime requirements into translation passes.

| Cases | Executed evidence | Boundary |
| --- | --- | --- |
| STR-01, STR-02, STR-03, STR-05, STR-06 | Document corpus and explicit structure tests in `scripts/aql-text.test.mjs` | Full admitted bodies, independent expected Programs, permitted metadata, arrays, bindings, no-ops and unused steps |
| STR-04 | Formatter test in `src/aql_text/parser_test.mbt` | Explicit accepted gating and omitted default preserved; no receipt synthesized |
| STR-07, STR-08 | Self-import/missing Results test and common-checker forward-reference test | Ordinary rejection and original location |
| STR-09 | Existing two-stage common-checker fixture | Same-named input scopes retained through formatter/parser |
| STR-10 | Existing literal SELECT regression golden in `src/aql_text/parser_test.mbt` | `sql_source`/`selected`/`rows`/`answer` and Program ID preserved |
| LEX-07 | Explicit YAML parameter-expression tree in `src/aql_text/parser_test.mbt` | Existing `$param` object remains separate from source interpolation |
| LEX-01, LEX-05 | Lexer Unicode/escape cases and parser scalar/nonfinite negatives | Lexical preservation/rejection; source-map coordinate unit tests belong to merged PR-1 |
| VEC-10 | Ranking peer-list test in `scripts/aql-text.test.mjs` | List order and score policy bodies only; execution laws remain existing operator responsibilities |
| FX-04 | Peer Effect map reversal in `scripts/aql-text.test.mjs` | No sequencing inserted; runtime scheduling not newly exercised |
| FX-05, FX-06 | Formatter gating/Effect test | Declarations retained, not a runtime notification/receipt test |
| FX-13 | Closed OP and raw transport rejection in `src/aql_text/parser_test.mbt` | Rejection before a Host is called |
| SYS-01 | `src/program_check/structural_text_test.mbt` | JSON/structural checker identity comparison in the three-target core runs below |
| SYS-03 | Trivia-preservation and source-location tests | Same admitted structure, original authored coordinates |
| SYS-04 | Identity-projection test in `src/aql_text/parser_test.mbt` | Changed Program ID and Effect name change the existing canonical projection; structural and JSON forms agree |
| SYS-05 | Manifest independent vector and Host substitution rejection | Structural grammar/rules included in compilation manifest identity |

FX-01 has pure checker coverage but no new instrumented provider-call counter.
Full FX-05/FX-06 runtime assertions and VEC-10 execution laws are not established
by source roundtrips. Later query, Effect recovery and installed source-routing
cases remain outside this PR's structural completion unit.

## Fixed-source local validation

All checks below passed on macOS with Node 22.23.2 and the pinned MoonBit
installation specified by `toolchain.json`. Builds reused their cache; this
is not a claim of a clean Linux build. Jobs ran serially with no source edits
during each job.

| Source SHA | Command / scope | Result |
| --- | --- | --- |
| `d343c4c4a1db742638db92c0f76f7002a410a025` | `node scripts/local-checks.mjs run lint` | Pass, including version policy, formatting, public interfaces and portable dependency checks |
| Same SHA | `node scripts/local-checks.mjs run core --target js` | 6,768 tests passed |
| Same SHA | `node scripts/local-checks.mjs run core --target wasm` | 6,765 tests passed |
| `1c0069ea310607be4ab50cf3c4adc964d811cbd4` | `node scripts/local-checks.mjs run core --target native` | 6,827 tests passed |
| `d38ca5bbc26c667b334e9ad7d09fc8c27282cb2b` | `moon test --target <js/wasm/native> -p actql/actql/aql_text --deny-warn` | 22 tests passed on each target |
| Same SHA | `moon test --target <wasm/native> -p actql/actql/canonical_json --deny-warn` | 428 tests passed on each target; JS also passed on the identical fixture tree before its commit |
| Same SHA | `node scripts/local-checks.mjs run spec` | Pass, including generated vocabulary, schemas, pins, independent vectors, metadata and links |
| Same SHA | `node scripts/local-checks.mjs run client` | Pass: 152 Client/Host tests, packed Node/browser smoke, packed Checkpoint acceptance, native Client mTLS and 191 Salesforce Site tests |

The only code change after the JS/Wasm full-core runs was the scalar JSON
comment delimiter correction, covered by the three-target 22-test run.
The following commit regenerated three current schema/manifest fixtures from
existing specification pins, covered by canonical tests and the successful
spec gate. Historical independent identity vectors were not retargeted.

The Client job builds the JS test bridge and runs all 95 structural fixture
checks before its packed acceptance. Its installed Local and HTTPS Hosts use
translated Values and acquired-input Programs and check Named Results,
request conflicts, cancellation and restart/attach. The two common-checker
identity/location tests and Host manifest-substitution test ran within core.

The JS bridge is test-only and returns an empty string on translation failure;
test callers reject that sentinel. It is not installed in the SDK. Packed
mode-option mocks are separate from actual Local/HTTPS execution and do not
establish Hybrid completion. The browser dependency-closure assertion keeps
the transport SDK free of parser, kernel, DuckDB and Store dependencies.

## Resolved verification findings

- The packed request-conflict fixture used whitespace-sensitive replacement.
  It now asserts and changes the parsed row value, so compact source output
  cannot make the negative request identical to the original.
- Adjacent outer comments after scalar JSON bodies initially failed. A test
  reproduced this; the fix accepts those boundaries while rejecting comments
  inside JSON and incomplete numeric bodies. All three targets pass.
- The first spec run found stale generated canonical fixtures for the new
  schema/manifest pins. Regeneration changed only those three fixtures;
  the repeated spec gate passed.
- The first Client job lacked the local pinned DuckDB dependency. Installing
  its committed lockfile with `npm ci --prefix adapters/connectors/duckdb/node
  --ignore-scripts` resolved the setup failure; the repeated job passed.

## Delivery boundary

Before publication, two commit-body lines were wrapped to the repository's
72-character limit. Every corresponding commit tree was compared and is
identical; no published history was rewritten. Local execution SHAs above
remain the actual tested revisions. Their published equivalents are:

| Tested revision | Published equivalent | Identical tree |
| --- | --- | --- |
| `d343c4c4a1db742638db92c0f76f7002a410a025` | `6c4e4f58ebbac1471558945c8cb2e3450c1a5a6c` | `bd23a4e89475d7c9934068b07d3f433718e1fe3c` |
| `1c0069ea310607be4ab50cf3c4adc964d811cbd4` | `9d9bf8b24c370803bd0a878d19526c610b80c68d` | `e7523ed0187a72d95b251d000af56ea7d4360bce` |
| `d38ca5bbc26c667b334e9ad7d09fc8c27282cb2b` | `b6a2ab8499b0218b4e9388b08b547c1e5d6facfe` | `987f84f218f4ef2348ec928c74e0d33306ca143b` |

The structural implementation and local affected gates are complete. Linux
CI remains pending until the PR's exact pushed revision finishes; local
results do not replace it. No package publication or main merge is performed.

PR-3 through PR-8 remain separate: query/Pipe sugar, graph/domain syntax,
installed raw-text routing and the full frontend release. The 140-case index
is retained as the imported baseline, with the executed subsets mapped above;
it is not a claim that all Frontend r1 acceptance cases have passed.
