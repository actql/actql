# Typed JSON literal common-owner boundary

Base: `7e337afa9e5a64035c5925aca1d93ba0ef787aaf`. Branch:
`feat/common-typed-json-literals`. This is a common-contract dependency of the
generic GoogleSQL JSON surface and Graph Delta source acceptance. It is not
completion of the text entry or Graph Delta acceptance.

## Review requested from A and C

| Owner | Boundary | Required review |
| --- | --- | --- |
| A | `expression_syntax`, `expression_typing`, `lowering_relation`, `execution_relation`, `model_execution/restored_capture.mbt` | One typed literal leaf and existing evaluator; no scalar coercion of JSON null; complete-input preparation budgets; capture restoration uses explicit typed-wire mode |
| C | `value_admission`, `canonical_json`, `run_publication`, `managed_graph_storage`, `graph_snapshot_identity`, `bounded_graph_diff`, `local_sga/delta_input.mbt` | Common JSON domain/envelope, retained keys/strings and profile identities; Graph identities/Delta bodies explicitly use the checked payload rather than the cell envelope |

No A or C review is claimed by this document. The changes need those boundary
reviews before integration. No new compute, submission, storage or recovery
owner is introduced.

## Source and wire

Machine source example, using the existing derive expression:

```json
{"derive":{"j":{"typed_literal":{"type":"json","value":"null"}}}}
```

The checked output is non-null `json`. Its canonical typed-cell wire is
`{"$json":null}`. A nullable JSON cell holding SQL NULL remains `null`.
The same domain handles JSON number, string, boolean, object and array roots.
Existing `literal` scalar/null inference is unchanged; existing object/array
literal inference remains JSON and uses the same new wire. Raw authored data
does not decode a `$json` key as a type tag.

The wire contract is separately pinned within the common expression law.
Result serialization preimages now contain that wire contract CID and the
existing format version. Versions remain 0.1. Expression/source schemas,
registry, grammar/Program dependencies, Values wire law, dependent pins and
independent canonical/profile vectors change together. Old untagged JSON
typed cells are rejected in explicit wire mode, without fallback. Graph
identity/Delta semantic bodies keep their existing body format; checked JSON
property cells use the common envelope.

## Selected decoding profile

Reference: GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
`ResolveJsonLiteral` / `JSONValue::ParseJSONString` with exact numeric parsing.
See [the design](../design/typed-json-literals.md) for official references.
Duplicate exact decoded keys retain the first value, while all input is parsed
and charged. Depth is at most 500 and additionally meets existing caller
ceilings. Data keys and string values retain CR/LF and Unicode scalar sequences.

The current common finite binary64 domain is an explicit numeric subset:
roundtrip decimal equality is required, so unsupported wide integers,
precision loss, overflow, underflow to zero and negative zero are rejected.
This does not claim the complete GoogleSQL signed/unsigned JSON integer domain.

## Evidence and remaining work

Independent fixed source/wire/profile preimages are in
`portability/corpus/typed-json-literals.json`. The expectation bytes are not
generated from the product. Existing Graph snapshot expectations remain intact.
The ordinary public-query harness includes two machine JSON successes (all
root domains plus SQL NULL, and an empty Result with full schema) and four
pre-admission refusals. The narrow selection is:

```sh
node scripts/test-packed-public-query.mjs --typed-json-literal-only
```

Focused JS checks cover parsing, Value admission and restoration, typing,
lowering, evaluation, Result delivery/profile identity, Values wire measurement
and Graph diff/apply. The latest affected-caller checks passed 54/54
(`run-n9LNQr`) and snapshot/encoding/closed-object JSON projection passed 14/14
(`run-88srQH`). Targeted Node contract/pin tests passed 23/23 (`run-wCXXsT`).
These logs are under `_build/local-checks/attempts/` in the branch worktree.
The changed storage fixture independently spells the JSON envelope; its
physical encoding is 43 bytes / 9 nodes rather than 33 bytes / 8 nodes.
Production ceilings are unchanged.

