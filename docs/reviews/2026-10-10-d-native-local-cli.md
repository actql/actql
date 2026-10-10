# Standard Native Local CLI: first connection unit

## Fixed baseline and scope

This work starts from main
`d4c8ed4987e8e25d4fc4f408b98705d90e7b7f53` in an isolated
`feat/native-local-cli` checkout. The original checkout's unfinished merge,
changes and evidence were preserved. The distribution work order is
`reviews/2026-09-23-actql-distribution/WORK_ORDER.md` in the workspace.

The assignment remains the complete standard Native Local CLI, including
Source execution, Result delivery, original-operation recovery, approval,
cleanup and outside-repository installation. This first unit does not finish
that assignment and must remain Draft.

## Implemented connection

The same Native executable now selects Local preparation only through explicit
`--mode local --config-root ... --config-file ...`. Remote remains the default
and still requires its connection, token and mTLS inputs at execution. Local
rejects those Remote inputs; no negotiation or rejected source format switches
to another engine or parser.

The candidate Local configuration is a closed, bounded `actql-config/0.1`
document containing `native.check_environment.file` and
`native.check_environment.evidence_bundle_cid`. Existing check-environment
admission validates the original; the declared CID alone is insufficient.
This preparation-only entry creates no store, key, grant, submission or Run.
It currently supplies no installed Source aliases or write bindings.

`prepare_native_client_program` lowers through `source_frontend`, inspects the
parsed Effect inventory, then selects the existing ordinary Program or Effect
preparation Owner. Rejection never falls back to another Owner. Static Effect
limits are shared with the existing Node bridge and Client ABI without changing
their former bounds. Authored strings and supplied values retain their exact
existing identities.

The CLI `check` response currently reports only `kind: prepared` and the checked
Program/parameter identities. It is neither the complete `docs/cli.md` checking
experience nor `actql-check-outcome/0.1`, and has no `verified` verdict or Run
reference. Connecting the existing diagnostic projection remains necessary;
no diagnostic catalog or wire schema was replaced.

Native crypto now supplies bounded secure randomness, exact-byte HMAC-SHA-256
and constant-time tag comparison through the configured library. RFC 4231
vectors are independent expectations. Existing Ed25519/private-evidence behavior
is retained; off-Native crypto remains explicitly unsupported.

The Native SQLite adapter retains the existing SubmissionEpoch body and HMAC
key, commits a monotonic expiry watermark, and refuses changed scope/body/tag,
lost custody and replacement initialization. Shape admission is not authority.
Its fresh-custody initializer remains private until proper format/bootstrap
admission is connected. There is no public CLI key-reset path.

The Run adapter calls `prepare_client_run_start` and
`prepare_client_run_physical_start`. Exact checked request/compiled Run binding,
issuance count, reservation and physical-start claim persist in one SQLite
transaction domain. Missing history is explicitly unresolved. Changed intent,
foreign/shared Run definitions, malformed rows and finite capacity overflow are
refused. Unknown commit/rollback outcomes fence that adapter instead of
authorizing work. This adapter does not accept a Submission, prove an execution
continuation or reconstruct resources. The eventual shared physical connection
must carry transaction-uncertainty fencing across its other services.

## Reuse and remaining connection points

| Path | Current main evidence | Remaining standard CLI work |
| --- | --- | --- |
| Program/SQL preparation | Common frontend/checker; actual Native candidate ingress | Complete diagnostic projection and configured Source context |
| Actual DuckDB Source | Native read-only binding, acquisition/capture and strategy APIs | Configure/admit the operator's actual Source; run the user Program through ordinary dispatch |
| Named Result | Native formal publication Store and current-authorized bounded Result access | Connect the admitted CLI Run and real Source output, then separate-process delivery/recovery |
| Submission/Run | Portable identity/start/cancel Owners; new physical binding/start adapter; shared non-destructive SQLite inspection | Trusted namespace/custody bootstrap, receipt/outcome journal and public operation routing |
| Effect | Native Preview, encrypted capture/continuation/Checkpoint custody; portable Effect Ledger and Checkpoint Owners | Native physical claim/head/history/outcome adapter, resolution/resume transaction, selected fixture apply/reconcile and process restart |
| Distribution | Existing fixed Native binary/artifact/npm wrapping | Fresh artifact from a clean fixed implementation HEAD; outside-repository install and full Local lifecycle acceptance |

