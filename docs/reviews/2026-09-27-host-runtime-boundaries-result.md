# Host runtime boundary result

Terminology note (2026-09-30): this historical review uses “ABI” for several
MoonBit-to-JS connections. In current terms, generated function calls are
internal JS bridges, Host invocation contracts are Host APIs, and persisted or
transmitted records are wire formats. The original review wording is retained
to preserve its contemporary record; native FFI ABI references remain literal.

## Scope

This change keeps the existing ActQL 0.1 wire and CID contracts. It connects
the standard Node and installed HTTP Hosts to the common Run observation
rules, then narrows the mutable dispatch and ABI boundaries. It does not add
Effectful Program execution, a new scheduler, or a new cleanup policy.

## Owner and boundary map

| Owner | ABI or retained boundary | Host wrapper and type |
| --- | --- | --- |
| `run_publication` Run-state issuer | `client_program_issue_controlled_unpublished_run_state` carries physical-start uncertainty and confirmed terminal outcome | The standalone `issueUnpublishedRunStateWire` accepts a named observation; the installed Host supplies durable journal facts and live-owner observation directly through the positional ABI (remaining adapter work below) |
| Common Run-start and cancellation control | `client-request-journal` serializes claims and projects validated retained Run facts | `client-dispatch-owner` owns physical dispatch, cancellation delivery, stop observation, and cleanup; `embedded-local` connects the public ports |
| `run_publication` delivery control | Generated Node ABI returns bounded numeric actions | `publicationAction` rejects unknown codes and returns named actions to result access and delivery |
| `run_publication` contract admission | Runtime handles remain checked against their issuing owner | `DeliveryContractView<Kind>` distinguishes roles at the TypeScript boundary; runtime ownership checks remain in place |
| Checkpoint and acquisition owners | The request journal retains exact preparation and source binding | An independent acquisition fixture pins its expected identity; packed restart tests retain the original claim and never restart unknown work |

The physical owner does not decide whether to retry an ActQL Run. A failed
cleanup remains owned for a later cleanup attempt. A persisted terminal outcome
is distinct from a committed publication and from currently available result
material. A reserved physical start without confirmed settlement projects to
`needs_reconciliation` after restart, without re-executing the source.

Rollback failure preserves the initiating error as the primary cause and the
rollback error as secondary evidence. A failed journal write is not reported
as a durable transition.

The installed dispatch owner receives the captured execution before fallible
publication, independently of the thrown error. Wrapping an error cannot lose
that owner; close failure remains retryable without repeating Compute.
Both HTTP and in-process ingress report authentication/authorization faults
through the existing private Host observer. Ordinary denial emits no fault;
public responses contain neither the cause nor request details. A failing
diagnostic observer never permits access.

## Completion evidence map

| Requirement | Executable evidence |
| --- | --- |
| Durable terminal outcome versus unknown start | `client-request-journal.test.mjs` records confirmed failure across reopen and rejects another physical start; `remote-checkpoint-host.test.mjs` attaches after lost execution observation without dispatching again |
| Cancellation and publication precedence | Installed HTTP Checkpoint C5 retains an unconfirmed stop; the late-observation-failure test preserves the committed Result |
| Primary and secondary errors | Real SQLite acceptance and Run-start rollback fault tests retain both causes; dispatch-owner tests retain cleanup after failure |
| Explicit cleanup handoff | `client-dispatch-owner.test.mjs` wraps the publication error and retries failed close without Compute; the acquired Program test checks the real execution handoff |
| Authentication fault versus denial | `client-http.test.mjs` exercises both ingress ports, faulting auth callbacks and a faulting observer, with unchanged public denial |
| Validated journal projection | All definition lookup variants reject corrupt retained Result inventory; missing terminal evidence remains unknown |
| Typed ABI and runtime ownership | `run-host-core` negative TypeScript fixture rejects forged and wrong-role handles; runtime tests reject foreign owners and invalid observations; publication action tests reject unknown codes |
| Independent acquisition and deadline fixtures | The query-amount fixture has its own pinned identity; SQLite Checkpoint tests inject `clock.ms`, including the exact approval expiry instant, while packed process/network coverage remains |

The installed Host treats a failed control projection as `InvalidRunControl`,
not as a missing Run. The controlled unpublished-state bridge preserves typed
issuance failure instead of returning absence. Other unrelated optional bridge
APIs are outside this refactor.

## Validation

The original implementation was tested at
`9cc15b9d8c86e61b19d1cec37e4dfc62281b6199`. The restacked source tree
at `61da9c2b2ad94fec430e04fa8164aed34412510d` is identical. The Workers
allowlist fix and its direct verification are at
`b4cb86508cd2018a9d69ea7b28e99c975ee2cd03`.

- `check:distribution-client`: passed. Node tests: 159/159; packed Node and
  browser Client smoke, packed Checkpoint acceptance, and native Client mTLS
  all passed.
