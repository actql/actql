# Bounded Score and Normalize record emission

## Completion unit

Base: `feb175d059b17b0176106564f05f9157009a4db2` (#585).
Kernel implementation: `6f3e54afa7bdbad3541edb59345358cd25fe7546`.
The publication/evidence commit adds the ordinary Host boundary and strengthens
the independent Text-key work assertion. Its final submitted SHA and executed
checks are recorded in the PR; this document does not claim full CI success.
This branch depends on #585, not on its separate Ranking child #591.

Score and Normalize previously called synchronous `append_record()` after
their bounded numerical computation. Vector wire emission and unused nested
columns could therefore drain in one kernel poll. They now start and advance
the existing record append owner. One append advance consumes one control
unit; logical record construction work remains independently enforced by the
same builder. A pending record cannot grant completion or publication.

Component/identity names use borrowed reference fragments with at most 64
UTF-16 pairs per poll, without full qualification concatenation. Score typed
identity validation and stable ties use the existing bounded key comparison.
No numerical algorithm, scheduler, ledger, wire, CID or public API is added.

The new two-row Text-key fixture also exposed an exhausted merge-side read:
after deciding a tie, Score remained in its tie phase. Selection now returns
to the merge owner's existing exhaustion check. Independent expected IDs are
the 513-unit prefix followed by `a`, then `b`, with scores exactly one.

## Independent boundaries

| Fixture | Control work | Workspace | Logical construction work |
| --- | ---: | ---: | ---: |
| Normalize, two fields / two dimensions | 35 / 34 | 67 / 66 | Existing wire discipline |
| Score, one record / two dimensions | 50 / 49 | 79 / 78 | Existing wire discipline |
| Normalize, three fields / 256 dimensions | 804 / 803 | 327 / 326 | 272 / 271 |
| Score, three input fields / 256 dimensions | 821 / 820 | 338 / 337 | 276 / 275 |

The large fixtures enumerate kernel and append phases in the test, rather than
deriving budgets from successful measurements. Each runs quanta 1, 7 and 256.
Normalize's output is 256 copies of the exact binary value 0.0625. Score's dot
product is exactly 256. Work refusals distinguish kernel control work from the
typed shared storage construction-work failure. Workspace one-short rejects
before record temporaries. The two-record long Text key additionally fixes
1695 control units from separately enumerated validation, merge, copy and
wire phases, independent of quantum.
The common Text cursor completes in its last code-unit poll, without a
separate end poll. The rejected 1697 assertion counted two such nonexistent
polls; its failed evidence is preserved in `run-DU6eqp` /
`focused-test-thR7Oy`, rather than treating the measured total as an oracle.

Normalize reserves current retained rows, next retained row, field/vector
temporaries, the shared append workspace and two cursor slots before reads.
Score reserves ordering/output storage, the shared append workspace and nine
fixed slots: name position, append handle, key handle and six borrowed key
comparison slots. These are logical workspace reservations, not a claim of
whole-Run physical resident-byte accounting.

## Stop and publication evidence

`vector_record_steps_wbtest.mbt` exercises long component/identity names,
typed Text validation/ties, output Vector emission and an unused 128-item
Array. Before confirmed stop, cleanup refuses with `NotStopped`; source and
provisional output custody remain live. After stop, the existing Session
cleans the shared append before its output builder, clears cursors, leaves
the input valid and releases the output reservation exactly once.

`public-vector-record-retention.test.mjs` uses a normal JSON Program, the
installed standard Host and a real retained Store. A Values stage supplies
one typed Vector and an unused 129-item Array. A fused stage converts, computes
Score or Normalize and applies the formal Vectors bridge; two later tasks
consume the retained result. The three explicit public names are checked
independently against literal expected content and order. Repeated requests
perform no additional dispatch or advances.

An awaited observation barrier, not a sleep, selects control work 768 after
the input bridge. Independent kernel/append phase bounds place this within
provisional record emission. Cancellation is requested while physical stop is
unconfirmed; retained snapshots and execution counts cannot change before
release. The resumed driver confirms stop without publishing any named result,
does not dispatch again and finally removes Carrier snapshots.

The route gate requires both operations' executable limits, record stop,
role stop, unused-column stop and public Store evidence, plus Score's typed
key fixture. It rejects missing evidence, a foreign suite, a lost actual suite
import and production regression to synchronous append. Registered JS/Wasm/
Native fixtures are not evidence that all three targets ran locally.

## Executed candidate evidence

- JS kernel/caller selection: 28/28; `run-mv4B8m` and
  `focused-test-SF7CKe`. The earlier Text fixture failure is retained in
  `run-pOMaGD` / `focused-test-hkQF6F`; unrelated fixture compilation attempts
  are not passing evidence.
- Ordinary public Host: 2/2; `run-wkIUhD` / `focused-test-TQCvX3`.
  Earlier connection-option fixture failures are retained, not overwritten.
- Required evidence negative checks: 3/3; `run-NZU64j` /
  `focused-test-AJk3i6`.
- Selected `local_carrier_vectors_wbtest.mbt` caller names `*Vectors*`:
  22/22; `run-6eYrhk` / `focused-test-bUnBfk`. That filter did not execute
  the new record test file; its compilation alone is not execution evidence.
- Selected local VecA API generation compiled JS/Wasm/Native without an
  interface change. Only `local-node` and `run-host-core` runtime packages
  were regenerated from the changed sources; payloads remain ignored.

Commands use `scripts/local-checks.mjs test moon --timeout-seconds 120 --
--target js <selected files>` or `test node --timeout-seconds 90 --
<selected files>`, with explicit nonzero-test guards. Source-file API generation
is `moon info --target js,wasm,native src/local_veca`. Final clean-SHA commands
and results belong to the PR validation section.

## Remaining work

This closes these two execution-lane record/name/key scans, not all Local
retention. Nearest's separate scans/emission, preparation and schema lookup,
JSON identifier normalization, legacy drains, final buffer assembly, aggregate
intermediate bytes and whole-Run physical accounting remain separately tracked.
No fresh full-target execution, packed external installation, native Host
cancellation, Store fault campaign, proof or performance campaign is claimed.
Prior shared-owner failure evidence is retained; these selected tests are not
new evidence for every Store failure/restart combination.