`native_publication_output_wbtest.mbt` provides the ordinary publication/access
assembly; its ordinary acquisition is mocked and is not public Source or
separate-process Run recovery evidence. `native_retained_case_probe` uses actual
Source acquisition/ordinary dispatch but an example application rather than the
user Program. Native Salesforce Preview acceptance asserts zero writes; it does
not establish approval/apply/restart. The Native continuation custody record
explicitly retains a live Ledger and does not prove its reconstruction after
process exit.

The next public slice must establish trusted explicit configuration and private
state custody, use the common Submission receipt/identity law, and connect
ordinary Native execution/publication/access. No automatic Connector grant
profile is introduced. Missing state/config/key material cannot imply freshness
or authorize replacement execution.

## Executed limited checks

These checks ran against an uncommitted source candidate based on the fixed main
above, not a fresh release artifact or successful Hosted CI revision.

Commands use the checked-in MoonBit pin and Node 22.23.2. Native SQLite tests
use `/usr/lib/libsqlite3.dylib`, crypto tests use the explicitly selected
`/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib`; each test run has a fresh,
owned SQLite directory.

| Command (via `node scripts/local-checks.mjs`) | Result | Evidence under `_build/` |
| --- | --- | --- |
| `test moon --timeout-seconds 120 -- --target native src/platform_native/signature` | 6/6 | `local-checks/attempts/run-pjUHbR` |
| `test moon --timeout-seconds 120 -- --target native src/platform_native/client_host` before Run adapter | 8/8 | `local-checks/attempts/run-9AwQcY` |
| `test moon --timeout-seconds 240 -- --target native src/platform_native/client_host` | 11/11 before final Run-custody/error refinements | `local-checks/attempts/run-c2CzX4` |
| `test moon --timeout-seconds 240 -- --target native src/platform_native/client_host/run_journal_wbtest.mbt` | 3/3 after those refinements | `local-checks/attempts/run-oLmljI` |
| `test node --timeout-seconds 180 -- scripts/test-native-client.mjs` with explicit debug binary | Existing mTLS, generated wire and Local ingress: 584/584 | `local-checks/attempts/run-S3pXIj` |
| `test moon --timeout-seconds 180 -- --target js src/run_publication_host/client_effect_program_test.mbt src/connectors_builtin_node/client_table_write_publication_wbtest.mbt src/platform_native/signature/signature_unsupported_wbtest.mbt` | 13/13 | `local-checks/attempts/run-fl0FMh` |
| `build moon --timeout-seconds 120 -- --target js src/client_values_host_abi` | Actual consuming ABI compiled; no ABI runtime-test claim | `local-checks/attempts/run-KyHlaH` |

The executed debug CLI binary was
`sha256:d881f01d69847d735e582c4ac1ae918e2119c34b95fb3b0b150b179b442a7d38`.
It predates the new Run adapter and is not relabeled as a final packed artifact.
Local ingress ran from owned scratch outside the repository with an empty PATH.
Its tests reuse the existing Native acceptance script/binary, including the
existing installed-launcher entry, rather than creating another build/job.

A preparation fixture initially failed because its authored environment file
had a trailing newline while its independent CID selected exact canonical bytes.
The fixture was corrected; product input is not trimmed or normalized. The
failure evidence remains `local-checks/attempts/run-fCzk5e`. Initial Run adapter
compilation failures remain `run-6fXOce`; `run-4AQp6C` timed out during Native
compilation before any test database existed. The bounded 240-second invocation
completed; no product timeout or expectation was changed.

Scoped `moon info --target js,wasm,native` checks signature/common Host interface
agreement. The Native-only client Host interface remains generated in the Native
build tree under the existing native-only interface convention. Two unused
private fresh-bootstrap helpers reflect the unfinished bootstrap connection;
warning gates were not weakened.

## Not yet verified or published

No actual Source-to-public-Run CLI acceptance, separate-process CLI lookup/read/
cancel/reconciliation, Native approval/apply/unknown/cleanup acceptance, fresh
packed installation or complete human/JSON/exit-code contract is claimed.
The bounded-read, interruption and response-loss requirements remain obligations for the
public lifecycle unit, not successes inferred from these internal rows.

Hosted CI remains stopped. No npm publication, Cloud operation or merge was
performed. GitHub's API rejected the existing local credentials with HTTP 401;
Draft PR creation and remote workflow-state confirmation are therefore pending.
The workflow/protection/authentication settings were not modified, and no push
was used to trigger CI while that stop could not be confirmed.

