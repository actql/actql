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
additional call after the Host and execution owner have exited. In this
single-INFER fixture they are co-resident in each child process; all three
child processes exit between phases. This is not evidence for a deployment
with separate Host and worker PIDs. The
recorded request/Run identity must survive all phases. The focused selector
does not remove these phases from the ordinary packed runner.

Run the bounded producer/consumer using the existing local-check supervisor:
`node scripts/test-packed-single-infer.mjs --approval-only --keep-artifacts`.
The retained command evidence records the exact source SHA, package tarball
digests, child commands and output.

At clean SHA `b6d253a4f94fd39a481aa6bf4b9a714e8cf40310`, the bounded invocation
passed both transports and all three phases (`run-aaw1bN`,
`public-query-evidence-gwpLha`). Its completed summary records five fresh
prepack producers, the external installation, six successful child commands,
and each tarball digest. Both transports retained the same request/Run and
independent row while physical calls remained 0→1→1. This is local packed
evidence for that SHA, not hosted CI success or a claim about later revisions.

## Limited checks and remaining boundaries

After integration, 43 focused Node adapter/registration cases passed
(`run-edzZIw`, `focused-test-VLcqkJ`). At merge SHA
`855db9841456a60c5b85c8d9936690c80bd2ea70`, 15 JS MoonBit attempt identity and
retained readmission cases passed (`run-NfNnQQ`, `focused-test-JN99lc`).
Receipts live in this worktree's `_build/local-checks/attempts/` and
`_build/focused-evidence/`; they are local evidence, not CI results.

Source acceptance inherited from #363 is not fresh-packed acceptance. The
existing mixed saved/unknown/unsent, expiry, replacement and cancellation tests
now select Local and HTTPS, without a second process fixture. The Local
sent-unknown cancellation/restart case passed after dependency preparation
(`run-XBQG4m`, `focused-test-A0xngD`), with tracked fixture changes present.
At clean SHA `738d397cbf6352136dab4f3938225d7be818ef6e`, 25 selected public
recovery cases ran: 24 passed and the HTTPS saved-response cancellation case
failed at Host shutdown (`run-jPZvxE`, `focused-test-bnFa2f`). The Run had
already reached Cancelled, but the restored stop observer attempted to rewrite
an immutable physical-close observation after its asynchronous Store check.
Two independent overlapping-observer fixtures failed before the fix
(`run-2vUSUN`, `focused-test-eRyhV8`). Restored cleanup now rereads and preserves
an existing confirmed physical-stop record; the common continuation owner
still verifies the terminal cancellation predicate separately. No journal
rule or authorization check is weakened. Nine conditional cancellation and
overlap cases passed after the fix (`run-sqLmVN`, `focused-test-vSn12k`), as did
four Local/HTTPS saved-response and sent-unknown cancellation cases
(`run-R0FK7m`, `focused-test-2QjtWe`, with tracked changes present).
The independent
Model/Effect approval case covers HTTPS with Host reopening in one process.
Mixed saved/unknown/unsent recovery, immediate Allow, expiry, replacement,
current infer/egress refusal, and immediate cancellation passed in the
25-case invocation above. Those successes belong to the pre-overlap-fix SHA.
Full-process packed independent Effect approval and fresh-packed coverage of
the overlap fix remain unfinished checks.
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
An additional physical-stop acknowledgement counterexample passed with the
six existing cancellation cases (`run-mViPvL`, `focused-test-LydL9X`).
After removing the superseded prototype's two unreferenced bridge imports
and their generator entries, the selected Host bridge passed JS
`moon check --deny-warn` (`run-oZWIeT`). The read-only Node and RelA assembly
generator check also passed with the pinned toolchain.

