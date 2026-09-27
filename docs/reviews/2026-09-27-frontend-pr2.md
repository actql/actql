# Structural frontend PR-2 evidence

## Scope and source

The implementation starts from `292dbecc79eb0058bc3f89ff6ffb918f7ed730db`,
which includes the merged bounded builder from PR #8. This record is in
progress: the base is not a claim that the changes have been verified at a
committed implementation SHA. Final validation and CI remain pending.

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
| SYS-01 | `src/program_check/structural_text_test.mbt` | JSON/structural checker identity comparison; three-target final execution pending |
| SYS-03 | Trivia-preservation and source-location tests | Same admitted structure, original authored coordinates |
| SYS-04 | Identity-projection test in `src/aql_text/parser_test.mbt` | Changed Program ID and Effect name change the existing canonical projection; structural and JSON forms agree |
| SYS-05 | Manifest independent vector and Host substitution rejection | Structural grammar/rules included in compilation manifest identity |

FX-01 has pure checker coverage but no new instrumented provider-call counter.
Full FX-05/FX-06 runtime assertions and VEC-10 execution laws are not established
by source roundtrips. Later query, Effect recovery and installed source-routing
cases remain outside this PR's structural completion unit.

The following checks have run successfully during implementation, not yet as
final fixed-SHA evidence:

- `moon test --target js -p actql/actql/aql_text --deny-warn`: 21 tests.
- `moon test --target js src/program_check/structural_text_test.mbt --deny-warn`:
  2 tests.
- `moon test --target js src/run_publication_host/client_compilation_manifests_test.mbt --deny-warn`:
  1 test.
- `node --test scripts/aql-text.test.mjs`: 95 tests, using the generated JS
  test bridge.
- `node --test scripts/compilation-manifests.test.mjs scripts/frontend-profile.test.mjs`:
  7 tests.
- `node scripts/test-node-client-package.mjs`: passed after regenerating Local
  and Run Host bundles. Clean packed installation exercised translated Values
  and acquired-input Programs through actual Local and HTTPS Hosts, including
  Named Results, request conflicts, cancellation and restart/attach. Browser
  dependency closure remained limited to transport Client files.

The JS bridge is test-only and returns an empty string on translation failure;
the test callers reject that sentinel. It is not installed in the SDK. The
packed Client test uses translated Values and acquired-input Programs. Its
mode-option mock checks remain separate from actual Local/HTTPS execution;
they do not establish Hybrid completion. Full related gates and final CI have
not yet run. No native or Wasm frontend execution result is asserted here.

The initial packed run exposed a fixture-only failure: the request-conflict
negative changed a JSON value using a whitespace-sensitive string replacement.
The compact translated JSON made that replacement a no-op. The fixture now
asserts the original row value and changes the parsed Program explicitly;
the conflict assertion and full packed run then passed.

## Remaining validation

Finish the requirement-to-execution mapping, regenerate dependent bundles,
and verify the affected lint, core, spec and Client jobs. Public interfaces
and canonical manifest changes require the three targets and API freshness.
The packed Host test must establish execution separately from source
translation. Record the implementation SHA and final CI before delivery.