## Current-main integration and pending physical regression

Main `0c6538b53f63a3c8a42770092e16035103749e9e` was merged normally as
`90bc8cbcdc8733000c6fcaf183b7d4027d9ca451`. This includes the existing signed
Native resident Effect Resolution admission from #1239, including current
authority checks after the clock callback. That API admits a Resolution; it
does not itself claim dispatch, apply an Effect or prove cleanup. It will be
reused rather than replaced.

The following work is uncommitted on that integration HEAD:

- Local preparation is human-readable by default; `--json` selects its existing
  machine report. Neither presentation claims that a Run was admitted.
- Client custody inspection reuses the existing pinned SQLite/WAL-copy and
  retry-only cleanup owner. Missing files remain physical absence, not proof of
  a fresh Host. Epoch and Run custody are read through their existing bounded
  decoders; missing or inconsistent records are not repaired.
- The new inspection entry bounds the combined DB/WAL bytes before creating
  scratch files, separately from the record-read bound. Its capacity refusal
  is typed, not classified from an error message. Existing Coordinator callers
  retain their former copy behavior and common format checks.
- Epoch and Run adapters share transaction-uncertainty fencing through their
  original SQLite physical handle. Rewrapping the same handle cannot bypass
  the fence. Rollback and checked close remain available for cleanup; neither
  removes the fence. Reopening still requires the original durable custody and
  start facts, and never treats an unknown outcome as non-execution.

The new independent cases cover read-only copies, absence, concurrent source
generation change, semantic refusal plus retryable cleanup, copy-capacity
refusal, lost/corrupt Client custody, and both before-commit failure and
after-commit reply loss across the Epoch/Run adapters. They are not yet claimed
as executed regressions.

Scoped Native `moon check`, shared-package `moon info --target js,wasm,native`,
C `clang -fsyntax-only -Wall -Wextra`, Node test-script syntax and formatting
passed for these working-tree changes. Evidence is in
`_build/local-checks/attempts/run-IbyoIi`, `run-4s2tDN` and `run-YrRK5V`.
The first inspection typecheck failure, `run-YJltAl`, was a test-only misspelling
of `DatabaseClosed`; it was corrected without changing the product error.

The bounded matching-target execution request selects only seven inspection
cases, `src/platform_native/client_host`, the affected Native CLI build and
`scripts/test-native-local-cli.test.mjs`. It was refused before starting by
another owner's shared heavy lock (`run-d3JX6I`; earlier requests
`run-cf84hm` and `run-XF9eHU` were likewise not executed). There is no current
artifact or runtime-success claim for this integration HEAD. The clean
`ab5a23fbb6a1bf5c070f1b0aaf4cd52a2196932a` internal 17-test result remains
historical evidence and is not transferred to the new main merge or edits.

The three earlier implementation commits were published only to the unattached
branch `feat/native-local-cli-ab5a23fbb6a1`; that branch publication is distinct
from a PR event, Hosted CI execution or package publication. This main merge
and the changes above have not been pushed.

Actual acquisition can reuse `open_resident_source_compute` with a checked
single-Source linear Program: its documented boundary is physical acquisition/
Compute ownership, not remote dispatch authority. The caller must already have
durable admission, current Source authority and an exclusive start claim.
`execute_task`, `prepare_result_export` and retryable `close` keep the existing
Native strategy/resource owners. Named Result publication and authorized
delivery remain the separate existing Native services. No alternate engine or
remote Coordinator is required by this physical composition boundary.

Trusted Local configuration adoption remains an explicit undecided bootstrap
boundary in `docs/design/oss-host-authorization.md`. The pending proposal is
operator adoption into private user-owned Host state; project discovery alone
must not install grants or signer keys. Inspection is useful independently of
that decision and does not choose an adoption policy. Source execution,
durable public operations, Effect application/recovery and fresh external
installation are still required for the assignment's completion.

## Original-Run Source connection

The Native Client adapter now connects to the existing Source/Compute owner
through `open_native_client_source_work`. It checks the original compiled Run
binding, persists the common reservation and exclusive physical-start claim,
and rechecks current authority at each durable boundary. A repeated claimed
Run returns `NeedsOriginalReconciliation`, including after SQLite reopen;
there is no constructor replay or replacement Run. Cancellation accepted by
the final authority callback is read again before acquisition. Task readiness,
execution, Result export and failed-close responsibility stay with the existing
physical owners.

