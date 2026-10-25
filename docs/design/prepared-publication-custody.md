# Prepared publication custody

Content identity and ownership are distinct. A material CID locates bytes; it
cannot select a process-local holder for retirement. The Store uses four owners:

| Owner | Identity and retained duty | Terminal witness |
| --- | --- | --- |
| Physical generation | Original installed inode, charge and recovery record | Last dependency gone and original physical cleanup acknowledged |
| Prepared holder | Nominal writer-issued handle and its own custody | Explicit handle release or selected transfer after durable adoption |
| Commit pin | Original public commit attempt | Its own confirmed adoption or confirmed absence; Unknown retains it |
| Durable owner | Confirmed Index or physical holding | That owner's existing retention/retirement protocol |

A content group indexes these owners but is not itself permission to retire them.
Physical reclamation serializes before per-CID metadata transitions. No per-CID
transition waits for the material queue. Public commits retain their existing
semantic serialization; private holding adoption cannot consume a public pin.

## Selection and transfer

The ordinary exporter supplies its exact `physicalPrepared` handles through the
publication coordinator to the Store's optional fifth `commitIndex` argument.
The fourth original-Index argument is unchanged. The handle inventory is copied
before asynchronous work and validated against the Store's private registry and
verified material inventory. Repeated aliases of one handle select it once;
distinct handles for identical content remain independent.

Successful adoption retires only selected holders. It removes their own custody
records, except that the original allocation recovery record remains with the
content group while another holder or commit pin still depends on that generation. Losing
seals' temporary-inode records cannot replace this recovery duty. The last holder or pin
settles the remaining original recovery records exactly once under the material
queue, with failure
retaining the same cleanup owner. A holder can already be durably transferred
while its original commit pin still owns a failed allocation-record cleanup;
these are distinct obligations. This is transfer of an existing duty, not a new
allocation or a new durable witness.

A confirmed durable reference may make a holder releasable, but cannot release it
without its original handle. Stored-evidence validation has no holder-adoption
side effect. Legacy callers omitting the optional handle inventory keep their
original holders and explicitly release them; ordinary SDK callers receive no
new cleanup obligation.

Private holding publication already takes exact prepared handles. Its pending
selection is registered before the original write and retained across an Unknown
acknowledgement. Confirmation transfers only that registered selection. A read of
an unrelated same-CID holding never creates a selection. Settled holders remove
their own pending-transfer references; unresolved owners remain available for
original confirmation or cancellation.

## Refusal and recovery

A missing group is not proof of adoption. A commit verifies the original under
the material queue and acquires a temporary, non-removable pin before installing
its Index. Partial acquisition returns only its own pins. A failure or lost reply
never replays Compute or grants permission to remove a foreign generation.

Schema semantic owners, metadata transactions, publication progress funding and
Host preparation Ledgers remain distinct protocols. This model does not claim
allocator/RSS reclamation or a global concurrent-memory bound.

Final pin cleanup reuses its own verified binding inventory after a successful
Index install. It checks that Index's exact metadata and Result deletion markers
inside the material queue before treating that original owner as live. Errors and
Unknown reads retain the original pin cleanup; they are never absence. A
concurrent metadata retirement must retain its original deletion recovery owner
before attempting physical reclamation, and physical reclamation joins the same
material queue. Thus a marker appearing after the read cannot leave an unowned
allocation: the durable Index or its original retirement owner still owns it.
If its own witness is retired or absent, cleanup uses existing live-reference and
original-generation recovery rather than reusing stale successful-adoption state.
