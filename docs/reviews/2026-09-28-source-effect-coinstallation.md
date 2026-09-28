# Source and Effect co-installation

The standard Host can restore a published Source and a published Effect from
one state root. A read Program and a separate Values-origin Effect Program
can each be submitted through the public Client and publish Named Results.
This does not add compilation of one Program that acquires external input and
then applies an Effect; that Program shape remains explicitly unsupported.

## Installation boundary

Each adapter restores its own published generation without provider I/O. The
Host admits the individual Check Environments and composes their closed
declarations before opening its dispatch path. Identical declarations may be
shared; the same connector ID, mapping selector, or other registered selector
with different content is rejected. The combined Check Environment has its
own canonical CID and is admitted by the existing MoonBit checker. The Host
does not infer read permission from an Effect declaration or commit permission
from a Source declaration.

For a shared connector ID, the adapters additionally expose a non-secret
physical binding CID. Equal Catalogs alone do not prove that the connection,
principal, tenant, Site generation, or Host root are the same. The Host
requires matching bindings before provider I/O. Authorization remains
role-specific and is rechecked at the existing read and commit boundaries.
The binding does not carry credentials or grant authority.

An Embedded reconnect compares both profile identities and the selected
Host authorization. A different Source or Effect publication, Site profile,
or account configuration cannot silently reuse an existing Host root.
Callbacks that affect execution must retain the same reference because their
semantics cannot be recovered from a file digest. The remote Host receives
the same two profile options. The packed package uses the same Embedded
installation path, not a second co-installation implementation.

Initialization cleanup retains both acquired adapters. Failure of one close
does not suppress the other close, and the primary initialization error is
kept separately from cleanup errors. Shutdown fences new requests and drains
active dispatch before closing Checkpoints, adapters, journal, and Store.
Failed cleanup remains owned and retryable; retry does not restart Compute or
provider writes.

## Product-path evidence

The reference-site HTTP tests submit a DuckDB-backed read and a two-member
Effect to the same Host. The read produces the independently expected IDs
`[2, 3, 3]`; the Effect publishes the original Values rows and records each
physical row send once. Another case holds both read access and Effect commit,
restarts the Host before and after answers, and checks distinct Checkpoint
kinds and publication of both Results. A denied read does not suppress an
independently authorized Effect. Existing Effect tests cover unknown replies,
partial results, cancellation, retirement, and barriers.

The Salesforce HTTPS fixture publishes Source and Effect generations for the
same connector ID. The standard HTTP Host restores both without a provider
request, reads the expected records, then resumes an approved Effect after
restart and publishes its Named Result. A differing Catalog under that same
ID is rejected twice at startup with zero additional provider requests and
without retaining a Store lock. This is mock-provider evidence, not an org
test. Two equal Catalogs with differing Site aliases are also refused before
provider I/O. A Program combining that acquisition with an Effect is rejected as
`ClientProgramUnsupported` before provider I/O or request admission.

The repo-external packed installation uses installed tarballs, with no
MoonBit toolchain in the child process. It reads through `@actql/local-node`
with both profiles set, and executes the approved Effect through
`@actql/node` on the same state root. The physical write count stays at two
after recheck. Another packed process reconnects with equivalent options,
then refuses a changed Source profile and a changed Effect profile before
provider I/O.

## Validation and limits

The relevant local gates are `client` and `host`; the pushed SHA's Linux CI
must be checked separately. No live Salesforce org operation is claimed here.
External-acquisition-to-Effect compilation, multiple Sources, read-approval
continuation within an Effect Program, Cloud, Hybrid, and placement selection
remain outside this completion unit.