The existing Source owner exposes its same structural support predicate so
this connection can refuse unsupported legal graphs before claiming work.
This is the current single-Source linear profile, not a new language rule or
completion of every Native operation. The trusted CLI factory must still
authenticate Submission custody, retain the original selected installation
context, supply current authority and commit public Run outcomes. These are
not delegated to the raw physical adapter or inferred from its close result.

`local_client_source_wbtest.mbt` reuses the existing actual DuckDB fixture and
one unmodified Source/filter/select-to-Compute Program. Its independent result
is `[{"id":3}]`, one non-NULL numeric `id` column. Its declared retention and
execution envelopes are each 512 MiB. It checks the existing reader pin keeps
cleanup pending, then confirmed close returns reservations and held bytes;
closing twice produces only one cleanup completion. Repeat construction cannot
acquire/compute again. Counts refer to acquisition/consumer Owner boundaries,
not a claim that validation and execution use only one physical SQL query.

The test-owned initial issuance row is explicit; no production fresh bootstrap
or Submission receipt is fabricated. This is internal Native execution
connection acceptance, not public CLI ingress/delivery, process restart or
packed acceptance. The actual Source test and three start-guard counterexamples
are added but have not run yet. Scoped Native checks passed in
`run-W0VDk6`, `run-UfVi5s` and `run-s9p5Hy`; the shared support interface was
generated on JS/Wasm/Native without divergence.

The matching-target request is retained as
`/private/tmp/actql-d-native-local-targeted-check.mjs`. It uses the existing
bounded/nonzero wrappers and shared heavy lock, the system SQLite/OpenSSL
libraries, and the read-only borrowed DuckDB 1.5.5-r.4 library matching this
checkout's pinned dependency. The latest request was refused before starting
by G's heavy lock (`run-z6F0b6`). No runtime result has been transferred from a
prior SHA or inferred from the successful typechecks.

## Scoped runtime follow-up

The Source connection also retains the actual acquisition's opaque capture and
checked requirement. `source_publication_observation` uses the existing
captured-relation identity, logical-input issuer and DuckDB Source Evidence
issuer; it does not create a substitute observation. The Client adapter binds
this evidence and the original acquisition interval to its compiled Run using
`issue_client_compiled_task_invocation`. Repeating evidence acquisition keeps
the same invocation identity and does not query the Source. Current authority
is checked before and after issuance; closed captures remain unavailable.
Source Policy is taken from the original checked requirement and is not
supplied as an override. This produces publication ingredients, not a public
index, Result grant or successful Run receipt.

The acquisition/consumer observer is guarded after caller callbacks, including
callbacks that accept cancellation. Cleanup notifications still remain usable
after authority loss or cancellation, with the existing owner retaining any
unrecorded completion. The timestamp callback runs before the final physical
start guard, never between that guard and acquisition.

`run-9kn9jM` passed scoped Native typechecks and actual shared interface
generation on JS/Wasm/Native. `run-73cTTG`, at base
`90bc8cbcdc8733000c6fcaf183b7d4027d9ca451` with these uncommitted source changes,
executed and passed the following matching-target selections:

- Seven shared SQLite inspection/cleanup cases (`focused-test-IJnzWg`).
- All nineteen Native Client Host cases (`focused-test-qw8XfM`), including
  custody, cross-adapter transaction fencing and original-Run start guards.
- One actual DuckDB Source connection acceptance (`focused-test-cJJAi2`),
  including the independent row/schema/column expectation, exact Source
  Policy/authority binding, repeat invocation identity, authority loss,
  closed-capture refusal and confirmed one-time resource cleanup.

The complete gate is **not** a pass: its 240-second aggregate budget expired
eight seconds into the subsequent Native CLI build. The three completed test
commands are independently successful (27 tests); updated binary/CLI ingress
was not executed. A separate build-plus-ingress request was refused before
starting by the shared heavy lock (`run-LnIqCM`). Earlier lock refusals
`run-z6F0b6` and `run-ZVb0CK` remain non-execution evidence. No current fixed-SHA
or packed completion is claimed by these working-tree results.

