# SourceView score admission and complete captured-input validation

This is the existing Phase 2 max/weighted completion dependency adopted in
`reviews/2026-10-11-integration-owner/source-ranking-scores-decision-20261014.md`
in the shared workspace. The author branch normally adopts main
`b2bd85846fb487c7b2e30495e917cd5a5fa6770d`, preserving the merged key-evidence
implementation and all prior failure receipts. It does not change Calendar,
Vector scalar fixtures, ranking policy semantics or the installed source engine.

## Owned declaration and projection

`carrier_facts.relation_scores` is a field-name map. Its values use the same
closed ScoreContract reader as existing local declarations and ranking arguments.
The reader and its data type move into the existing `vector_checking` dependency;
`relation_evidence` retains its public alias and accessor surface. This avoids an
Environment/Evidence import cycle and a second semantic decoder.

Environment admission keeps an opaque original facts/Catalog/schema declaration.
It rejects non-number, nullable, conditional and unknown fields. The checker
projects the original map through `declare_ranking_scores`, with cumulative
work/node/text budgets and the unchanged `SourceViewInput`. No connector input
is replaced by a private local snapshot. Complete-body dependency admission
retains independently owned key, score, lookup and file facets and refuses an
uninterpreted extension. The enclosing facts grammar remains extensible.

Original assertions follow existing lawful unary transfer. A completed producer
input retains its producer ownership; it is not rescanned as though a renamed
output were its original capture. Ranking's existing complete-input and matching
contract obligations remain in force.

## Execution boundary

The existing `execution_relation` input-admission owner resumes score validation
with a cursor over every original captured row and every declared field. It uses
its existing control allowance, bounded session and operation workspace. No rows
are copied, no additional execution allowance is minted, and cleanup drops only
borrowed references and its two charged cursor slots.

The ordinary sequence driver validates original input before import. The Local
Source residual completes original record and key guards, validates scores, and
only then enters filter/projection compute. The same remaining work allowance
flows into compute. Range failure has an internal typed `InputScore` cause. The
Native filter/select route refuses these pending obligations before execution
instead of issuing evidence for a filtered subset.

Two installed-source caller counterexamples retain the original two-page key
fixture: one invalid score on a filtered-out row must reject, and valid rows may
be aliased into `value` while their declaration retains its original `payload`
owner. Failed capture retains its execution reservation until cleanup succeeds.

## Independent oracles and identity

`portability/corpus/source-relation-scores.json` contains authored ASCII
preimages and independent Python SHA-256 identities. Two input IDs with score
0.5 yield weighted scores 0.25 and max scores 0.5 with IDs ordered 1,2. These are
fixed expectations, not generated runtime output. Existing missing/mismatched
contract and lawful/invalid transfer tests are selected by the prepared recipe.

The previous full interpretation contract is retained in `preimages/` at CID
`sha256:b513c6a3f6746e20822c51f3fc7dab2327e5ecfe339549b50e98976c11d21804`.
The new normative body has independent identity in `current-contract-identity.json`:
`sha256:b72f0e9566ffcb5495e801b342c9c578c90206a63e84761d367e5bd04bc0a13f`.
Empty and key-only body preimages, original Vector fixture hash `9717e6a8…`, old
saved Run identities and historical receipts are unchanged. Ordinary contract,
body-pin, document, requirement and canonical generators update dependents.

## Evidence and pending checks

Node-only `run-ICEb9Y` executed six independent score/key identity tests, read-only
contract/body-pin freshness and whitespace checks successfully. `run-0adnsL`
completed ordinary metadata/requirement/canonical generation (590 identities).
Evidence is retained outside the author tree at
`/Users/t14i/workspace/20260822/reviews/2026-10-14-b-source-ranking-score-evidence`.

The initial sandbox process-inspection refusal started no steps. The unchanged
normal guard, run with its required process-inspection permission, then failed
metadata generation because three requirement IDs covered six obligations
(`run-Ox67Jg`). Its first two generators succeeded; the failure is retained, and
only the corrected metadata and downstream generators were run afterward.

Moon tests, generated Moon interfaces, consuming-target compile and Moon format
have not run. `prepared-checks.mjs` selects admission, cursor and Source callers
under the existing non-Heavy 60-second/TERM5 budgets, JS `-j2`, clean source fences
and nonzero test discovery. It is preparation, not execution evidence. Root will
allocate those compiler windows after G's ordinary RC producer closes.

Normal installed Local/HTTPS max/weighted values, replay, acquisition counts and
cleanup remain unverified. No producer, consumer, Heavy, Hosted CI, external
Provider or formal release was started for this unit. RRF-only success does not
close max/weighted completion; the existing Calendar runtime gap remains separate.
