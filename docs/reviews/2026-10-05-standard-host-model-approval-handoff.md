# Standard Host Model approval: first vertical slice

## Adoption and ownership

The integration retains A's unfinished prepared-owner candidate
`6125cbb031bf3ce4a59b18df4f28cfec287d030f`, then normally merges the published
call-set implementation `a0dc67bac44b4ce28b60c2f6cf7570f00562c561` from #363.
The subsequently published #363 HEAD
`90babd81d485892383811264cedeefa1306ade87` is merged into main and adopted
through a normal main merge at `6ec5252fbf04adcb1fb9593fc4156e3656b7a4c3`.
The D PR therefore targets main with no unmerged Model dependency.
None of these statements is a claim that the unfinished A candidate or #363
has completed content review or packed acceptance.

D owns standard Host integration and external Local/HTTPS acceptance for #310.
A reviews the common prepared owner and resource boundary. Existing #363
review fixes remain with dot. The Host now uses #363's installed continuation,
typed retained-input reader, finite call inventory, per-call settlement and
provider originals. It does not install a second inference driver or owner.

The D pre-adoption prototype and its regressions are preserved at
`2e0909bf8bdfb5e6f289f78d8510f68955ef8a63` and
`88f5772b06e952fff1ba780f9bc1eb8bb9de6790` and in `scripts/fixtures/model-approval-pre-adoption/`.
Those fixtures intentionally use the earlier ABI and are not current tests.
Their former explicit Store authentication test ports do not establish
production Store custody or public restart acceptance.

## Current acceptance path

The existing packed single-INFER runner also accepts `--approval-only`.
It fresh-packs through each package's real prepack producer, installs outside
the checkout, and submits the existing independent VALUES/assert/INFER/derive
Program through `@actql/node`. Three separate processes perform durable
Waiting, signed Model approval, and same-request Result retrieval. The same
cases run against Local and a trusted HTTPS Host; the `http` fixture label
denotes HTTPS, not cleartext HTTP.
The approval input contains distinct decomposed/composed Unicode and CR/LF
bytes. The actual provider verifies the submitted string after durable custody
and restart; the independent assessment expectation remains unchanged.

The independent expectation remains the original assessment row:
`[{"assessment":{"input_key":{"id":"a"},"outcome":"ok","value":{"reason":null,"risk":"high"}}}]`.
Expected physical calls are zero before approval, one after approval, and no
additional call after both Host and execution processes have exited. The
recorded request/Run identity must survive all phases. The focused selector
does not remove these phases from the ordinary packed runner.

Run the bounded producer/consumer using the existing local-check supervisor:
`node scripts/test-packed-single-infer.mjs --approval-only --keep-artifacts`.
The retained command evidence records the exact source SHA, package tarball
digests, child commands and output. No pristine latest-SHA packed success is
claimed until that invocation succeeds.

## Limited checks and remaining boundaries

After integration, 43 focused Node adapter/registration cases passed
(`run-edzZIw`, `focused-test-VLcqkJ`). At merge SHA
`855db9841456a60c5b85c8d9936690c80bd2ea70`, 15 JS MoonBit attempt identity and
retained readmission cases passed (`run-NfNnQQ`, `focused-test-JN99lc`).
Receipts live in this worktree's `_build/local-checks/attempts/` and
`_build/focused-evidence/`; they are local evidence, not CI results.

Source acceptance inherited from #363 is not fresh-packed acceptance. Its
mixed saved/unknown/unsent tests currently cover Local only; the independent
Model/Effect approval case covers HTTPS with Host reopening in one process.
External HTTPS mixed unknown, full-process Effect restart, current provider
replacement/expiry/cancellation, and public confirmation of the newly agreed conditional common
Running-to-Cancelled terminal predicate remain separate unfinished checks.
Four independent missing-condition Host counterexamples failed before the
terminal guard (`run-4j2WfD`, `focused-test-OcCa6K`) and passed afterward with
the existing Waiting checks (19 cases, `run-E5jlFc`, `focused-test-Pz9QyV`).
Durable original-Run fence readback across restart and duplicate cancellation
also passed (2 selected cases, `run-w9DNY0`, `focused-test-FscqKX`) after
preparing only the missing Checkpoint ABI from the checkout.

Original-Run packaging changed decomposed string data in every original leaf
before the fix (one failure and three passes, `run-jtOnNb`,
`focused-test-hM20K3`). Model packaging and durable snapshots now use the existing
SDK value-preserving canonical encoder, without changing account configuration
identity. Separate composed, decomposed, CR and LF fixtures pin the data bytes.
The four fixtures and selected Host/registration regressions passed together
(53 cases, `run-qniS6O`, `focused-test-Y0kwhS`) after the fix.

The retained-history scan previously stopped at inherited singleton
`mergeBases` in `resolve-model-checkpoint-main-db141961.json` and
`resolve-model-checkpoint-main-e26f7500.json`. These original records are
preserved and the concrete error was reported on #363. It is neither a product
failure nor a successful history verification. Required hosted CI remains
unverified during the billing outage; no rerun or merge is requested.