The libraries were system SQLite, OpenSSL at
`/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib`, and the read-only borrowed
DuckDB 1.5.5-r.4 library matching the pinned Node dependency. The test root is
`/private/tmp/actql-d-local-physical-Pk794S`; the runner and command summaries
above preserve the exact environment/arguments. Public CLI `run`, durable
Submission/bootstrap, Named Result commit/read, separate-process recovery,
Effect execution and external package installation remain unfinished.

## Original Submission custody connection

The next connection preserves the original unchecked `ClientSubmittedIntent`
using the existing common owner and `SubmissionEpoch`/nonce identity. The
Native request journal stores that exact value-preserving canonical intent and
its independent issuance count in one SQLite transaction. It records only
`preparing`: no ready receipt, new Run, dispatch, preparation refusal or retry
permission is manufactured by these methods. Existing Run rows, the original
epoch key and monotonic expiry watermark are rechecked in the same transaction.

Reference-only lookup authenticates the original epoch even after admission
expiry and applies current authority. Missing history remains unresolved;
missing or contradictory custody is refused without repair. Unknown commit or
rollback outcomes fence the physical handle across both epoch and Run
adapters. Read-only store inspection now checks the original-intent custody as
well as the existing epoch and Run custody before any writer may be adopted.
This is still an unshipped Local profile, not a migration or repair mechanism
for a released store format.

`prepare_native_client_submitted_program` connects the retained unchecked input
directly to the existing frontend and ordinary/Effect preparation owner.
Structured input remains the original Program, and AQL input retains text,
format, parameter declarations and supplied values. An opaque handle binds
the resulting preparation to that original intent CID; callers do not provide
replacement lowered JSON. Unicode and line endings are preserved for data,
while operation nonces retain the existing typed identity domain: a
noncanonical nonce is rejected rather than normalized. The finite Native input
profile is explicit; envelope budget exhaustion is separate from input refusal.

These methods do not yet connect the retained intent to an atomic ready Run
receipt or CLI `run`. Trusted configuration adoption, installation custody,
receipt/phase completion, publication/read, Effect operations and separate
process recovery remain follow-up implementation, not acceptance claims.

Matching-target typechecking, SQLite C syntax checking and actual scoped
`moon info` succeeded while this change was uncommitted (`run-XxE6IC` and
`run-L7mZjh`). The scoped Native interface is the real compiler output at
`_build/native/debug/check/platform_native/client_host/client_host.mbti`;
this Native-only package has no canonical JS interface.

The bounded runner `/private/tmp/actql-d-native-original-intent-check.mjs`
executed 28/28 Native Client cases and seven selected shared SQLite
inspection/cleanup cases successfully in `local-checks/attempts/run-CTGTBX`.
Focused records are `focused-test-PgdTNt` and `focused-test-mpJRB1`. The owned
SQLite root is `/private/tmp/actql-d-native-original-intent-gFWBeC`. This is
dirty-tree evidence based on `ca87f2d4aa82b13c2b461bf0b8ef5f369f96e1ad`,
not proof for that historical clean SHA or a new release artifact.

The earlier Native attempt `run-vZtSEc` passed 27/28: the negative fixture
incorrectly expected an AQL text SELECT to be rejected. The existing
`source_frontend` query-script grammar accepts it. The corrected test
independently expects SELECT acceptance and refuses a JSON document submitted
as text, unknown envelope fields and declaration placement on JSON. Neither
the frontend nor a product expectation was weakened. The runner-only missing
Node argument separator (`run-FNpuuJ`, before test execution) and shared-lock
refusals are retained as failed/unexecuted evidence, not product successes.

No public CLI run, release artifact, packed acceptance or Hosted CI result is
claimed by this limited Native journal/preparation regression.

## Original Submission-to-Run atomic acceptance

Main `8a54cee9230958e1749fc74abd90610393d9a338` was merged normally as
`cb1c524ce2fe309b27afc74bc88b470e017c2996`, with no conflicts. Its other parent
is `44206b94f5975a0412763ce524217d6963cf93bd`. Existing custody, evidence and
history were retained. This integration includes the Native Site Effect Ledger
storage seam; that Site/dispatch-bound seam is not an implemented Local Effect
send permit or CLI approval path.

`accept_submitted_run` now connects an already retained original intent to its
opaque ordinary preparation, exact compiled owner and owner-issued Run. It
uses the existing request journal transaction and shared submitted-intent
transition rule. The ready acceptance fact and new Run binding/count commit
together. Repeated acceptance retrieves the same Run; a different input,
preparation owner, reference, authority scope or Run definition is refused.
Missing original intent or capacity refusal cannot issue a Run.

