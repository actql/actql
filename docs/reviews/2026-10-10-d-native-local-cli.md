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
| Submission/Run | Portable identity/start/cancel Owners; new physical binding/start adapter | Fresh-format inspection before writer open, namespace/custody bootstrap, receipt/outcome journal and public operation routing |
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
