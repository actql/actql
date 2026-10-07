# Preserve residual obligations when composing common guarantees

## Boundary and source identity

Adopted main: `465a501b6ccf1a7b57943d11d5d3614e3a53e511`.
Dependency: #909, normal-merged into this branch at
`818e40e45929392026cb10d4982cd98775c1d479`.
Implementation: `7039e502cf15500691ecc0747bcdb853d53381b8`.
Clean executed source including its retained-history declaration:
`58fa76336058994866e1b9975b5d080a140a009f`.
Final merge target is main; #909 remains a separate unmerged dependency.

The existing Session and chain composition gates reused common guarantees but
could lose the obligations that those guarantees do not establish. Set accepted
any nonempty residual list. Prompt, delayed-stop and pause chain claims did the
same. Nest and common premise checks also used `includes`, allowing a string to
match required text by substring rather than preserving independent list entries.
This is a metadata acceptance defect; no public Run malfunction was reproduced.

The gate now requires every already-authored residual obligation for the specific
scope, independently of the caller-supplied binding or derived claim. Each list
must contain unique, nonempty strings; each required entry must occur as an exact
list element. Reordering and additional unique local obligations remain allowed.
The Set baseline is the four existing authored obligations in `bindings.json`.
Nest uses its existing obligation inventory. Chain prompt/stop/pause lists retain
their exact original text. Source/target/artifact/connection coverage checks and
exact supported guarantee lists still apply.

This matters when adding a provider: use the existing common model and adapter
claims, register an independently executed connection, and preserve its local
meaning, work, capacity, ownership and physical obligations. A new binding or
matching digest does not establish those obligations. Existing capacity and Events
validators already compare their authored obligations; they are unchanged.
No generic framework, production owner, workflow, reuse policy or test retirement
is introduced. Product code, models, typed claims, old fixtures and binding JSON
are byte-identical to the integrated parent.

## Before/after and focused validation

A controlled diagnostic loaded the actual baseline gate modules from
`818e40e45929392026cb10d4982cd98775c1d479`. Replacing all residual obligations
with one unrelated nonempty line was accepted at both binding and final gates for
Set and all three chain scopes. The fixed gate rejected the same metadata while
keeping its controlled source/artifact records unchanged. This is a report
fixture, not physical execution, fault injection or an authenticated receipt.

The first diagnostic attempt failed because the fixture's Node command used
`node` instead of the final chain gate's required exact executable path. Correcting
only that diagnostic command produced the before/after result. Both attempts are
preserved; the first is not a product failure or a successful reproduction.

Working-diff focused selection passed 136/136 (no skips):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/bounded-session/evidence.test.mjs \
  proofs/relation-chain/evidence.test.mjs
```

This also executes the existing imported action-input and Events evidence tests.
Negatives cover unrelated residual text, each omitted Set and chain obligation,
substring embedding, non-array lists, duplicate entries and concatenated premise
text. Positive controls preserve reordered obligations plus an additional local
obligation. The evidence records the working diff; it is not relabeled as a
clean-HEAD Node run.

## Actual clean-source consumer

At clean source `58fa76336058994866e1b9975b5d080a140a009f`, the existing runner
`node proofs/relation-chain/run.mjs js` completed under the shared heavy guard
`run-fcpFun` (540-second combined budget, 5-second TERM grace).

| Boundary | Result | Duration |
| --- | ---: | ---: |
| Lean checker, exact proposition types and axiom audit | 54 laws | 9,725 ms |
| Session fixture | 7/7 | 630 ms |
| Prompt-chain connection | 4/4 | 28,958 ms |
| Delayed-stop connection | 6/6 | 1,965 ms |
| Pause connection | 2/2 | 1,273 ms |
| Actual final graph consumer | 5 conditional claims | accepted |

The original report fixes execution SHA, clean state, compiler pin, snapshot,
commands and actual generated JS artifact digests. Its artifacts were checked
again while archiving. These are local debug JS artifacts, not release packages
or Actions originals. The same guarded invocation then runs actual read-only
`node proofs/relation-pipeline/history.mjs`; it never uses `--write`.

## Remaining coverage

Native/Wasm, full Core, packed/public acceptance and hosted CI were not run here.
Set/Nest gate regression fixtures do not constitute a new physical Set/Nest
campaign. Normal integration obligations remain unchanged. Shared model proof plus
finite correspondence does not become proof of arbitrary provider implementations.

Authenticated successful full-main originals, compatible subsequent-main
qualification, normal-PR `mutations-js` reuse, related-input fresh execution and
acquisition/authentication/transfer-inclusive net CI savings remain unverified.
Their existing resumption plan is preserved; no periodic polling or dispatch was
performed. This unit secures obligation composition, not those economic claims.

## Retained-history acceptance and original archive

Actual read-only history passed at the same clean executed source: 246
declarations, 199 integrations and all 89 protected files. The guard records
complete streams, exit 0 and released locks for both consumers. The four changed
protected verifier/test files have declarations using their actual parent blob
digests and modes. No historical original was rewritten.

Archive: `evidence/2026-10-08-composed-residual-58fa76336.json.gz`.
The archive contains 31 original members: working Node output and focused/guard
records, both controlled baseline diagnostic attempts, the historical module
bytes, actual clean-source Lean/JS report and logs, and actual history output.

Expanded archive: 4,134,982 bytes; SHA-256
`06ded14ba82646bad18bbe6a3a33ab7a1f6ac0a5a4914273b37824080b6d0561`.
Compressed archive: 609,336 bytes; SHA-256
`9015c10acfa9c3617d60f275fc8994225bf98c12568745ee1683cfe1cfa20860`.

Generated JS artifacts remain in the owned worktree; the archived report binds
their digests, not a full distribution of binary bytes or a complete runtime
environment. A later documentation/archive publication commit does not relabel
these executions as that commit.