The ready record retains the original request identity, Run definition CID and
immutable admission revision. This revision is exact decimal Int64 text under
the existing decoder, not a floating-point JSON number or a current control
revision. Later reservation/control updates do not replace the admission fact.
Read-only custody inspection also verifies this recorded relationship against
the actual Run row. The former preparing record encoding is unchanged.

Commit uncertainty fences the original physical handle. On reopening, a failed
pre-commit transaction retains preparing only, whereas a committed transaction
with a lost reply retains the original ready Run. Reference-only lookup neither
accepts, reserves nor starts work. Neither outcome permits automatic resend.
Corrupt custody is refused and preserved rather than repaired.

This connection currently accepts ordinary computations. Effect preparation is
explicitly `UnsupportedPreparation`; it does not fall back to an ordinary Owner.
Admission itself is not a physical-start permit, successful Run, public receipt
or persisted execution continuation. The trusted Host still has to retain the
original selected installation/context and apply current authority. Public CLI
bootstrap/run, lifecycle publication/read, approval and packed installation
remain unfinished.

Scoped Native typechecking, including the CLI consumer, passed in
`local-checks/attempts/run-FxFSBf`. The first check's test-helper missing error
signature (`run-W2vGmn`) was corrected. The initial actual Native run
(`run-FlxH6D`) failed reading the new admission revision: the writer emitted a
JSON number but the existing exact Int64 decoder requires decimal text. The
writer was corrected without relaxing admission or decoder checks. Independent
cases now include zero, a revision above `2^53`, Int64 maximum, and refusal of
numeric, negative, noncanonical or overflowing encodings.

The bounded runner `/private/tmp/actql-d-native-original-intent-check.mjs`
passed all 34 Native Client Host cases and seven selected shared SQLite cases
in `run-4uotsX`, with focused records `focused-test-oTc7WQ` and
`focused-test-PlAdyL`. It used system SQLite, the configured OpenSSL library
and owned fixture root `/private/tmp/actql-d-native-original-intent-Cko4Sl`.
This is working-tree evidence based on `cb1c524ce2fe309b27afc74bc88b470e017c2996`,
not a clean-SHA or fresh release artifact claim. Shared-lock refusal
`run-oEr5dg` remains unexecuted. Historical clean-SHA and debug binary evidence
are not transferred to this new integration.

## Source Result publication and retained delivery connection

The next connection starts from the original retained Native Source/Compute
owner. Actual Root Result outputs are converted in checked Result order and
passed to the existing captured-run publication owner. Callers cannot replace
the original Run, checked plan, observed logical input or Source Data Policy.
Effect Runs and runs with INFER evidence requirements are not published by
silently omitting their obligations from an Effect-free receipt.

The publication service installed for this work requires both current Host
publication authorization and the original Run/start/cancellation guard. It
checks the guard again after the authorization callback. This connection does
not issue a read grant or project a successful Run. The final public lifecycle
adapter still needs the common cancellation/publication commitment boundary;
these separate journal and Store calls are not claimed to be one transaction.

The actual DuckDB fixture retains its independent row `{"id":3}`, non-null
number schema, `id` field order and 512 MiB execution envelope. It adds exact
Run/plan/input/Policy substitution refusals, callback-time authorization loss,
private preparation before publication, authorization checks at commitment,
and formal chunk confirmation plus a durable delivery receipt. JSONL bytes are
independently expected to be `{"id":3}\n`, with nine confirmed bytes.

Temporary Compute export pins delay cleanup. Once released, the original
Source/Compute reservations return to zero and cleanup occurs once. Named
Result retention remains separately reserved. Closing/reopening the existing
Store allows a new delivery attempt without Source acquisition or Compute
execution. This is an internal Native connection fixture with a test-Host read
grant, not CLI ingress, public current read authorization, or proof that both
Host and execution processes stopped and recovered.

Scoped Native caller typechecking and actual shared JS/Wasm/Native interface
generation passed in `run-R7qz5p`. Shared heavy-lock refusals `run-cthfSJ`,
`run-96ShHR`, `run-QTTkUa` and `run-3kmlLV` ran no tests.