The retained-history scan previously stopped at inherited singleton
`mergeBases` in `resolve-model-checkpoint-main-db141961.json` and
`resolve-model-checkpoint-main-e26f7500.json`. These original records are
preserved and the concrete error was reported on #363. It is neither a product
failure nor a successful history verification. Required hosted CI remains
unverified during the billing outage; no rerun or merge is requested.
The read-only scan at `68adb76c36a48a2dcf1fc5b886aefdca8f190bcb` reached its
120-second supervisor budget without an assertion result (`run-7sc0u9`). This
does not establish the current first history error or a successful scan.
The attempted fresh-packed invocation at
`99a990fdc3cbf875bb93a33dddb6720a800078f0` was refused by the occupied shared
heavy lock before its producer started (`run-2JfzwS`). No lock was removed.
At `2dd1955634bcbd1619e22cf5d7f457520aed8801`, all five real prepack producers
and the external installation completed, but the first Local approval case
was refused with `UnknownHostRootFormat` (`run-yE9W1n`, packed evidence
`public-query-evidence-1kgwkb`, command 007). The fixture had written its signer
key into the unadmitted Host root. Signer/report files now stay in the parent
fixture directory, outside the approval Host root; the Host format guard is
unchanged. The failed installation, original receipts and key custody remain
retained. This is not Model approval success.
At `f0ea85ad1b6844ca868d797e38cd61b13fbf7dd0`, the Local Run reached durable
Waiting with no provider call, then correctly refused artifact review because
the fixture had installed a signer without granting review read access
(`run-kbUH96`, `public-query-evidence-M6FufZ`, command 007,
`CheckpointReviewDenied`). The fixture now explicitly grants its owner review
read access, as the existing installed acceptance does. Product review and
signer checks remain unchanged.

The source recovery harness now explicitly prepares the ordinary Node package
exports using private per-package workspace links and the existing pinned
DuckDB dependency. It assembles and checks ignored adapter copies with the
existing builder, without another MoonBit build or changes to borrowed root
dependencies. Earlier source attempts failed before Model execution on absent
`@actql/sdk` (`run-1cS6Tm`) and absent `@duckdb/node-api` (`run-DB4lhm`).
These preparation failures are distinct from product recovery failures and
do not establish packed acceptance for a later SHA.

## Packed mixed-call recovery

The ordinary packed single-INFER runner also executes the existing public
recovery harness for both Local and HTTPS, under both `outcomes` and `fail`.
`--recovery-only` narrows to those four cases; it does not create another job or
remove them from the default runner. The same five tarballs and private npm
installation serve approval and recovery acceptance.

The shared child fixture now receives explicit public package entry points
and independently authored fixture files. Source tests prepare only their
private source dependencies; packed tests import `@actql/node` and
`@actql/local-node/http-host` outside the checkout. There is no fallback on a
failed package import, and neither path replaces the execution owner.

Each case records a saved first response, a sent second call with its response
lost, and a third call that was initially unsent. Repeated process restoration
must retain the same Run, never resend the unknown or saved call, and obey the
authored policy for the unsent third call. Independent SQLite and encrypted
Store inspections pin the saved/unknown/unsent states and actual provider call
log. Packed fixture custody remains with the retained acceptance artifacts.
The focused source HTTPS `outcomes` case passed after the entry-point refactor
(`run-wkC233`, `focused-test-8s16Vl`, tracked changes present). The new packed
selection is not yet claimed successful.

The adjacent acquired-Model case at
`3e1cac836c522ba35ad24645e3c5ec7bc664bcf0` stopped the sequential supervisor
before packing (`run-62tWXp`, `focused-test-mWpKmA`). Its read-only identity
observer compared a macOS `/var` fixture path with the installed adapter's
`/private/var` path for the same file. A diagnostic rerun fixed the exact
mismatch (`run-GUqxQP`, `focused-test-G6JdNc`). The fixture now resolves its
scratch directory before authoring profiles; it neither changes the product
path resolver nor relaxes the exact source identity assertion. Source approval,
Model approval, and frozen-input reuse then passed (`run-fpoPke`,
`focused-test-OWHRSQ`, tracked changes present). This is not packed evidence.
