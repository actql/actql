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

The final documentation commit, unrelated local jobs, and Linux CI are not
covered by these local checks. The first H3 CI run identified the missing
Workers module allowance; it must be rerun at the pushed fix SHA. The PR must
distinguish this pending CI result from the checks above.

## Compatibility and follow-up

Public wire versions and CID preimages are unchanged. The run-host-core
TypeScript surface now requires named observation objects and branded delivery
views; internal callers and generated package assets were updated together.
The broader Connector SDK type surface is outside this change.