At fixed SHA `e98e258a78241c6a62d29970fb77bff3159fb87c`, `run-PBaRvN`
passed 34 Native Client Host and seven shared SQLite cases, then refused the
actual Source Result delivery. The new fixture had passed contract parsing's
depth 100 into the durable row-framing owner, whose admitted maximum is 64.
The diagnostic-only follow-up `run-zA0Oe4` reported the typed
`DurableRowFrameInvalidLimits` in its one failed Source case. The fixture now
uses a separate finite delivery depth of 16; no Owner check, expected Result,
row/byte limit or execution capacity was relaxed. Both failed logs and original
fixture stores are retained. The typed delivery refusal is included in future
test failure messages instead of an uninformative unwrap panic.

Final clean-SHA runtime verification remains to be recorded separately. No
release artifact, external installation, packed acceptance or Hosted CI success
is asserted by this internal connection record.

The clean follow-up `run-j05Me2` at
`a2b79956309952d54c9e4bb2e64e284755d11598` again passed the 34 Client and
seven SQLite cases. Its actual Source case reached a confirmed nine-byte
delivery, then the new fixture incorrectly queried the Store with the formal
attempt CID instead of the original caller attempt ID. The existing Native
Store lookup contract uses the latter. The fixture now uses that immutable ID
and independently refuses the CID as a replacement key. The first failed Store
and its durable receipt are retained; no payload reopen, grant reconsumption,
Owner change or expectation replacement resolves this fixture mistake.

## Original Native Checkpoint transaction connection

Main `8d187fd2368c7d2d85931592af95d4f79b1eb543` was merged normally in
`c02255c192946d4d5424e9144ab5bdb1ee8ec082`. The sole generated journal API
conflict was resolved by actual `moon info`; existing history declarations
were preserved. Native Client and CLI caller typechecking passed.

The original Client Run row now holds the Store-confirmed Checkpoint, checked
Result declarations, bound authorization/environment identities, common Run
projection, unresolved Effect names, verified Resolution and common resume
identity. Checkpoint closure, Run revision and resume identity commit in one
existing SQLite transaction. The common Checkpoint Owner decides closure,
duplicates, conflicts, status transitions and unknown-Effect refusal. Current
Native Host keys and reviewer authentication are independently checked before
the write transaction; callbacks cannot overwrite an intervening revision.
An open Checkpoint's current deadline is checked at commitment, independently
of historical verification time. A duplicate still identifies its original
durable answer after the deadline. No physical send or cleanup proof is issued.

This is private, not-yet-shipped Client journal material. The decoder refuses
missing/new malformed custody instead of repairing old rows or inferring a
fresh continuation. The existing 131072-byte Run-row limit, actual SQLite
record bound and 512 MiB execution envelope remain unchanged. Additional
Checkpoint material must fit those limits; no replay fallback is installed.

The signing fixture compiles original references, then independently signs the
existing protocol with ephemeral Node Ed25519 keys. It never produces expected
Run statuses or rows. Native verifies actual signatures through pinned OpenSSL.
The transaction fixture uses an explicit durable Checkpoint artifact attached
to a Values Run; it is not proof of Native Effect preview/write acceptance.
Full/selected Native Client wrapper invocations provision these signatures;
unrelated selected packages do not invoke the producer.

The dirty diagnostic `run-uia7rg` passed 39 Native Client cases, then failed the
Source caller because the D runner omitted `ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT`.
That failed log and scratch are retained. The runner now supplies the existing
owned fixture root; neither product expectations nor limits changed. Additional
revision/authority races require fixed-SHA verification recorded separately.
Eleven Node wrapper regressions passed in `run-l1PjrQ`; actual shared API
generation and Native caller compilation passed in `run-LJwIcI`/`run-qZggab`.

The remaining Direct Local connection is a durable resume claim/generation/
lease/fence plus physical storage for entries issued by the existing Effect
Ledger Owner. Main's new Native Resident row write/recovery is real, but binds
an actual retained consumer, Site and DispatchRequest. Those identities must
not be fabricated to open a Direct Local executor. Provider writes, CLI ingress,
separate-process Run recovery, packed installation and Hosted CI remain
unverified for this component. This does not complete the Local CLI goal.

## Original Native resume claim and fence connection

Main `35d30ac93ed89ba44254bc9d4dadd48c00687a89` was merged normally in
`5a3c39771993ca0971401ba3802f94bbe381f828`; existing declarations and
generated contracts were retained.

