# Audited Local capability completion (Draft)

Initial validation baseline: `f74d8e6436f314092b412669ba1281d246b604a4`.
Subsequent own-branch integration includes upstream `a7fc10e9d2cbf9bcb51929f278028aa1bd5fd4cc` (#3249): its 16 disjoint files are byte-identical and the sole package.json overlap preserves both test registrations. The exact 42-case public suite and 25 file-store guards pass after rebuilding Node adapters; three nominal recovered-command guards also pass. No Moon source changes occur in this upstream delta. The full interface-owner check remains unverified: pinned `acorn` was restored with lockfile SHA512 verification, but its Git inventory stage requires a checkout rather than this source export. Normal read-only Git access requires credentials unavailable to this executor; no fake clean HEAD or passing result is inferred.
This is source-built Node Local evidence, not clean packed, Native/Wasm, hosted CI, or production acceptance.

## Scope and exact inputs

The 42 original refused inputs now return independently expected rows through one integrated public Local runtime. They cover 12 feature groups: String TRY_NUMBER (15 cases), NFKC and CASE_FOLD (12), NULL comparisons/predicates and signed source zero (7), SQL array access and STRUCT (3), relational composition (3), and JSON RIGHT JOIN (2). The permanent `adapters/host-node/fixtures/audited-capabilities-42.json` retains each input, expectation, baseline refusal, and the explicit correction of the formerly unexecuted TRY_NUMBER('-0') oracle from NULL to canonical zero. `client-audited-capabilities.test.mjs` replays the complete set.

This is not a claim that every valid query fits Local's resource profile. The residual overreservation below remains open and prevents treating this Draft as ready to merge.

## Semantic boundaries

Immediate NULL comparisons use independently typed peers; unknown names, incompatible non-null domains, and two unresolved NULLs remain invalid. Null predicates do not require a non-null domain. Signed source zero normalizes to canonical positive zero without relaxing negative-zero JSON Number or Parameter admission. A separately found leading-zero strip defect for 0e10 is corrected without bypassing the existing numeric parser.

Array OFFSET and SAFE_OFFSET have distinct common operation owners. Both evaluate children once, eagerly, preserve NULL propagation, and require integral finite Number offsets. Only SAFE_OFFSET changes out-of-range outcomes; neither hides child failures. Existing subscript semantics remain unchanged. Named SQL STRUCT lowers to existing object/property operations.

NFKC and full default C/F case folding followed by NFC use pinned Unicode 16 data and bounded portable continuations, not host normalization/lowercasing. Default Local text policy admits 4096 input codepoints, 16384 UTF-8 bytes, and 1 MiB output. The output envelope also admits conservatively typed NULL expressions; excessive inputs still fail. Existing state reopens, saved Run output remains readable, and new text operations execute without rewriting old Run originals.

JSON RIGHT retains authored identity and side bindings while traversing right-major/left-minor order. It null-extends only the authored left. Duplicate/null keys, empty inputs, asymmetric field names, cardinality error sides, and output ceilings are tested. A keyed SourceView cannot fabricate unmatched right rows from an incomplete fetched subset; that separate capability remains unavailable.

## Capacity regression found and corrected during review

An initial scalar-envelope optimization omitted each row container and actual input-port multiplicity. It budgeted 100 nodes for 1-column input although 51 rows consume 102 nodes. Two 26-row inputs consume 104. This was a deterministic accounting regression, not a random row threshold. It was caught before publication and was not merged or deployed.

The corrected proof includes row containers, every original port including repeated Step targets, cumulative output schemas, and external producer projection. Unknown/nested schemas fall back to the existing general limits. The 512 MiB ceiling, row limits, text/intermediate budgets, and failed-result isolation are not relaxed.

Independent public comparison: 78 boundary cases pass on both baseline and corrected runtime, spanning 0/1/25/26/49/50/51/99/100 rows, widths 1/2/4, multi-stage calculations, duplicate fanout and repeated producer ports. Twelve additional same-state concurrent/sequential executions over three reopen cycles pass. These observations are not an OS-memory measurement or universal leak proof.

White-box accounting checks read actual scanner counters: duplicated scalar input costs exactly `2*n*(width+1)` nodes; an exact allowance succeeds, one short fails without successful output, and cleanup returns workspace to zero while retaining caller-owned inputs. Bare row wire requires `1+n*(width+1)` nodes and the logical Relation envelope `3+n*(width+1)`.

## P1 open: conservative whole-Run reservation rejects small valid pipelines

Logical retained-byte quotes remain high: the three-row sort composition drops from 549,884,544 to 444,969,344 bytes; HAVING quotes 446,831,744 and the multi-stage Pipe 516,575,488. These are accounting reservations, not allocated RSS or measured peak process memory.

Adding one redundant `|> WHERE y >= 0` after EXTEND to the original three-row Pipe preserves the expected `[{y:6}]`, but check reports verified/runnable while submission returns implementation_limit. No result is published. A four-term constant UNION followed by ORDER likewise refuses: 17 tasks / 16 ports quote 550,205,760 bytes, above the unchanged 536,870,912-byte ceiling. The [P1 follow-up report](2026-10-24-local-overreservation.md) gives its minimal reproduction and consumer-by-consumer proof plan.

The generic wire node ceiling 100000 alone contributes 6.4 MB per import port; thirteen sort ports reserve 83.2 MB. Numeric-only text ceilings contribute 108 MB for the sort and 124 MB for the Pipe across providers/imports. They cannot be blindly reduced: shared limits also control Relation envelopes, schema identity, bridge/completion entry counts, and intermediate expression work. The algebraic wire-only savings are not implemented or claimed safe for those other consumers.

Follow-up must separate wire structural nodes from schema/bridge/completion limits, prove each consumer's count and lifetime, use the same selected proof for quotation and actual consumers, and retain negative one-short and partial-publication checks. Do not raise the global cap or special-case example row counts.

## Validation and limits

Integrated 42/42 exact results and permanent public regression groups pass. All 43 previously passing relational cases and all 167 previously passing scalar cases remain passing after integration (including explicitly expected failures). Unicode 16 official NFKC corpus: 19965 vectors in 80 batches, plus canonical guards; explicit cancellation/control exhaustion/workspace refusal is exercised during ordering, measurement and output construction. New array contract shape/negative mutation/predecessor tests pass. Normative requirements and 361 machine imports, generated identities, interfaces, and byte-pinned artifacts are regenerated together.

Focused checks do not replace full integration CI. Native/Wasm execution, clean packed acceptance and hosted CI are unverified. A retained ordered-params test has a fixed CID mismatch also reproduced on unchanged baseline; it is not silently updated from product output. FULL JOIN diagnostic Draft #3248 is independent and does not implement FULL JOIN execution. No merge, deploy, auth change or new issue creation is part of this work.
