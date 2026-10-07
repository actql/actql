# Saved Output reconciliation

A completed consumer can have a sealed publication payload and a started
Transfer while its first Output report is still absent. Recovery must not
recompute its Result, regenerate the Output intent or upload its payload again.

`Journal::reserved_output(request, intentKey)` reads the original reservation
from the existing Site journal. It re-admits its canonical bytes and checks the
exact dispatch and intent identity. A missing reservation is distinct from
invalid or foreign custody. This read does not grant current use authorization
or establish payload, Transfer, report or ACK success.

`reconcile_durable_direct_transfer_from_source` requires the original started
sender record and an exact physical source owner. It queries the original
destination using authenticated HTTP GET. Only a matching committed destination
can advance the sender through the existing Transfer transitions. A missing,
uncommitted or foreign reply leaves the original responsibility unresolved.
This continuation never reads a payload chunk, sends a chunk, creates another
attempt, sends a commit request or performs Source/Compute work.

The trusted current-authority port is checked before query, after query and
after local source stop. Stop is confirmed separately through the physical
source owner; receiver commit is not local stop evidence. The sender record is
reloaded after physical access so a concurrent cancellation or completion is not
overwritten. A failed journal save can retry the same responsibility without
closing an already stopped source twice. Returned failures retain unconfirmed
source cleanup through the existing failure owner. Source-reader stop does not
reclaim producer output, receiver holding, consumer borrow or Named Result.

## Focused Native validation

With the pinned toolchain, system SQLite and a fresh owned SQLite root, select:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target native --strip src/platform_native/remote_journal \
  -f '*reserved Output*'
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target native --strip src/platform_native/remote_transfer_client \
  -f 'direct reconciliation*'
```

Set `ACTQL_TEST_NATIVE_SQLITE_LIBRARY` and
`ACTQL_TEST_NATIVE_SQLITE_ROOT` to the actual library and owned namespace.
Missing prerequisites fail rather than skip. Preserve failed namespaces.

The journal case checks reservation recovery through a fresh connection before
any report exists, absent custody and rejection of another dispatch/attempt.
Seven reconciliation cases execute real SQLite and the common Transfer Owner:
commit with zero payload reads, uncommitted receiver, foreign occurrence,
authority loss during query, concurrent cancellation, persistence failure/retry
with one physical stop, and missing original sender with zero queries.
HTTP and source-stop facts are simulated in these Native unit cases. The Cloud
query route has separate consuming tests; neither establishes public acceptance.

## Required caller integration

Cloud must supply the read-only authenticated query endpoint. Recovery must
rebuild the original Run and validate current Site generation, authority,
lifetime and cancellation before using the saved Output. It must bind the saved
payload intent's attempt and dispatch identities, verify the sealed Store
payload, and validate its plan/subject with the portable Output Owner.

The caller must then generate the first real Output report through that Owner,
save its custody before sending, and persist the report-CID-bound ACK. Existing
cleanup owners retain the original payload, borrow, holdings and reservations
until their independent release conditions are confirmed. An old missing
consumer output-file record must not be fabricated by this continuation.

No public Worker/Native acceptance, historical Run recovery completion, ACK,
publication or formal release is established by these primitives alone. No wire
fields, identity domains or saved-record formats change. The corresponding
Cloud query and formal merged-SHA adoption are independent prerequisites.
