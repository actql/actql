# Object member spelling: checked Frontend counterexamples

Status: Frontend repair in progress; selected packed Local/HTTPS acceptance
passes at the recorded clean source. Complete feature coverage remains open.
Source: `62ebd828c4731d7b78d54241a63a532996630c2a`.
This is separate from #933's grouped implicit-alias repair.

## Requirement and independent control

`docs/spec/query-text.md` specifies ASCII case-insensitive column, field and
alias lookup, including backtick names. Google's selected [lexical case rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#case_sensitivity)
also distinguish field names from case-preserving string values. This finding
concerns closed, typed object fields. It changes neither JSON key equality nor
Graph label/property contracts.

The [retained positive regression probe](repro/object-member-case/object_member_case_probe_test.mbt)
is not installed in the normal test suite while unfixed. It independently
writes a complete JSON Program before compiling any source. Its Values schema
has `id: number NOT NULL` and a nullable closed `payload` object whose declared
field is `score: number NOT NULL`. Input rows are:

```json
[{"id":2,"payload":{"score":20}},{"id":1,"payload":null}]
```

The independent Program uses ordinary `property.name = "score"`, derives one
slot, and selects `value, id` in that order. It passes ordinary checking. The
exact-member source `SELECT payload.score AS value, id FROM objects` generates
the same complete Program. Expected rows, as an unordered multiset, are:

```json
[{"value":20,"id":2},{"value":null,"id":1}]
```

`value` is nullable number due to the nullable receiver; `id` is nonnullable
number. There is no ORDER BY in this minimal example. No field is inferred from
rows and no lowercase transformation is applied to values or schema keys.

## Observed failure boundary

The same schema is rejected by normal Program checking after each of:

```sql
SELECT payload.SCORE AS value, id FROM objects
SELECT `objects`.`payload`.`SCORE` AS value, id FROM objects
SELECT (COALESCE(payload, payload)).SCORE AS value, id FROM objects
```

The first two should have the same complete ordinary Program as the independent
control. The third retains its authored COALESCE computation but accesses the
same declared field and has the same row/type expectation. The probe does not
claim structural Program equality for that computed-receiver form.

All three fail with `Pipeline.Operation.Expression.UnknownField("SCORE")`.
The positive tests deliberately remain red; this is not a new rejection
expectation or a permanent language restriction. Guard `run-ekIALP`, focused
receipt `focused-test-TQc70r`: 4 selected tests, 1 passed and 3 failed. The
control admits first, and the failure assertions identify the exact cause.

The source-to-common boundary is `query_expression/lower.mbt`: unresolved path
suffixes and explicit property members preserve the authored name verbatim.
`expression_typing/signatures.mbt` then correctly performs exact lookup for the
ordinary machine `property` operation. Merely folding every authored name to
lowercase would still fail when the declared field is `Score`, and would
silently choose one member when `score` and `SCORE` both exist.

No public Host/Run failure, packed source acceptance, request identity or
provider I/O result is established by these compile/check probes.

## Implementation direction and boundaries

B retains the Frontend repair. Existing common machine semantics stay exact.
The Frontend must map an authored member to the unique actual name in the
receiver's declared closed-object contract, after the correct column/alias/
qualified receiver binding. Unknown and case-ambiguous names must not fall back
to a different receiver or create a synthetic field. Explicit output names and
implicit authored output spelling remain independent of this member binding.

The current `query_program.Input` and transient SELECT/DATA/CTE bindings carry
column names but do not retain recursive column contracts. A complete repair
must propagate schema facts through current physical slots, including SET,
projection, GROUP, JOIN, CTE and parameter-produced objects; it cannot restore
an input schema after a receiver has been replaced by an output alias.

Available authoritative APIs already include:

- `value_contract.read_author` and admitted parameter declarations for input
  contracts. They provide schema facts, not values or acquisition permission.
- `expression_typing.check` / `result_type` / `node_at` for computed receiver
  contracts. Reuse these rather than implementing Frontend arithmetic, CASE,
  COALESCE or nullability inference.
