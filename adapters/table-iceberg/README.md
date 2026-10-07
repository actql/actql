# Optional local Iceberg Table I/O

This is an internal physical boundary, not an installed public Table Effect.
Do not invoke `write_claimed` from user input. The future bulk adapter must first
admit the request in common Core, bind the checked/captured whole Relation and
effective policy, obtain approval, recheck current authority, and durably claim
the existing Effect Ledger. No Python component issues approval or schedules
work. The normal Program unsupported guards remain until that integration lands.

## Dependencies and scope

Install on the Host that opts into Table support, not in Core or the SDK:

```sh
python3.12 -m venv .venv-table
uv pip install --python .venv-table/bin/python --require-hashes \
  -r adapters/table-iceberg/requirements.lock
```

The lock pins PyIceberg 0.10.0, PyArrow 21.0.0 and all transitive dependencies.
The initial backend targets a local POSIX warehouse and SQLite Catalog. The
standard PyIceberg `SqlCatalog` uses SQLAlchemy for Catalog management and
metadata loading. Publication uses an explicit `sqlite3` transaction against
the **same** Catalog database so head CAS and original-operation receipt are
atomic. This is not a separate data store: Parquet, manifests and Iceberg
metadata are the Table truth. No external writer or Catalog migration is
supported by this initial backend.

Only flat Boolean, finite binary64 Number, and exact UTF-8 String columns are
encoded. Unsupported types and field-ID layouts fail before staging. The pinned
new-table constructor assigns IDs in physical field order, so the input mapping
must already declare that exact consecutive layout; it is never silently
renumbered. Unicode data values and CR/LF are not normalized.

Conditional value fields are physically nullable and paired with required
boolean fields in the reserved `__actql_presence_` namespace. The mapping binds
both by field ID. Actual Parquet files are inspected before default projection;
missing/NULL companions, missing value fields, and false-with-value are refused.
Ordinary Iceberg readers expose the physical columns, not ActQL absence rules.

## Publication and physical custody

One operation stages one complete Relation. Whole-table replace binds exact
Table UUID, expected metadata generation and unchanged schema/mapping.
Data/manifests/metadata and directory entries are fsynced before head publication.
The immutable original receipt survives later head changes. Frozen generation
reads load the original metadata, never the current head. No ordering is promised
from physical file order.

Persistent limits cover allocated operation count, reserved bytes and reserved
file count. Each output file is recorded before creation, each write is charged
before physical write, and existing files cannot be truncated. Reservation and
file records live in the Catalog database. They are physical custody records,
not another Effect owner. Committed generations retain their entire reservation;
old-generation GC is not implemented. Missing publication evidence does not
authorize a second write: the existing allocation forces reconciliation.

Unpublished staging may be cleaned only after the existing Host process owner
has confirmed physical stop. `cleanup_after_stop` cannot establish that fact
itself. In the same Catalog database transaction, cleanup checks the immutable
original commit record and installs a publication fence. A committed operation
never deletes files, even after a later head change. A fenced operation cannot
publish, claim new files or write existing files. Cleanup removes only the
operation's pre-creation file manifest, without following symlinks. Reservations
remain charged until durable deletion records cover every owned file; failed
deletion or lost custody-save responses remain retryable after restart. Original
allocation, charged bytes, fence and deletion records are retained as audit facts.

## Focused diagnostics and remaining integration

The internal `adapters/host-node/table-iceberg-process.mjs` bridge launches the
pinned optional interpreter through the existing managed-process owner. The
worker uses the existing bounded private execution frames and opens no Catalog
during its handshake. One write consumes one opaque preparation, including an
empty Relation. The caller must admit the operation/materials, check current
authority and approval, and win the existing durable Ledger send claim first.
This bridge does not supply those decisions or register a public installer.

The physical await ends only after observed process exit, not a stop request or
channel closure. Its failure cannot justify a resend. A subsequent process may
read the immutable original-operation receipt; a missing receipt is still
unknown. Cleanup requires the bridge's actual stopped-writer observation and
then the existing Catalog publication fence. No interpreter arguments or
commands are accepted from a Program. Initial transport bounds are 4 MiB,
100,000 value nodes, depth 32, one request and a 60-second physical deadline;
these do not constitute a common execution/retention accounting proof. Delegated
budget handshakes are explicitly refused rather than inventing usage reports.

The real Node-to-Python tests directly construct common Ledger claims. They
establish physical custody/send-once behavior, not Program approval, a current
authorization decision, a common bulk Preview, or public Table-source admission.
They are optional Table Host diagnostics, not mandatory SDK/Core dependencies.

## Saved commit response admission

The common Table projection admits a sealed original-operation receipt, not
just HTTP 200 or `accepted: true`. It checks operation, Effect, Catalog, schema,
mapping, replacement UUID/generation and the captured Relation's immutable row
count, including zero. The resulting private Effect outcome retains the full
receipt. Missing, malformed, foreign or unconfirmed responses leave the existing
dispatch uncertain; they do not certify noncommit or authorize resend/cleanup.

`table-commit-outcome.mjs` reads only the response owned by the exact Ledger
claim and the opaque checked Table Preview. It retains the common outcome
receipt before the existing terminal Ledger CAS. Source availability is needed
for apply, but immutable evidence can still be settled after source release.
This function performs no commit, approval, target authorization or retries.
Host-capture tests use explicit response fixtures; separate optional physical
tests admit actual Catalog receipts. Together these are boundary evidence, not
a completed Program-to-approved-Catalog execution or public Table reader.

```sh
node scripts/local-checks.mjs test node -- adapters/table-iceberg/physical.test.mjs
node scripts/local-checks.mjs build moon -- --target js --release src/connectors_builtin_node
node scripts/local-checks.mjs test node -- adapters/host-node/process-channel.test.mjs adapters/host-node/table-iceberg-process.test.mjs
```

The explicit test requires the optional pinned environment; it does not silently
skip. It runs independent presence fixtures through real Parquet/Iceberg, then
tests Table create/replace, original receipt after restart/later commit, lost
commit reply, injected receipt-save failure rolling back the head, empty typed
Tables, and capacity refusal. Custody tests include concurrent conditional
replace, actual child termination before cleanup, failed cleanup/restart, lost
removal observation, pre-creation failure and symlink refusal. This is **not**
public Client acceptance.

Remaining before public installation: the common bulk Effect adapter and current
authority boundary, bounded streaming of captured input, Host process-stop
integration for staged-file cleanup/retry, immutable
Table acquisition into a new Run, and packed Local/HTTPS approval/restart/release
acceptance. Do not mark the full Table task complete from these physical tests.
