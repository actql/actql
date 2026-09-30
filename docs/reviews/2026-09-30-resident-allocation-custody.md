# Resident Site allocation custody — PR #72

Implementation fix: `f0448758e`. Integrated main: `327fe8a08` (#92).
The final source SHA and CI results are recorded in the PR's Validation section.

## Ownership and recovery

The publication Store remains the only payload/capacity owner. The Site keeps
an exact Output intent before the first Store operation, and completes it only
after the Store confirms reclamation. Recovery first owns the executor slot;
generation fencing alone is not proof of physical stop.

| Boundary | Responsibility |
|---|---|
| Before allocation acquisition | Known-unallocated cleanup can finish after the existing durable checks. A conflict does not authorize deleting the conflicting entry. |
| Directory acquired, identity held by the live Store | Preserve the exact device/inode before attempting its durable write. Identity-write, child-open and writer-preparation failures use the acquired cleanup path, not known-unallocated cleanup. Failed persistence retains the live owner and reservation. |
| Identity durably recorded | Reclaim only the matching allocation, preserve unrelated public names, confirm deletion and directory sync, then release capacity. Nonempty directory removal is not reclamation success. |
| Process stopped before identity became durable, or identity inspection failed | A recorded name plus an existing entry is insufficient ownership. Persist `Reclaiming`, return `RecoveryRequired`, keep the allocation record, reservation and Output intent, and never advance to `Reclaimed` or complete the intent. |
| Recorded entry absent | The existing owner confirms directory durability before releasing capacity and completing reclamation. Absence alone is not durable deletion proof. |

The filesystem primitive reports acquisition separately from identity and
durability confirmation. An inspection failure after `mkdir` does not unlink
by name; a directory-sync failure preserves the acquired exact identity.
The Store's in-memory acquisition map is cleanup custody, not a second capacity
ledger. It is bounded by the existing payload reservations and is cleared only
after the durable reclaim completes.

The resident control process reports `allocation-needs-reconciliation`, with
the Store/journal locations, and `allocation-reconciliation-intent` with the
exact payload request CID. It keeps the Store and executor slot, parks automatic
reclaim attempts for this ownership-unknown case, and starts no new executor.
Restart discovers the same durable state; it neither creates another allocation
nor changes the accepted Run into a new execution.

## Explicit limitation and operational evidence

Automatic reclamation is **not** guaranteed at every possible stop point.
`mkdir` followed by a stop before the directory identity write leaves an entry
that cannot be distinguished safely from a foreign entry at the recorded name.
The seven previously named recoverable kill points still reclaim successfully;
the added `allocation-created` point intentionally retains capacity and intent.

Current APIs can retry an exact live owner's cleanup and can finish after
independently established absence. There is no supported ownership-evidence
repair/termination API for a present, ownership-unknown allocation. A safe
operational reconciliation/termination procedure and an automatically
recoverable acquisition redesign remain separate work. Do not populate the
ownership record from `stat`, delete by name, force capacity to zero, or mark
the intent done. Those actions would manufacture missing authority.

For investigation, retain together:

- `publication_payload` in `Reclaiming`, its exact request and revision;
- `publication_payload_allocation` under the same material key, including the
  recorded name and absence of acquired identity;
- the capacity reservation and the actual entry at that name;
- `site_output_intent` and its dispatch/attempt binding, without a matching
  completion record; the Site's configured Store authority and journal binding.

The regression's disposal of a foreign fixture uses its separate test owner.
It is not a product repair command and does not establish production deletion
authority.

## Executed regression evidence

At implementation `f0448758e`, using the pinned MoonBit toolchain, real SQLite
and filesystem on macOS:

- Publication Store runner: **26/26 passed**, with native SQLite and a fresh
  Store root set; all allocation regressions executed. The legacy-root and
  subprocess-lock fixtures have additional environment guards and did not
  execute in this direct command; the Native-job harness supplies those.
- Allocation-focused earlier run: **10/10 passed** before adding the created
  directory inspection fault regression.
- `scripts/test-native-resident-site.mjs`: passed. Its existing success,
  delegation refusal, actual executor counts, transfer/release, holder death,
  real journal failure and cleanup cases remain. Added scenario 22 tests real
  SIGKILL after `mkdir`/before identity persistence, both the created entry and
  a separately owned same-name directory, two process restarts, unchanged
  reservation/intent/entry and zero additional executor entries. Two separately
  observed queued acceptances synchronize control-loop progress without a
  fixed sleep or requiring a blocked execution to complete.
- `git diff --check` and MoonBit formatting checks passed.

Fault injection is identified precisely: identity/open/writer preparation uses
a private typed whitebox seam around real Store acquisition; directory-sync
and created-directory inspection use the filesystem primitive's fault hooks.
The process stops, directory replacements, SQLite write locks and physical
files in the resident acceptance are real.

Verification failures retained in the record:

- The initial allocation regression reproduced the pre-fix leak: its directory
  remained while capacity was returned.
- Reusing a previously populated full-suite Store root caused a fixture setup
  abort; the successful full-suite runs used fresh roots. This was not treated
  as a product fix or silently counted as a passing first run.
- The first two new process-test runs incorrectly retained the stand-in's
  terminal dispatch waiter for intentionally unstarted accepted work. One timed
  out waiting for completion; the other starved the next stand-in handout.
  The test now withdraws that transport waiter after actual acceptance, while
  leaving the Site's durable accepted record queued. No product timeout,
  retry, gateway implementation or expected executor count was relaxed.
- The local Native job's first step passed. Its later calibration step refused
  the dirty checkout (`NativeCalibrationRequiresCleanCheckout`); that is not
  a complete local Native-job pass. The clean-checkout follow-up and final CI
  results are recorded in the PR rather than inferred from an earlier SHA.

Re-run with the pinned toolchain and root dependencies available:

```sh
# Both paths must be fresh, task-owned directories outside the repository.
ACTQL_TEST_NATIVE_SQLITE_LIBRARY=/path/to/sqlite/library \
ACTQL_TEST_NATIVE_STORE_ROOT=/path/to/fresh/store \
  moon test --target native src/platform_native/publication_store
ACTQL_TEST_SCRATCH_ROOT=/path/to/task/scratch \
ACTQL_TEST_PRESERVE_SCRATCH=1 \
  node scripts/test-native-resident-site.mjs
# Complete job: only from a clean checkout, with no unrelated untracked data.
node scripts/local-checks.mjs run native
node scripts/local-checks.mjs run lint
```

## Scope and handoff

This completes the allocation-custody correction inside O1/O3/O4/O7. It adds no
public SDK API, canonical CID rule, wire or saved format. It reuses the existing
`Reclaiming` state and typed Store issues. The pinned compiler conversion uses
`StringView.to_owned()`; three deprecated calls caused the previous Linux
native/connector-addition compile failures.

The resident Site still accepts source-free Values materials. Inner materials
are capped at 262,144 bytes; encoder/HTTP/journal/holder limits are respectively
1,442,816 / 1,441,792 / 1,048,576 / 2,097,152 bytes. These are different boundaries,
not a promise that every future Connector binding fits. Values binding remains
`{}` and the escaped envelope fits the journal; oversize materials are refused
before acceptance. No default limits were enlarged by this fix.

Cloud #39 merged at `73a45960d480ab379d0d199c3a24ca8e633cf45b`. Its protocol
fixture completion is separate from actual resident Site integration: pin the
OSS and Cloud SHAs, connect the materials envelope, then verify executor entry,
transfer, publication and public Named Result. This local Site test uses an
HTTPS Cloud stand-in; it is not real Cloud or Salesforce-org acceptance.

Remaining separate units: trust-model review (§3), observation-history bounds
(§6), O5 lost-reply recovery, O2 handout cancellation, O6 restart/generation
semantics, native bundle-retention failure custody (old item 5), and Site journal
COMMIT/ROLLBACK cause retention (old item 7). Graph/carrier task implementation,
Cloud code and a new protocol/execution loop were not added to this fix.
