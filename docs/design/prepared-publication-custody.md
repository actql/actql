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

An externally missing object from a closed prior Store lifetime remains a read
refusal. Its exact opening accounting row may nevertheless be retired without
inventing an original FD: the Store excludes current readers, writers and
preparations, fences that CID, verifies absence on both sides of the actual
object-directory ACK, and removes only that unchanged row. Failed ACK or a
replacement retains the fence and charge. Current allocations and previously
retired/replaced opening generations require their original cleanup path;
equal CID/device/inode DATA cannot restore prior-lifetime eligibility. This
selected reconciliation neither scans unrelated history nor resets its quota.

## Bounded deletion diagnostics

Prepared-object release and the original Result/metadata deletion owners share
the same first/latest cleanup diagnostic operation. Each private list retains
its first original throwable and replaces only its latest positional slot.
Repeated identical values still occupy both roles; primitives, frozen errors
and `undefined` retain their exact identity. Frozen status snapshots remain
independent of later list updates. This bounds retained retry history without
restricting the number of retries or inspecting an error to infer success.

The original deletion serialization, unconfirmed object inventory, unlink and
directory durability stages remain authoritative. A failed observation keeps
that same owner pending and retains its capacity. Only the existing successful
durability/accounting transition settles it. Diagnostic replacement supplies no
physical acknowledgement, new reservation, refund or permission to resend.

## Bounded managed-execution diagnostics

The synchronous managed-failure adapter records its own first/latest cleanup
throwables through the same diagnostic operation. Original read failure,
upstream/additional cleanup owners and their current observations remain
separate. Diagnostic replacement neither advances the Core failure progression
nor marks operations closed. Repeated failures can remain pending indefinitely;
only their original successful close/stop/settlement transitions advance it.
The execution settles once, and an Unknown reader still cannot be treated as
stopped because a diagnostic slot was replaced or an input reader disappeared.

## Publication retry diagnostic prefixes

A publication failure can initially collect separate diagnostics from its
original prepared payload, export or Transfer children. Preserve that finite
initial prefix, and capture its length once before exposing retry. The shared
diagnostic operation retains the first and latest subsequent retry failure
after that prefix. It never recomputes the prefix from a growing history.
Commit-pin confirmation, pending writer cancellation and schema release use
the same operation with an empty prefix. Delivery keeps its initial record
failure; Unknown publication keeps its separate reconciliation/record facts.

Transfer retains the prefix on its existing state so source-stop and
destination-recovery helpers follow the same rule as the outer cleanup handle.
Its aggregate close and source-release handles preserve their initial
per-entry failures too. The existing original child inventory, cursor,
single-flight guard and physical status decide progress. Replacing a diagnostic
does not drop a child record, resolve Unknown, repeat a mutation, release a pin
or settle capacity. Earlier frozen snapshots retain their original contents.

These diagnostic references and the fixed prefix selector are retained caller
controls. Their presence neither supplies the complete physical construction
recipe nor permits a Store quota or protocol byte ceiling to substitute for
that caller's live memory/failed-child backing.
