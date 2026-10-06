# Native retained-file restoration boundary

The original retained-file Owner can seal and read a task output, but previously
had no entry to re-adopt the same committed physical file after that Owner left
scope. The filesystem already provides exact-generation reader and reclamation
operations. This change connects those existing operations to the retained-file
Owner rather than creating another writer or reacquiring Source data.

## Caller contract

`sealed_generation()` exposes the original device, inode and size only while
the sealed file is available. The trusted caller must preserve that value with
the original occurrence, content CID and responsibility in its existing custody.
It must not substitute a generation obtained by inspecting whatever currently
occupies the filename.

`restore_native_retained_task_file(root, occurrence, generation, cid, max_bytes)`
re-adopts exactly `output-<occurrence>`. Missing or replacement generations and
an insufficient bound are rejected. Restoration creates no staging writer,
Source I/O, capacity reservation, Transfer, borrow or executor entry. Complete
bytes remain provisional until the existing reader's `finish()` verifies their
content CID. A failed verification revokes further use.

This is a physical storage port, not dispatch authorization. Before calling it,
the existing holder/exclusive-slot boundary must prove the previous owner is
stopped and that only one owner resumes this responsibility. The caller must
re-admit the original Run, producer, attempt, checked edge, schema/order, input
port, current Site identity/generation and authority through their existing
Owners. Those facts are not inferred from a matching file.

The original writer-backed Owner keeps its existing cleanup path. A restored
Owner uses filesystem reclamation of the saved generation and confirms release
only after unlink and directory synchronization succeed. Missing-file retry
still synchronizes the directory. A replacement is preserved and failure stays
retryable. Successful release is idempotent. Active readers must finish or close
before cleanup; a borrow return does not by itself release any Site reservation.

## Executed evidence and remaining work

The bounded Native package selection runs nine cases, including four new
physical restoration cases: original bytes without a new writer, missing or
over-budget input, replacement protection and synchronization retry, and
provisional reads with a wrong content CID. Existing writer-backed seal,
reader reclamation, integrity and cleanup tests remain selected.

The first attempt stopped at compilation because the new fixture helper lacked
its assertion error declaration. That declaration was corrected; it was not a
runtime or product assertion failure. The corrected Native selection passes
9/9. The actual consuming `remote_resident_host` package also passes a scoped
Native `moon check`. The interface is generated with `moon info`.

This does not yet connect custody persistence, Site reservation reconstruction,
producer Runtime restoration or consumer-holder recreation. It does not prove
the public Cloud two-task Run, normal release or fault acceptance. The next
connection must persist exact custody under the original journal responsibility,
restore each reservation once under the exclusive slot, and validate the
existing binding before consumer start. Missing material must remain an explicit
input-restoration failure with cleanup responsibility; it must not trigger Source
reacquisition or be mislabeled as an unknown execution outcome.

The final destination is OSS `main`, after the parent chain through #598 and
#571. Formal Cloud adoption still requires a merged source with matching five
packages and Native binary. There is no wire, contract CID, independent fixture,
Cloud vendor pin or shared cancellation/Ledger change here. Cloud #88 old Run
responsibilities remain separate. The full connection is tracked in [#182](https://github.com/actql/actql/issues/182).
