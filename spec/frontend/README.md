# Frontend r1 adoption baseline

The frozen baseline and imported index are PR-0 evidence, not a parser release.
Current structural implementation evidence is recorded separately in the
[PR-2 record](../../docs/reviews/2026-09-27-frontend-pr2.md); it does not rewrite
the baseline's historical observations. The agreed first milestone is
PR-0 (baseline and adoption), PR-1 (bounded source builder and origins), then
PR-2 (structural text and minimal formatter). Each unit is reviewed and merged
before starting the next. SQL/Pipe sugar, MATCH and full Client routing remain
in PR-3 through PR-8. No new execution API is part of this milestone.

## Fixed inputs

[baseline.json](baseline.json) fixes the actual integrated source SHA,
toolchain, current Grammar Manifest, imported requirement digests and existing
independent identity vectors. The base includes PR #3. The 72 imported
operations equal the 72 current Manifest operations; this does not establish
runtime support for all operations or equate them with Local's path counts.

The imported source material is immutable. Its older branch SHAs and waiting
instructions are historical. The public adoption record below stands on the
current repository interfaces; it does not require another repository to run.

[frontend-profile-r1.json](frontend-profile-r1.json) records all 36 feature
decisions, conditions, delivery units and explicit case mappings. Its
`adoption` field retains the imported supported/restricted/rejected decision.
`implementation_status` and execution evidence are separate. Feature mappings
are requirement associations, not claims that a case covers every surface.
Missing cases are recorded in `additional_fixture_requirements`.

[acceptance-index.json](acceptance-index.json) retains all 140 imported case
IDs. Their baseline status is `not_run`; the requirement digest identifies the original case,
not an execution receipt. Builder cases start in PR-1; structural coverage
starts in PR-2. Cases involving query or Host routing are not silently counted
as complete when their structural prerequisite passes.

The [structural orders source](fixtures/orders.structural.aql),
[independent Program](fixtures/orders.canonical.json),
[input rows](fixtures/orders.jsonl) and
[expected rows](fixtures/orders.expected.json) are byte-for-byte imported
requirements. The structural source now has a translation comparison against
the independent Program, as recorded separately; execution of its expected
rows is not implied by that comparison. The
existing identity-oracle files are recorded by digest, not regenerated from a
new lowerer. Additional metadata, Effect, special-expression and all-operation
fixtures and their verification scope are listed in the PR-2 record.

## Existing entries and missing connections

| Boundary | Existing entry / owner | Work assigned to Frontend |
| --- | --- | --- |
| JSON/YAML decoding | `source_value.parse_json_measured`, `parse_yaml_measured` | Preserve lexical rejection and measured usage; do not trust constructed usage |
| Bounded source admission | `decode_core.admit`, `source_map.admit` | Reuse admission and owner-bound map; add safe generated-source construction |
| Program issuance | `stage_syntax.parse`, `parse_bytes`; private `admit_program` | Add the admitted builder bridge in PR-1; retain the closed envelope |
| Semantic checking | `program_check.check_parsed`, `check_parsed_with_evidence` | Consume the same Program; no second checker |
| Structural text | No text format in `stage_syntax.Format` yet | Implement envelope, STEP, closed OP and minimal DATA chains in PR-2 |
| Formatting | `program_body` and `stage_body` retain full source | Preserve all structure; do not use `emit_metadata_stripped_program` |
| Host execution | `prepare_effect_free_client_program`, `prepare_client_effect_computation` | Representative ordinary Host test in PR-2; never erase Effects to recheck |
| Grammar identity | `compiler_grammar_manifest_wire`, `admit_client_compilation_manifests` | Coordinate exact manifest/pin changes with the implemented feature |
| Public source routing | SDK JSON/YAML formats and structured `start` | Full routing is PR-7; no parser dependency in the transport SDK |

Frontend owns builder, source representation and formatter changes. Shared
`stage_syntax`, checker or Grammar Manifest changes are isolated for review
before other callers adopt them. Host/ABI owns Run observation, ownership and
transport; Local owns execution and retained storage. Their unfinished work is
not a prerequisite for PR-0 or the bounded builder.

## Acceptance evidence policy

Each executed case needs an actual fixture, independent expectation, suite,
result, source SHA and target; artifact and profile are recorded when relevant.
Document/inventory checks do not change any runtime case status. A case that
only exercises a fixture adapter is not proof of an installed public route.
JS, Wasm and native canonical comparison and normal Host execution are future
PR-1/PR-2 evidence, not asserted by this baseline.

Run `node --test scripts/frontend-profile.test.mjs` for the adoption inventory
and immutable fixture checks. It is included in `npm run test:docs` and the
existing `spec` CI job. Normative edits also require metadata regeneration and
`node scripts/local-checks.mjs run spec`. No runtime or public MoonBit interface
changes are made in PR-0.