- `relation_typing.check` / `output_schema` for ordinary operation schema
  transitions. This is a type probe, not order/key/capacity admission or a Plan.
- The final ordinary Program checker/planner/Host remains mandatory. Any
  transient Frontend fact must correspond to its actual retained slot.

Next, connect those facts to member resolution with bounded work and retained
origins. Preserve qualified input versus output alias provenance, empty input
schemas, nested nullable receivers and declared case. Include a collision
schema with distinct `score` and `SCORE` values so exact-name preference cannot
hide ambiguity. Computed receivers require common typing; a reference-only
rewrite is insufficient. No new executor, JSON normalization or compatibility
fallback is authorized or needed by this repair.

## Reproduction and retained evidence

In the source revision above, temporarily copy the retained probe into
`src/query_program/object_member_case_probe_test.mbt`. It uses existing
independent test helpers from that package. Select only:

```text
moon test --target js src/query_program --filter 'member case probe*'
```

Use the repository's pinned toolchain, `runFocusedTests` nonzero wrapper and
`runLocalCheck` guard (`heavy: false`, timeout 120s, TERM grace 5s). Remove only
that temporary source copy after the gate has terminated. The saved probe and
raw receipts remain. No full Core, Wasm/native, proof, performance or packed
campaign was run for this finding.

Local retained paths in B's reused, clean source worktree:

- `_build/frontend-member-case-probe/summary.json` and saved probe.
- `_build/local-checks/attempts/run-ekIALP/summary.json` and command streams.
- `_build/focused-evidence/focused-test-TQc70r/` command receipt and streams.

The working directory is
`worktrees/actql-frontend-having-grouped-subexpressions`, now on the independent
`fix/frontend-object-member-case` branch. The old grouped-projection PR is
merged; this branch does not modify #933 or any teammate's worktree.

## Integrated branch state

After the recorded probe, #933 was merged externally with reviewed public
branch head `c879fd6beb7a161d9fdb0d81da309591555b705d` and main merge
`2fde4022be54b035f89b4807c415b781262823f6`. B does not push further changes
to that closed PR. The member-resolution branch normally adopts main
`c28c05d941f4a3dadaa98a287015fd46721e79f0`, then preserves B's additional
pre-merge alias verification record through a normal merge. Its extra files
are only the retained probe and review records; no member-resolution product
repair is claimed.

The exact reviewed #933 head workflow query returned `workflow_runs: []`.
B's seven-test recheck is instead attributed to clean integration source
`4743484b7004ed8704310c663383c68e02596ad9`, as detailed in the [alias record](2026-10-08-group-having-implicit-aliases.md).
Neither the merge nor this preservation relabels previous source evidence as
CI success or as packed public execution. The remaining member-case repair
and the complete Frontend objective stay open.


## Current implementation and bounded evidence

The independent `fix/frontend-object-member-case` implementation now binds member
names after the query lowerer has chosen the actual column, output-alias or
qualified slot. `query_program/member_resolution.mbt` uses ordinary
`relation_values`, `relation_typing`, `relation_join_shape`, `relation_append`
and `expression_typing` owners for schema/receiver probes; it introduces no
runtime or data-sampling path. It follows generated stage/step/Result producers,
including retained parameter declarations, and changes only uniquely resolved
authored property-name occurrences. Ordinary machine Program checking remains
mandatory and exact JSON field lookup remains unchanged.

The source preparation boundary now retains the field contracts already checked
against the published Source View/schema generation, rather than passing only
column names. `source_frontend.bind_query_context` rejects duplicate, unmatched
or column-inconsistent schema attachments. These are in-process Host facts,
not Client-supplied authority. Schema reading shares a cumulative work budget.
The selected Node/RelA preparation mirror is regenerated by
`scripts/connector-node-bundles.mjs --write` and checked read-only.