- `local-checks.mjs run host`: passed, including retained storage, publication,
  remote dispatch, Checkpoint journal, packed Run Host, and packed Local assets.
- `local-checks.mjs run lint`: passed, including MoonBit formatting and public
  interface checks.
- `check:run-host-core`: passed, including the TypeScript negative fixture and
  packed package.
- `check:publication-runtime`: passed, 16/16.
- `test:docs`: passed, 40/40.
- `local-checks.mjs run workers`: passed after the explicit pure publication
  action translator was added to both Workers module sets, 24/24 workerd
  tests.
- Real SQLite and installed HTTP Host regression tests cover retained
  observations, restart uncertainty, cancellation, rollback causes, and
  acquisition binding. No Salesforce or external provider was exercised.

The earlier final stack passed Linux CI at these exact SHAs:

- H1 `42409c6ad782fb2b7ead4ff1ed865046477e1942`:
  [CI](https://github.com/actql/actql/actions/runs/36300566770).
- H2 `c3d63d26d163517a09078db65f78a35521f736b0`:
  [CI](https://github.com/actql/actql/actions/runs/36300650261).
- H3 `52428424a8c252a1811abf2cb77b5786a51c45a8`:
  [CI](https://github.com/actql/actql/actions/runs/36301076753).

The completion audit added explicit execution handoff and private auth fault
observations. At `0d83eca3a`, `check:distribution-client` passed 163 tests,
packed Node/browser and Checkpoint acceptance, and native Client mTLS. The
merged tree at `d543b352d2051aa9c03330313309cb712af0b6b7` is identical.
The focused owner/Program tests passed 26/26 and ingress tests passed 14/14.
The Host gate also passed on the merged implementation, including retained
storage, remote runtime, Checkpoint, packed Run Host and packed Local assets.
The updated PR heads require their own CI results; the older runs above do not
prove those heads. Each PR records its exact validation SHA and CI link.
Performance remeasurement and external provider tests are not claimed.

## Compatibility and follow-up

Public wire versions and CID preimages are unchanged. The run-host-core
TypeScript surface now requires named observation objects and branded delivery
views; internal callers and generated package assets were updated together.
The broader Connector SDK type surface is outside this change.

## Remaining-work audit, 2026-09-30

Baseline: main `b1f6dcd6fe29f13b2f98102df02e710b98d2acd1`, including
#66 and #67. #68's small shared-JS extraction is separate and does not close
this work order. The earlier completion evidence remains evidence for its
specific boundaries, not for every later caller.

| Unit | Implemented; do not repeat | Remaining bounded work |
| --- | --- | --- |
| H1 | Durable Run unknown/terminal observations, publication precedence, primary plus rollback causes, private authorization diagnostics | This follow-up closes request-journal initialization and post-schema prepare cleanup. `clientRunControlObservation` still erases the owner's issuance error as absence; retain that cause in a separate ABI follow-up. |
| H2 | Dispatch owner, explicit publication execution handoff, shared retained journal facts, independent shutdown/initialization cleanup | Acquisition recovery custody still relies on the outer `AcquisitionOpenError`; an ordinary cause wrapper hides its recovery owner. Close that explicit handoff separately. Installed Run observation/cancellation composition can then be narrowed without inventing another state machine. |
| H3 | Branded delivery views and runtime ownership checks, four named delivery action families, independent acquisition fixture, controlled expiry clock | Apply named observation arguments to the installed Host's actual calls; distinguish the targeted publication contract roles; translate remaining publication lifecycle actions at the ABI boundary. Do not redo delivery branding or redesign Connector SDK. |

### Request-journal initialization follow-up

The request journal previously closed directly in its schema catch, losing
the initiating error if close also failed. Statement preparation was outside
that catch and could leave the database open without returning an owner.

The single initialization boundary now extends through statement preparation
and journal construction. It uses the existing
`throwSqliteInitializationFailure`; no new cleanup framework or transaction
semantics are introduced. Successful cleanup rethrows the original failure.
Failed cleanup preserves both causes and the existing retry/status owner.
The installed Host's existing initialization wrapper retains that owner.

`installed-host-cleanup.test.mjs` injects schema and prepare faults into real
SQLite connections, with and without close failure. It also enters through
`openInstalledRemoteHttpHost`, fails both initial close attempts, and recovers
through the returned Host error's cleanup handle. Counters require schema
and prepare to run once, retry to call only close, repeated completed retry
to do nothing, and the failed database to be physically closed. Reopening
the existing journal/Host succeeds without repairing its format.

Run/Effect execution, wire, CID inputs, stored format, and the existing
non-destructive format inspection are unchanged. Outbound implementation and
cross-team contract review remain outside this follow-up. Exact verification
SHA and CI results are recorded in the independent PR, not inferred from the
older runs above.
