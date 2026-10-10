# Native Effect continuation and Checkpoint custody

## Persistence boundary

The actual retained Native consumer keeps the original Capture and Provider
Preview owners, then retains its whole continuation snapshot and common-issued
Checkpoint as two separately encrypted physical holdings. The existing Store
transaction, capacity reservation, authenticated readback and retryable
retirement mechanism serves both; no second lifecycle ledger is introduced.
The common Checkpoint CID scopes both physical slots inside the original Store.

The continuation byte hash must match the sealed Checkpoint before encryption
or allocation. The Store authority must be the original evidence authority.
The Native caller accepts only a review prepared by this exact consumer and
requires the original computation and Preview readback. Both new encrypted
sizes are reserved in the existing execution Ledger before the first write.

Partial persistence is allowed as unfinished work. The same custody pair and
reservation are returned on an uncertain write. Store reopening authenticates
any existing original slot and permits an absent second slot only for continued
persistence. No confirmed pair or waiting projection is returned from partial
storage. Repeated persistence reuses the original ciphertext and reservations.

After both exact saved bodies are authenticated, the common Checkpoint owner
confirms persistence and can produce the waiting projection. The original Run
owner must still commit that projection under its own revision and current
permissions. Neither the projection nor custody is approval, a physical-start
claim, or an Effect recovery permit.

## Privacy and cleanup

The existing AES-GCM envelope gains two closed Native evidence roles,
`continuation_record` and `checkpoint`, under the unchanged authenticated
publication-evidence preimage. Independent public Node crypto vectors verify
role, key and identity authentication. This does not claim that a Node provider
profile can restore the Native snapshot.

The continuation, Checkpoint, computation, Preview, Source, receiver, borrow and
Named Result remain distinct obligations. Explicit retirement is only for a
trusted caller that has discharged the corresponding retention obligation; a
Run status alone does not prove it. Each physical owner confirms its durable
terminal before returning its Store reservation. The original execution Ledger
reservation is returned only after both retirements succeed. A failure retains
the same handle, and retry cannot return the reservation twice or resurrect a
retired slot.

## Acceptance and remaining work

The existing actual Native Provider harness has a separate Checkpoint case that
uses the unchanged 10-attempt and 512 MiB limits. The original Source custody
fault campaign remains in its original case; those cumulative fault allocations
are not rerun inside the new Checkpoint case. No resource bound is increased.
The Checkpoint case injects interruption after
continuation commit, interruption after Checkpoint commit and lost terminal-save
acknowledgement. It verifies that partial storage exposes no waiting projection,
full readback projects the original Run, retries retain exact ciphertext and
one reservation, wrong key/role/authority/body are refused, retirement returns
only the paired reservations and the original computation/Preview remain live.

Store reconstruction retains the original live execution Ledger. This is not
Host/Coordinator restart or reconstruction of execution resources. Full durable
recovery inventory, Run waiting commit, public resolution, current approval,
Effect write/outcome reconciliation, Result publication, formal release and
real Cloud Preview acceptance remain required in the overall F goal. Cloud
formal cohort adoption is separate and must use merged OSS source and the
matching production Native binary.

Parent: #1201 (`071a2e457efe0eadad3562c81dd35fc3cc645f9d`). The final merge
is into OSS `main` after that parent; no merge or hosted CI start is performed.