Approval now creates the common pending `ResumeIntentView` in the same original
Run transaction as the Resolution and Run projection. Native stores its exact
generation, claimant and lease expiry without floating-point conversion.
Restore refuses missing, inconsistent or noncanonical custody; it neither
repairs old private rows nor grants a replacement continuation.

`claim_effect_resume` readmits the retained original signed Resolution against
current installed Host keys and reviewer authorization. After verification and
clock callbacks, it checks the original Run revision before committing the
common `decide_effect_resume_claim` result. Busy claims do not mutate the Run.
Expiry permits a higher-generation claim, not repeat dispatch of an Effect row.
Changed bindings retain a sticky observation-only settlement claim. Accepted
cancellation also fences sending while preserving observation responsibility;
this connection does not declare the Run Cancelled or cleanup complete.

The opaque process-local claim is bound to the exact original journal, request,
Checkpoint, Resolution and common intent. `effect_resume_fence` uses the common
fence predicate, current authorization and the retained cancellation fact.
It is a diagnostic observation, not permission cached across an await. The
physical Effect adapter must use the locked predicate together with the existing
Effect Ledger Owner's row claim in one transaction before sending.

Eight added Native cases cover expiry/reopen/takeover, original approval/current
authority, common invalid-material refusals, sticky settlement, cancellation,
intervening revisions, precommit versus commit-reply loss and malformed custody.
Actual Native typechecking, scoped interface generation and the existing CLI
consumer passed in `run-f6He3l` and `run-OYW4F3`; an earlier test compilation
failure is retained in `run-0DhzFp`. Fixed-SHA runtime results and actual debug
executable digests are recorded separately, not inferred from typechecking.

Provider dispatch/response custody, actual Effect preview/write/reconcile,
public CLI original-operation routing and separate-process acceptance remain
unfinished. The prior actual Source fixture is a regression caller, not a new
claim of public packed CLI completion. No Hosted CI or package publication was
started.

## Original Native Effect row custody connection

Main `3900058027b0095b6851161aa4e1c65aa1ef754f` was merged normally in
`2eed244d60440262c323f9f7ffccf0acb9952f65`. Existing source/history material
was preserved; the main delta is the audited Append cleanup regression.

The original Client Checkpoint now retains exact entries issued by the common
Effect Ledger Owner. `record_effect_row_dispatch` checks the current original
resume fence, original logical scope, checked Preview identity and immutable
basis, then commits the prepared/dispatching chain with the original Run
revision. Common recovery decisions return an existing possibly-sent/terminal
entry without another dispatch claim. An expired claimant, cancellation or
settlement-only resume cannot issue a new dispatch. Unknown commit outcomes
return no handle and fence the original journal.

An independent physical custody row binds the original Checkpoint, Run
definition, request and ordered entry identities. Its CAS revision equals the
number of non-prepared entries. The original Run row and witness advance in
the same existing SQLite transaction. Startup and each mutation compare both;
partial chain loss, missing/replaced witness and inconsistent witness revision
are refused rather than repaired or treated as an unsent row. This is custody
for the existing common Ledger, not a new Ledger or Recovery Owner.

The opaque original dispatch handle can retain an unknown observation after
cancellation/lease expiry. Repeated observation is idempotent; it cannot mark
success, overwrite a terminal receipt or dispatch again. Current-authorized
lookup never opens a Provider. The existing Run-row/SQLite byte limits remain
unchanged; the private history is bounded to 128 entries and common chain
validation. Capacity refusal rolls back the Run and witness together.

Nine added Native cases cover duplicate/takeover refusal, durable unknown,
authorization/fence/Preview/scope checks, commit loss, chain corruption,
independent custody loss/rewrite and finite capacity refusal. Native caller
typechecking/formatting and actual interface generation passed in `run-l7h0P5`;
the earlier readonly-basis fixture compilation failure remains `run-hBM3uX`.
Fixed-SHA Native runtime evidence is recorded separately.

This is metadata custody, not proof of Provider I/O. The actual Native write
owner must still bind the checked request and Preview, independently revalidate
target/credential/current cancellation, reserve response/receipt capture before
copy/send and confirm the exact durable dispatch immediately before I/O. Receipt
classification, common Effect Set completion, cleanup retries, public CLI
operations, separate-process restart and packed installation remain unfinished.
No Site or transport dispatch identity is fabricated for Direct Local execution.
