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
writer set before opening its staging FD. A pending writer prevents another
record write. A false or rejected close keeps that exact FD and forbids final
publication or staging unlink; retry only closes/unlinks/syncs the original
staging alias, never rewrites bytes or creates a new holding. Cleanup is
single-flight, and `Store.close` retains/drains the same duty even if the
caller sanitized or discarded its error. Original prepared-object custody and
the holding-directory ACK remain independent. No key, ownership or capacity
is released merely because a callback returned or cancellation was requested.

The original metadata envelope includes the admitted record/Buffer, temporary
path/UUID Strings, file and hard-link/directory operations, writer-set entry,
closure/status/cleanup record, pending Promise/flight, retained original FD and
failure/cause references. The original prepared payload and commit queue may
overlap all of these. A successful unlink is not its directory sync, and a
weak reference or GC opportunity is not a physical acknowledgement. This
inventory is not a byte grant or a normal four-role Model profile; unknown
layout/bootstrap costs remain unknown, and existing limits do not increase.

## Verification boundary

The independent tests interrupt the actual filesystem write before any byte
and after eleven bytes in a fresh process. Other cases exercise false/rejected
close, same-FD cleanup, error-discarded Store shutdown and unchanged refusal of
an old corrupt final name. The existing prepared release tests retain lost
commit replies and delayed directory ACKs. Protocol admission uses the explicit
contract-control fixture; these are real Store/filesystem/process tests, not
genuine Core admission, installed Model acceptance, Provider I/O or numerical
funding proof. Original installed failures remain separately source-qualified.
