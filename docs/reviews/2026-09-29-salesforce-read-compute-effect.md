# Salesforce Read→Compute→Effect acceptance

This records the Salesforce acceptance of one Program that acquires records
from the installed Salesforce source, computes locally, previews an update
of the same records, waits for approval across Host restarts, writes, and
publishes its Named Result, through the public Client.

The common path that runs an Effect from an acquisition belongs to the common
Host, Checkpoint and public entries. It is not on main yet. This unit
prepares the Salesforce side and its acceptance, and verifies that path once
it lands. It does not copy or reimplement common code.

## Status

**Not connected yet.** On main, the Program is refused before any Run with
`ClientProgramUnsupported`:
- `src/run_publication_host/client_effect_compilation.mbt:72-90` compiles
  Effects only for a source-free Unit that starts with Values.
- Every Read→Compute→Effect test fails with `ReadComputeEffectNotConnected`.
  That marks the path as not connected. It is not a Salesforce defect, and
  it is never counted as passing.

Passing today:
- The stateful mock org's self-test.
- Every existing Salesforce test, with the fixture extensions in place.

## The Program and independent expectations

- **Acquire:** read `Test_Record__c` through the records view (scan, filter
  `Name <> 'record-2'`, select `Id`, `External_Key__c`).
- **Compute:** derive `next_name = concat(External_Key__c, '-processed')`
  and select `Id`, `next_name`.
- **Effect:** update `Name` of the same records by `Id` (halt by default;
  `continue` in the independent-rows case).

Expected values are written by hand in `read-compute-effect.fixture.mjs`:
- **Targets:** records 1 and 3; record 2 is filtered out and never written.
- **Bodies:** `{"Name":"key-1-processed"}` and `{"Name":"key-3-processed"}`.
- **Named Result `updates`:** the two rows above.
- **The org afterwards:** the two targets renamed, record 2 unchanged.

## Cases

| Case | Entry | Expected |
|---|---|---|
| Success: acquire, filter/derive, Preview, held, restart, approve, restart and resume, 2 writes, Named Result, restart with no further write | Remote HTTP, Embedded, tarball | Exactly the two bodies, once each. No Source re-acquisition after the restart. Named Result and final org state as above. |
| Target changed after acquisition, before Preview | Remote HTTP | The Preview observes the target as it then is. The existing guard compares at send, so the Set is written. |
| Target changed after Preview, before send | Remote HTTP, Embedded, tarball | Refused before any write (stale Preview); the Run fails. A race after the pre-send check is not claimed to write nothing. |
| Approval expired | Remote HTTP | No write. Expiry uses the Host's `checkpointTtlMs` with a bounded wait past `expiresAt`, as the read approval test does. |
| Commit permission revoked after approval (a): the account configuration now denies | Remote HTTP | No write. This checks refusal on a configuration change only. |
| Commit permission revoked after approval (b): same installation and configuration, the org no longer lets the user update `Name` | Remote HTTP | No write; the pre-send recheck of the target field refuses. The Host-side lapse of a current decision is a question for the common side. |
| Reply lost after the org applied the second write | Remote HTTP | That row stays unknown and is never resent. The Run is `needs_reconciliation`. The org shows both rows applied, and a restart sends nothing. |
| Halt: the second of three rows is rejected | Remote HTTP | First applied, second failed, third never sent. The Run fails. |
| Continue: the second of three rows is rejected | Remote HTTP | Every row sent once; two applied, one failed; none resent. The Run fails. |

## Findings for the Salesforce side

- **Effect factory input.**
  - The factory takes its rows only from `facts.openComputation()`, which the
    Host wires today to the source-free computation
    (`installed-effect-site.mjs:208`, `embedded-local.mjs:634-642`).
  - The factory stays as it is: it should consume what `openComputation()`
    returns for an acquisition-based Run.
  - Ownership, closing and the restore contract of that computation are
    questions for the common side.
- **Collections.**
  - The installed Effect never takes the sObject Collections route:
    `issueSalesforceEffectCapability` is called without `collection`, which
    defaults to serial rows.
  - So `continue` sends single-record writes one by one. Each row is still
    settled independently.
  - Collections partial results are covered by the provider tests
    (`effect-run.integration`), not through the installed Effect.
- **Source capture.**
  - It lives only in its process and is closed after compute
    (`client-dispatch-owner.mjs`).
  - An Effect after a restart must write from the computed result made
    durable before approval, never re-acquired. The acceptance tests count
    Source queries apart from target check reads.

## Conditions shared with the common side

- After a restart:
  - no Source re-acquisition or recomputation;
  - the write input is the durable input bound to the approved set, never
    rebuilt from the Preview display alone;
  - a missing, corrupt or mismatched durable input is refused before sending.
- The durability point, its ownership and recovery are the common side's.

## Real org

Not run for this unit yet. It runs after the mock and packed checks, only
within the recorded permission scope and budget.
- Scope: the success path and one pre-send refusal (target changed after
  Preview).
- Fields: `Name` and `External_Key__c` of the dedicated object only.
  - `Amount__c` is Number(16,2), which is not declared.
- Records: only records created and recorded by the run, which then deletes
  them.

The estimate separates normal processing, verification reads, planned
cleanup and emergency cleanup headroom. It is rechecked against the latest
usage record and the org's API remaining just before the run.

Mock only (not run on the real org):
- unknown result after a lost reply;
- partial success (halt and continue);
- approval expiry;
- revoked commit permission.

## Tests

- `adapters/connectors/salesforce/test/read-compute-effect.acceptance.test.mjs`:
  every case on Remote HTTP, and the Embedded success and stale-Preview cases
  (each Embedded step in its own process, so each is a restart). It runs in
  `npm run check:salesforce-site`.
- `scripts/test-packed-salesforce-source.mjs`: the success and stale-Preview
  cases from the installed tarballs, with no checkout or MoonBit.
- `salesforce-effect-site.fixture.mjs` gains a stateful org, off by default:
  - applied writes change the records;
  - a missing target is 404;
  - replies can be lost after the update was applied;
  - per-row Collections application and replies;
  - a query hook;
  - direct record changes.