The first packed attempt at `e96e9b965cd1202b04c13a4404012bbeedc7b3eb`
stopped before the new cases: the README Program's common closure rejected
`UnsupportedExpressionContract`, because the Stage semantic emitter retained
the predecessor expression pin. Evidence: `run-uvDahB`, external command
`010`, `public-query-evidence-ffyP7M`. The fix updates the Stage semantic pin
and dependent authored Stage/Program/acquisition/nest preimages. Historical
preimages and PR-0 byte oracles remain retained, without compatibility fallback.
The resulting focused Stage/Program checks passed 35/35 (`run-F6FwlK`), and
ordinary README preparation/compilation plus historical profile tests passed
9/9 (`run-2gzubG`). That first packed failure is not acceptance evidence.

The second packed attempt at `5257fbd599bf0e7a00780bba96b446b86934455f`
passed the ordinary README Local/HTTPS checks, then stopped at the first new
machine input (`run-N6nw46`, command `012`, `public-query-evidence-HgUCie`).
That input incorrectly declared a JSON Values column, which the existing
Values contract forbids. It now uses a boolean seed and an ordinary IF with
JSON/NULL branches to produce the nullable JSON SQL NULL comparison. Values
admission is unchanged. The consuming preparation test also found that Plan
identity re-admission normalized JSON data keys in the emitted expression
body. It now preserves owner-checked keys through the existing strict parser
and canonical data mode. The all-roots/empty/README preparation and compiler
regression passed (`run-igukHi`), and the existing Plan fact identity regression
passed (`run-48VxoJ`). These are focused checks, not packed execution results.

Three-target public-interface verification and changed-package formatting
passed (`run-TgiV5D`); this checks compilation and interfaces, not three-target
runtime execution. Read-only literal/vector, Workers/Node fixture, canonical,
owned-version and document-family validators passed. Exact-SHA packed results
and tarball digests belong in the PR validation record after execution.

The third packed attempt at `0e1b87d05e356abed132ef0fb2acfc6ee39ed937`
passed the README Local/HTTPS controls, then failed while publishing the first
typed JSON Result (`run-9GYM9M`, `public-query-evidence-WeTsCy`). The existing
Captured Run issuer and contract restoration normalized a decoded JSON data
key again, invalidating the retained Result identity. Those boundaries now use
the same strict preserving parser as checked Plan identities. An independent
decomposed-key logical CID anchors the issue/restore regression (9/9,
`run-tzNg8Z`); duplicate rejection and all other contract checks remain active.
The SDK now verifies the Result serialization profile against the generated
common wire-law pin. SDK description, literal-contract and preparation tests
passed 8/8 (`run-ytH2Eh`).

The real installed Host diagnostic passed both all-root and empty-Result cases
(`run-Xvd7tt`), including ordered complete contracts from Result.describe().
It used the changed release bridge and source adapters, with the unchanged
DuckDB native dependency borrowed from the earlier Delta packed installation.
This is deliberately not recorded as clean new-SHA packed evidence. The test
is registered in the ordinary distribution-client job. A prior focused attempt
ran out of disk (`run-Z4BwiL`) and did not establish a test result; completed
regenerable native/Wasm check outputs were reclaimed while evidence and the
release bridge were preserved.

Clean packed Local/HTTPS passed at
`46944c33e9a28511bba714cc907db2cda9ad44fa`: `run-c9Dt9d`,
`public-query-evidence-zE61Qv`. Both transports passed every root versus
ordinary scalars/SQL NULL, empty Result rows and complete ordered description,
and four refusals with zero Run admission/provider reads. README controls
also passed. Its manifest records dirty=false and five tarball digests; the
installation was removed after saving evidence. This supersedes the failed
packed attempts, without turning the mixed-source diagnostic into packed proof.

Existing fixed Values Run/Result/request identity tests additionally depended
on the predecessor expression contract. Their hand-assembled oracle now
retains the old dependency-role hashes from the fixed base, derives the new
Stage/Program/Unit/Result/Run preimages independently, and preserves all old
Run vectors. The two Values issuance/identity callers passed 2/2
(`run-Gx309r`) and the independent vectors passed 2/2 (`run-GZnVdu`). These
later changes affect test oracles, expectations and this report; the packed
source SHA above remains explicit rather than being relabeled as later HEAD.