`program_source_builder.import_source` preserves value/key locations and
Authored/Generated roles while copying addressed fragments. It retains the
original builder's bounds and preserves string data, including decomposed
Unicode, CRLF and a literal backslash followed by n. Source copies do not rename
schema/data keys or weaken ordinary expression admission. The frontend skips
literal contents and uses the declared member spelling, including `Score`;
it does not lowercase values or prefer an exact member among folded collisions.

Working-diff evidence before the implementation commit:

- `run-geMEJS`: original four positive probes pass 4/4 (historical red was 1/4).
- `run-jVfLcH`: expanded binding regression 7/7, selected Node preparation
  caller 3/3, generated Node/RelA source freshness passes. This includes quoted,
  computed and mixed-case parameter receivers, alias/qualified scopes,
  CTE/JOIN/GROUP/analytic paths, removed-range refusal and folded ambiguity.
- `run-D7aqMJ`: publication binding 2/2 and source-builder package 10/10.
- `run-zCLdFY`: related existing property callers 20/21. The unchanged
  `computed object properties guard ORDER reuse by receiver reference meaning`
  expects two COALESCE occurrences for a qualified input-snapshot reference,
  but lowering emits one. The resulting split count is 2 versus expected 3.
- `run-zsZtyG`: a temporary, explicitly mixed-source diagnostic bypassed only
  the new member pass, and the same unchanged qualified expectation still
  failed. The temporary bypass was restored in `finally`; it is not a product
  path, clean-main execution or public distribution proof. The expectation
  remains unchanged. An attempted expectation edit was rejected by automatic
  approval review and was not applied.

New source cases are registered in the existing implicit-property and computed
receiver acceptance fixtures, including uppercase/backtick/computed/nested
members and output-alias ordering with independent rows/contracts. They are
not execution evidence until a normal five-package producer and external
Local/HTTPS consumer complete at their recorded clean revision.

Remaining work: preserve and resolve the qualified-reuse regression with
independent semantic evidence; validate the integrated-main source; execute
selected packed Local/HTTPS cases; review preparation work accounting and
additional typed producer outputs (Graph/INFER/NEAREST and unsupported schema
transitions). No full Core, Wasm/native, proof, performance or required CI
success is claimed. The complete Frontend objective remains open.

## Clean distribution acceptance and independent reuse correction

