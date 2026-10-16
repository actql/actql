# Physical holding metadata publication

Physical holding creation, sharing and deletion intent use the existing Store's
staging directory and exclusive hard-link publication. The complete original
record is written, file-synced and closed before it receives a final name.
The original containing-directory durability acknowledgement remains separate;
visibility alone never adopts prepared custody or confirms an unknown commit.
Existing record bytes, CIDs, conflict comparison and reclamation rules remain
unchanged. Incomplete bytes occupy only an unpublished `object-<UUID>` staging
alias, which the same Store's existing restart recovery removes. A crash after
the exclusive link leaves complete final bytes, not a new commit receipt.

This does not repair or ignore an old corrupt final record. Startup still
refuses it and retains the original recovery evidence; no missing/empty record
is interpreted as an unapplied operation, permission or cleanup success.

## Same-owner cleanup and inventory

The existing Store retains each active metadata writer's record in its private
writer set before opening its staging FD. Holding publication keeps its existing
exclusive writer-admission fence. A false or rejected close keeps that exact FD and forbids final
publication or staging unlink; retry only closes/unlinks/syncs the original
staging alias, never rewrites bytes or creates a new holding. Cleanup is
single-flight, and `Store.close` retains/drains the same duty even if the
caller sanitized or discarded its error. Original prepared-object custody and
the holding-directory ACK remain independent. No key, ownership or capacity
is released merely because a callback returned or cancellation was requested.
After confirmed cleanup, an escaped cleanup handle drops its explicit original
Store/writer association; its retired status does not retain that live set.

The original metadata envelope includes the admitted record/Buffer, temporary
path/UUID Strings, file and hard-link/directory operations, writer-set entry,
closure/status/cleanup record, pending Promise/flight, retained original FD and
failure/cause references. The original prepared payload and commit queue may
overlap all of these. A successful unlink is not its directory sync, and a
weak reference or GC opportunity is not a physical acknowledgement. This
inventory is not a byte grant or a normal four-role Model profile; unknown
layout/bootstrap costs remain unknown, and existing limits do not increase.

## Prepared-object custody records

Original prepared-object custody now uses this same Store-owned metadata
writer: only a complete, file-synced and closed record receives its exclusive
final `prepared-custody/<UUID>.json` name. The original custody directory still
needs its separate durability acknowledgement before the object writer links
its payload. Record bytes, recorded payload device/inode, custody/reclamation
identity and recovery validation are unchanged. Empty or partial bytes from an
interrupted write remain in the existing staging namespace, where original
restart recovery already reclaims unpublished aliases. A corrupt final record
from an older process remains refused, not repaired or treated as absence.

Independent prepared writers retain their existing concurrent behavior; they
do not acquire the holding-publication exclusive fence or a new queue. Their
metadata FDs join the same Store duty set before acquisition. Failed/false close
is retained there even if the object writer's error is discarded; shutdown or
the same single-flight handle performs close-only cleanup. Completion never
reseals or resends a request. The additional staging path, record/Buffer,
writer-set entry, closure/Promise and original error/FD overlap with the payload
writer and reservation until actual retirement. This is explicit inventory,
not numerical funding or a physical-byte exemption.

A failed metadata duty also prevents a new metadata FD acquisition until the
same duty retires. Its payload reservation can already have been returned, so
that reservation's original object limit cannot be reused as evidence that the
failed metadata lifetime ended. The existing writer record adds one private
failure Boolean; admission scans the existing duty set without copying it.
Healthy in-flight metadata writes do not activate this fence and may proceed
in parallel. Retry only retires the original FD/staging duty, without rewriting
the record; after actual retirement ordinary preparation is admitted again.
The Boolean and scan iterator/workspace remain explicit control inventory,
not a new Owner, counter, FD quota, numerical profile or permission grant.

## Verification boundary

The independent tests interrupt the actual filesystem write before any byte
and after eleven bytes in a fresh process. Other cases exercise false/rejected
close, same-FD cleanup, error-discarded Store shutdown and unchanged refusal of
an old corrupt final name. The existing prepared release tests retain lost
commit replies and delayed directory ACKs. Protocol admission uses the explicit
contract-control fixture; these are real Store/filesystem/process tests, not
genuine Core admission, installed Model acceptance, Provider I/O or numerical
funding proof. Original installed failures remain separately source-qualified.