The subsequent clean packed Graph diagnostics probe at
`f80c8133158ee2bd4cf73cf4f5544d3c67dc26c2` reached a successful degree Result,
then failed its old untagged JSON identity expectation (`run-4zUkBL`,
`public-query-evidence-gA3vFP`, command `012`). The semantic identity, domain,
degree and order matched. Dependent diagnostics/traversal source fixtures now
spell the common JSON envelope, including ARRAY<JSON> items. The existing
public Graph caller's independently authored Relation row/Store preimages use
the same declared wire; its Graph snapshot and Delta semantic preimages remain
unchanged. This is a dependent fixture update, not a change to Graph identity.

The separate Frontend's clean packed source acceptance passed at
`078c600a0c21918339d7b078847e1749ad8532fb`
(`run-0feaIR`, `public-query-evidence-1tZPe2`). The Delta source path also
passed at `1bf39f4d8898b8118a2294a8541edb094bc2cf33`
(`run-GmKhiP`, `public-query-evidence-sJpmho`), including an authored generic
JSON literal passed to apply_graph_delta and independently expected p=8.
Each record covers Local and HTTPS and preserves its own clean source SHA;
these results are not relabeled as the common branch's later HEAD.

Remaining: the affected Graph fixture execution checks, A/C boundary reviews,
Wasm/Native runtime execution and required CI. These PRs do not complete the
whole Frontend profile or all Graph consumers.

## Normal main integration on 2026-10-06

Normally merged main `eb74d7b65d0f338ef5862a7d9cd7397744a08eaa` into
`c211bacde77abba79e727c443c676fb95ae3d9ff`. The merged lowerer retains both
typed JSON literal admission and main's shared membership-list lowering. The
SDK retains main's checkpoint byte verification and the common JSON wire pin.
Both parents' ordinary packed selections remain registered. Generated files
were regenerated from the combined bodies, including Workers then Node Host
fixtures; no freshness check or historical declaration was removed.

The combined expression law is
`sha256:800ab1eed12a3bcf98779493833081bc636c6ea108adbe1b57a57c01512b2f67`;
the Grammar Manifest is
`sha256:e891f9c133e66fbc4649b0cea7968f431e3285fd7f265f3304701eb0110e6816`.
The independent Values preimages retain the complete predecessor closure and
derive current Unit/Program/Result/Run identities from selected normative roles.

On this merge tree, focused JS lowering, JSON/membership evaluation, dependency
and Values issuing callers passed 34/34 (`run-igkYPv`, `focused-test-fdu1we`).
Node contract/SDK/grammar callers passed 8/8 in `run-utoNbP`; that attempt's
new frozen-vector assertion failed and was corrected from its original Git
contract bodies. The final independent vector checks passed 2/2
(`run-18QKFG`, `focused-test-ZZY8t9`). Read-only typed-literal, catalog,
Stage/Program, registry, canonical (370 identities), document-family and
Workers/Node freshness checks passed, as did selected formatting. These are
merge-tree observations, not clean new-SHA packed or CI execution evidence.
Prior packed records above retain their original source SHAs. Integrated
source/digest-bound public acceptance and A/C boundary review remain distinct
obligations; no merge is requested by this integration record.

## Shared-boundary coordination and packed selector follow-up

The 2026-10-06 coordination keeps Model original-wire preservation, cancellation
and recovery terminal decisions with D/A, Effect value/request/hook/Ledger work
with H, expression progress/holding/work with A, and pin integration with dot
and the applicable contract owners. B does not add competing repairs to these
units. The existing checked-response restoration change in
`model_execution/restored_capture.mbt::begin_restored_model_response` uses
`wire=true`; it consumes the common typed response wire, not the provider's
original Model wire. D/A should review this distinction when integrating #465.
A/C boundary review of #463 remains unclaimed.

At clean stacked-child `8c70aec7f080eee4acd16cb6e6fd4f415db3fd82`, normal pack
completed but public acceptance stopped at its first selector guard
(`run-Rnh9wy`, `public-query-evidence-mSzRSh`, command 001). The guard assumed
that the combined analytic selection was the first ternary branch. Adding JSON
selection ahead of it invalidated that textual assumption; the analytic cases
and independent contracts were still present. The guard now locates that
selection within the full chain, asserts its boundaries and retains all case
and mutable-state assertions. No corpus, capacity or Result expectation changed.
Focused Node profile/selector checks passed 11/11 (`run-sDjExB`,
`focused-test-VYXeRc`). The stopped packed attempt is not execution acceptance.