Draft PR: #942. Clean source
`a2f2c20f2bf5411b11b7e6c96251ca4032587f09` normally merged main
`d7fe0f11a90e898bce5004bb20dc1dd3522771a5`. Guard `run-RGXrJj` executes
the seven member tests successfully at that source. Guard `run-uYjeYX` builds
the normal five packages once and reuses them for both selected external
consumers; it is passed/complete and its locks are released.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-member-a2f2c20f2-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-member-a2f2c20f2-pack node scripts/test-packed-public-query.mjs --implicit-property-only
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-member-a2f2c20f2-pack node scripts/test-packed-public-query.mjs --computed-object-property-only
```

The implicit-property consumer has 13 normal cases and five preparation
refusals per Local/HTTPS transport. The computed-receiver consumer has ten
normal cases, five preparation refusals and one demanded-receiver execution
failure per transport. Independent rows/contracts, aliases versus qualified
input snapshots, empty/nullable inputs and public column/type checks pass.
Existing acquisition/retry checks remain. Evidence roots are
`worktrees/.codex-scratch/public-query-evidence-wWVFc4` and
`worktrees/.codex-scratch/public-query-evidence-o7Ug0o`. Their source records
are clean, complete, and passed; owned installations are removed after success.
The original manifest and receipts retain all five tarball SHA-256 digests.
These results do not cover later commits, all Core, Wasm/native or required CI.

The old qualified COALESCE count assertion was investigated before amendment.
The selected semantics and `docs/spec/query-text.md` require reuse when both
clauses resolve to the same input receiver. The independently written
`computed_qualified_reuse_expected()` explicitly derives the original
payload/other pair once, selects `original_score` and `payload = other`, then
sorts by `original_score` and `id`. It is checked as ordinary machine input
before comparison with source lowering. Guard `run-9Sz2Gs` proves full Program
equality for the original qualified source, 1/1, rather than deriving an
expected expression count from product output. The historical rejected
count-only edit remains distinct; it was never applied.

Mixed `.SCORE`/`.score` and quoted-member variants then exposed another
Frontend defect: syntax comparison used exact property names, so identical
resolved receivers could still produce a second derive and pre-projection
sort. Guard `run-9qqPXP` retains the pre-fix failure (6/7). The correction
uses existing case-insensitive field-name comparison in explicit Property
and reference-suffix equivalence, retaining receiver-slot/prefix identity
checks and ordinary member ambiguity/type admission. The independent Program
is unchanged; public rows, types, limits and qualified ordering expectations
are unchanged. A corresponding case is registered in the normal computed
receiver corpus. Later focused/packed receipts must be attributed to their
own source revision before this follow-up is called executed. Working-diff
guard `run-PkxVOw` now executes the computed receiver, GROUP property and
member-binding files: 24/24 pass, including all three mixed-case/quoted
independent Program controls. This is focused JS evidence, not clean-source
packed evidence for the follow-up.

## Refused-probe reservations and authored input types

Follow-up working diff over
`e1032c62d87ccc437c6d63638b20f94c8e4b2ee7`:

- Common type probes return consumed work on success, but no consumed work on a
  semantic refusal. The previous member pass continued attempting probes after
  such refusals. It also did not charge successful expression syntax admission.
  The pass now stops at its first semantic probe refusal and retains the complete
  remaining allowance. This is a conservative reservation, not measured usage.
  Ordinary final checking retains responsibility for the semantic diagnosis.
- The first member replacement reserves the exact retained Source node count
  for the final origin-preserving copy. Refusal does not consume that held copy
  allowance. Only that reservation is returned for the final copy; no additional
  type probe is allowed. Actual budget refusals remain Frontend WorkLimit.
- A missing producer schema is unknown, not proof of a semantically invalid
  receiver. Field-dependent probes are skipped in that case; subsequent
  independent known bindings can still proceed. No field/presence/key evidence
  is invented.
- Published Source View types still use the existing generation-bound Context
  attachment. Literal local Relation declarations use `local_relation_input.read`
  and its bounded usage, the ordinary common authored-input reader. The Catalog
  checked-contract reader is not appropriate for author object declarations:
  they legitimately omit checked-only `additional_properties`. Using it lost
  receiver types and left `SCORE` unchanged. The independent SQL/Pipe Program
  control retains the original declaration and expects declared `score`.
  Neither schema source authorizes read I/O or proves row/key conditions.

Focused evidence, not clean-distribution or full-CI evidence:

- `run-fiu07P` did not compile the initial whitebox fixture; this is not a
  pre-fix product failure. `run-fyQ8fe` discovered four tests but all failed on
  the fixture's foreign source path before exercising the product. The path was
  corrected to the builder document's `<generated>` path.
- `run-7Jt3HO`: 13/14. All six budget/unknown-schema whitebox tests and seven
  existing member tests passed; the new independent Program text had a missing
  closing brace. That authoring error was corrected without deriving the
  expected Program from product output.
- `run-I3F870`: 37/37 JS across budget, member, computed receiver, GROUP property
  and implicit property files.
- `run-JJIdfj`: the Node corpus test exposed its stale `[9,5,1]` case count after
  two previously added member-case regressions. Public rows/contracts and the
  refusal/execution-failure cases were unchanged. The normal-profile assertion
  now enumerates the eleven authored case names rather than only their count.
- `run-2d8Sxk`: member tests 8/8, including the exact MissingField refusal from
  the inappropriate Catalog reader, plus Node corpus tests 4/4.

The new refusal-budget invariant is established by the bounded whitebox
selection and source inspection; no historical clean-HEAD or public Run budget
failure is claimed. Selected external acceptance must be repeated on the next
normally packed clean revision before attributing execution to these changes.
Additional Graph/INFER/NEAREST schema transitions and the complete Frontend
objective remain open. No compatibility path, evaluator, common runtime owner
change, full Core, all-target campaign, or manual CI rerun is introduced.
