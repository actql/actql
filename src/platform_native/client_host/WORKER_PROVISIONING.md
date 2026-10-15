# Original pre-Core worker provisioning identity

The existing Native Host adoption/journal Owner issues one child provisioning
operation before the worker child acquires its physical resources. Existing
Host initialization/backing and the child operation are separate lifetimes. Its parent
is the original adoption and Submission epoch. The child key is independently
issued random identity, not the parent nonce/CID, Resource DATA, PID or FD.
`OriginalLocalInstallation._project` and Wasmtime are not involved.

`issue_worker_provisioning` requires the current Account's explicit
`resource=worker, operation=provision`. `lookup_worker_provisioning` independently
requires `worker/read`. Neither is inferred from Run submit/read. Selection is
an opaque original from the existing installed arena Host;
metadata selection does not supply a numerical profile or permission to acquire.

Fresh Host adoption initializes the child custody witness in its existing
transaction. Missing custody on older/partial installations refuses; this unit
does not repair or migrate it. A retained child intent precedes the immutable
SQLite row and selected-key CAS. The same Host retains the partial carrier before
file/SQL I/O. Failed file closure keeps the existing Writer/Root responsibility.
A lost COMMIT reply fences that journal. Reopen uses the same intent/key in the
same Store and only observes; it never writes, reserves, acquires or launches.
A known absent SQL row after the durable intent remains `UnresolvedOriginal`
with `NotRecorded`, not retry permission. An issued witness with a missing row
is custody loss. The parent witness stores the existing adoption CID rather than another full
adoption body. The child intent/SQL/live body copies are bounded to 2048 bytes
each; their 8192-byte metadata reservation uses the existing settings budget.
This reservation does not account for native control/loader/VM overhead.
The existing bounded settings metadata reservation is consumed;
no capacity limit is increased. This is not full bootstrap physical funding.

The closed intent binds adoption, original epoch fingerprint, independent child
key, selected source, recipe and provider generation. The first key phase has no
worker-child ticket/backing yet. The subsequent existing live Resource DATA and
actual provider/child/backing projection must attach under this SAME key; it must
not create another attempt. Source/recipe/generation substitutions refuse.
All cold results are unresolved DATA, never a nominal child, Ledger, borrow,
zero-debt claim, launch, stop or settlement acknowledgment.

A successor issuer is deliberately unavailable in this slice. Full actual
worker/descendant/FD/alias retirement has no complete typed supplier here yet.
Closing an unacquired selection, missing records, direct-PID exit and finishing
Host initialization cannot supply that proof. Once the existing Owner connects
its genuine retirement evidence and new current authorization, a separate child
identity may be issued. This refusal is not claimed as a successful successor
acceptance or complete worker recovery.

The focused Native tests cover actual isolated SQLite commit/reopen, lost first
COMMIT reply, uncommitted first write with retained intent, foreign epoch and
generation, missing original records, and independent Account refusal. Runtime
selection is metadata only: physical arena acquisition, Python Wasm Core, worker,
Engine, ordinary installed wheel and public Python product execution remain 0.
