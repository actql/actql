# Retain every accepted typed-pipeline corpus stage

## Problem and resulting behavior

Numeric derive was admitted by #937 through the existing shared generator,
shrinker, model laws, route and independent consumer. Its wrapper retained only
the original six-descriptor corpus. A later eighth descriptor changes the
random stream and can discard previously accepted derive-containing inputs,
even when all local semantic predicates still have witnesses.

Retain an explicit ordered sequence of accepted registry stages in the existing
registry. The common corpus builder first completes the earliest stage, then
appends distinct inputs using newly added descriptors at each subsequent stage.
Previously accepted inputs, identities and order are retained. Each stage still
requires its complete concrete local obligations. Reversed, duplicate and
nonprefix foundation sequences are rejected.

The current seven-descriptor corpus remains exactly 114 inputs with digest
`9420e65ec1e80d508c740c0bc2130588a8f1a21119aa026787f1d2070a269b8f`.
This change adds no product operation, law, harness, Owner or cached action.
The existing 49 directed pairs, 22 predicates, required targets and mutation
campaigns remain. No test is removed or scientific obligation relaxed.

## Independent regression and extension procedure

A generator-only fixture extends the current registry using the existing Take
contract. It is not a new runtime operation. The former single-foundation rule
loses at least one of the 28 accepted derive inputs in this fixture. The corrected
default retains every current input byte-for-byte and appends only inputs which
actually use the added fixture. A second fixture verifies a further accepted
stage retains the entire preceding extension. Unique IDs and local concrete
predicate witnesses remain required.

A product extension must still supply its independent oracle, admission,
contract, generator arguments/reductions, real route and operation-specific
obligations. It appends an explicit stage, updates the independent final-part
count to the actual complete union and retains all required targets/campaigns.
Reference equality checks admitted descriptor prefixes, not semantic equivalence
of arbitrary changed descriptors. Editing generator/oracle/registration inputs
still changes the action identity and requires fresh verification. Retention is
not permission to reuse any old receipt or to strengthen finite evidence.

## Source and validation

G; final merge target `actql/actql:main`. #930 and #937 are integrated.

- Implementation source: `7f72280c284b7b33dedcd891d48dd82fe64c29ce`.
- Clean declared source: `3a28b010033d98239a7da72443bd32bb338b0352`.
- Targeted generator/engine/consumer checks: 48/48, working-diff guard
  `run-fZ1r22`; after strengthening the independent former-rule counterexample
  and second-extension case, corpus checks 6/6, guard `run-LCpZ7g`.

Commands through the existing bounded/nonzero wrapper:

```sh
node scripts/local-checks.mjs test node -- \
  proofs/relation-pipeline/corpus.test.mjs \
  proofs/relation-pipeline/derive.test.mjs \
  proofs/relation-pipeline/engine.test.mjs \
  proofs/relation-pipeline/evidence.test.mjs
node scripts/local-checks.mjs test node -- \
  proofs/relation-pipeline/corpus.test.mjs
node proofs/relation-pipeline/run.mjs js
node proofs/relation-pipeline/history.mjs
```

The source declaration records the two actual protected changes (`corpus.mjs`
and `corpus.test.mjs`) from their real parent/blob/mode identities. Registry and
README changes remain in the broad source snapshot. Hashes bind actual changes;
they do not establish semantic correctness. Existing immutable records and
verifier rules remain unchanged.

At clean `3a28b010033d98239a7da72443bd32bb338b0352`, guard `run-tkYV52`
passed actual JS/model execution and retained history. All 114 inputs were
checked, registered and completed; Session 14 and chain 54 typed/axiom model
laws passed. Source snapshot:
`1a10ed3e3d0b46629bdd4220a65fd914e78be006c8cb1f9880b63b41d3c0550e`.
The independent actual raw-log/report consumer accepted; all three compiled JS
artifact copies matched original receipt digests. Pipeline time was
40,928.589917 ms; serial JS/model step 63.752 seconds. History contained
261 declarations, 215 integrations, 27 supplements and 89 protected files,
and passed in 106.603 seconds. None is a before/after or CI savings result.

Original textual archive:
`evidence/2026-10-08-pipeline-corpus-stages-3a28b0100.json.gz`; 37 primary
members plus nine retained failed-attempt members, 859,020 compressed bytes;
SHA-256 `62cb08c26867212644469fefa2046fa24e80b639fd3e2ff2ad8483d7840ef048`.
Compression round-trip, member identities, receipt/source/input/log admission
and original compiled-artifact digests were verified. Binary copies remain local.

Adopted main `7e09fd17f7b17815c56a37c392a8cc9d65c2960c` by normal merge
`be1b0a9f6545e4d31ddbad54c9a0cecd7787d764`, after the original guard ended.
Compared with the registration parent, main changes none of the 89 protected
source files. It preserves the accepted corpus implementation bytes. The new
branch differs from main only in the four corpus/registry/procedure files and
the actual protected-source declaration. The final integrated ancestry check
is recorded separately below; original execution receipts keep their actual
`3a28b010` source and are not executions of the later merge/documentation HEAD. One failed attempt `run-Hp9m6H`
ran out of disk space while copying the actual whitebox JS artifact. Its guard
is incomplete and is not a successful producer or final acceptance. The original
failure/log/input evidence is retained before a later attempt. `run-CW1fXo` was
refused by another heavy owner before execution; no foreign lock was removed.

## Remaining boundary

The future descriptors above are generator-only controls, not runtime acceptance
for eighth/ninth product operations. No fresh Wasm/Native scientific acceptance,
full mutation/shrink/exploration matrix, physical/packed suite or final three-target
audit is claimed by the Node results. Required CI obligations remain.

Hosted origin authentication, qualification against a compatible later main,
ordinary-PR `mutations-js` reuse, related-input fresh fallback and net CI savings
including acquisition/authentication/checker costs remain a separate unfinished
unit. No Actions dispatch/retry, same-SHA self-qualification or merge is performed.


## Integrated ancestry acceptance

At clean `be1b0a9f6545e4d31ddbad54c9a0cecd7787d764`, the existing 600-second / 5-second-grace
guard ran `node proofs/relation-pipeline/history.mjs` after the normal main
merge. Guard `run-SnJNlT` passed in 87.116 seconds: 265 declarations,
217 integrations, 27 supplements and 89 protected files.
All 89 protected blob/mode identities match the actual `3a28b010` producer
manifest. No protected-source merge conflict, new merge resolution or verifier
rule change was required. Unprotected runtime changes from main are not relabeled
as tested by the earlier JS producer; its broad snapshot and original SHA remain.

The separate ancestry-only archive is
`evidence/2026-10-08-pipeline-corpus-main-be1b0a9f6.json.gz`;
3 textual members, 216,561 compressed bytes, SHA-256
`70f8bf5a92975818c3cf8cc251b5dc32abeeea0bf47f011d513d322831d57452`. It preserves the actual command, output,
terminal guard and unchanged-protected-input correspondence. Compression
round-trip, member byte counts and digests passed. It is provenance evidence,
not new semantic execution, hosted CI or evidence-reuse authorization.
