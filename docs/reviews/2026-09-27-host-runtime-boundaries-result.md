# Host runtime boundary result

## Scope

This change keeps the existing ActQL 0.1 wire and CID contracts. It connects
the standard Node and installed HTTP Hosts to the common Run observation
rules, then narrows the mutable dispatch and ABI boundaries. It does not add
Effectful Program execution, a new scheduler, or a new cleanup policy.

## Owner and boundary map

| Owner | ABI or retained boundary | Host wrapper and type |
| --- | --- | --- |
| `run_publication` Run-state issuer | `client_program_issue_controlled_unpublished_run_state` carries physical-start uncertainty and confirmed terminal outcome | `issueUnpublishedRunStateWire` accepts a named observation; the installed Host supplies durable journal facts and live-owner observation |
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
