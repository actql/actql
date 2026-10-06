# Native producer output custody in the Site journal

## Problem and connection

The acquisition-task export now has a sealed physical file, but its exact
writer generation was still process-local. Restoring the dispatch's managed
output observation alone could not identify the original file safely. A fresh
stat of a matching filename must not create ownership after holder loss.

The existing Native Site journal now stores an opaque output-file custody
snapshot in the same SQLite transaction as the managed output observation and
dispatch revision. The snapshot contains the original request CID, occurrence,
saved device/inode/size, stream content CID, material generation and the common
physical manifest. Device and inode are canonical decimal strings so the full
UInt64 identity survives JSON without floating-point rounding.

The standard acquisition-task export constructs this snapshot from the sealed
writer. Runtime checks its request and output facts, retains physical cleanup
responsibility on rejection, and passes it to the existing evidence commit.
Journal admission checks the typed subject's request, generation, schema,
view, codec, manifest, row count and retained bytes. Reopening the journal
readmits both the original dispatch observation and custody. It does not stat
the file, acquire a reservation, grant authority or start an executor.

The local `site_output_file` record is metadata in the existing Site journal,
under the original dispatch attempt key. It is not an execution ledger or a
separate scheduler. Existing outputs without a file remain representable as
absent custody; absence cannot authorize file restoration.

## Failure and retry

The managed observation, custody and dispatch revision commit together. A
failed commit rolls back all three. If commit succeeded but its reply was
lost, retry must reproduce the exact observation and custody bytes, including
the presence or absence of custody. Another inode, request, manifest or omitted
snapshot cannot replace the saved original. The common in-memory transition
is committed only after the SQLite commit is confirmed.

Custody decoding preserves raw JSON values, checks canonical decimal forms,
readmits the common manifest and requires an exact canonical encoding. The
writer bound includes the UTF-8 length of every field with overflow checks;
the existing journal record limit still applies before transaction mutation.

## Executed evidence

Focused Native SQLite tests cover exact UInt64 restoration with typed
completion, transaction rollback, lost commit reply with exact retry, and
foreign request/manifest rejection. These use real SQLite but synthetic file
metadata; they do not establish physical holder reconstruction.

The affected Native physical export tests still cover exact acquired stream
bytes, manifest order/extent/content verification, replacement-safe cleanup
retry and append-failure cleanup. A portable runtime caller test covers
material-generation and manifest mismatches. The pre-existing typed output
restoration test also remains in the selection.

Exact source SHA, commands, counts and CI status are recorded in the PR.
Preparation runs before the commit are kept separate from submitted-source
confirmation. No full Core, packed campaign or performance run is implied.

## Remaining public execution boundary

This supplies durable custody metadata, not a restored completed producer
runtime. Same-generation holder reconstruction must still recheck current Site
identity, generation and authority, restore the original reservation exactly
once, readmit completion and reconnect the existing Transfer/holding owners.
Sender holding, independent receiver holding, consumer borrow and Named Result
retention remain separate cleanup obligations.

There is also a distinct interruption window before this completion commit:
the physical file is created and sealed before custody is committed. A crash
there must not infer ownership from a pathname or reacquire Source. Creation
and cleanup responsibility need to remain with the existing owner and journal
before that window can be considered recoverable.

Public Cloud two-task execution, holder recreation, current-source Native
integration, final reservation restoration and interruption acceptance remain
unverified. This change does not adopt OSS packages into Cloud, deploy a
Preview, resolve old #88 Runs or claim formal release acceptance.
