# Bounded multi-consumer holding

This increment extends the existing local Store and its admitted process
delegation to multiple independently settled reader pins. It implements a
physical-lifetime part of Q5/Q8, not full managed-profile completion or semantic
evidence authority.

## Admission and accounting

`maxReadersPerBody` defaults to one, preserving the existing exclusive-reader
behavior. A Host can explicitly admit more readers. `maxReadBufferBytes` bounds
the Store-wide reservation for simultaneous verification buffers; by default it
is the safely checked product of `maxFrameBytes` and `maxEntries`, matching the
previous maximum one-reader-per-body allocation. Each reader reserves
`min(maxFrameBytes, max(1, body.bytes))` before allocation or delegation.
These are verifier-buffer bytes, not a bound on all native engine memory.
They do not replace selected task/Run resource admission, which still needs to
cover native decoder memory and the other simultaneous reservations.

`activeReaders` and `reservedReadBufferBytes` expose the corresponding live
responsibility. Each confirmed stop returns only its own reservation. Cancellation
requests do not release buffers still used by an awaited callback. Revoking a
body prohibits future use, while physical reclamation waits for every reader.
No data copy or logical CID is required solely to add another physical read pin.

The process Store now tracks outstanding reads by their existing unique token,
not one mutable slot per output. Its session/run checks and exact terminal
reports remain unchanged. Actual process exit settles every remaining reader;
it does not settle other consumers early or revoke independently retained output.
There is no new portable wire or permission inferred from equal content.

## Verification scope

New tests verify separate tokens, foreign-report rejection, per-body and global
capacity refusal, idempotent stop confirmation, cancellation of one concurrent
consumer without cancelling another, and delayed cleanup until the last pin.
Two manifest consumers concurrently pin both chunks of the same result, reserve
10 verifier bytes for four pins, return those reservations, and leave the five
unique stored bytes held.

The actual managed-process fixture opens two reads, finishes one, then exits
with the other still live. The controller retains the remaining storage/buffer
responsibility until confirmed exit and cleanup. This tests the existing
delegation channel, not a serialized-handle simulation.

Validation passed: `check:retained-boundary` (105 tests), the real DuckDB
manifest and standard Host integration (3 tests), and `check:docs`. These
checks retain the legacy single-reader default and its rejection tests.

This does not establish consumer authorization, scoped semantic evidence issuance,
strict-deadline stopping, or the new profile's transformation/completion paths.
Those remain required before runtime-profile acceptance. No new throughput or
27-case performance claim is made by these lifecycle tests.
