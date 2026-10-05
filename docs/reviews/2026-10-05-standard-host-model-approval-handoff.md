# Standard Host Model approval: first vertical slice

## Adoption and ownership

The integration retains A's unfinished prepared-owner candidate
`6125cbb031bf3ce4a59b18df4f28cfec287d030f`, then normally merges the published
call-set implementation `a0dc67bac44b4ce28b60c2f6cf7570f00562c561` from #363.
Main is integrated at `5236470651c863f9d59cfebf5b192da5e7db234d`.
None of these statements is a claim that the unfinished A candidate or #363
has completed content review or packed acceptance.

D owns standard Host integration and external Local/HTTPS acceptance for #310.
A reviews the common prepared owner and resource boundary. Existing #363
review fixes remain with dot. The Host now uses #363's installed continuation,
typed retained-input reader, finite call inventory, per-call settlement and
provider originals. It does not install a second inference driver or owner.

The D pre-adoption prototype and its regressions are preserved at
`2e0909bf8bdfb5e6f289f78d8510f68955ef8a63` and
`88f5772b0` and in `scripts/fixtures/model-approval-pre-adoption/`.
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
replacement/expiry/cancellation, and the newly agreed conditional common
Running-to-Cancelled terminal predicate remain separate unfinished checks.

The retained-history scan previously stopped at inherited singleton
`mergeBases` in `resolve-model-checkpoint-main-db141961.json` and
`resolve-model-checkpoint-main-e26f7500.json`. These original records are
preserved and the concrete error was reported on #363. It is neither a product
failure nor a successful history verification. Required hosted CI remains
unverified during the billing outage; no rerun or merge is requested.
