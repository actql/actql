# Python Local in-process Host boundary

The Local adapter invokes MoonBit directly through Wasmtime. Node is a build
tool, not a runtime dependency or a transport fallback. The public Client wire,
remote-site protocol and in-process ABI are distinct contracts.

## Transfer custody

`client_host_buffers` composes the existing physical resource Ledger's shared
capacity, allocations and borrows. A pool reserves its allowance once. A transfer
charges both mutable staging and immutable wire payload capacity, including the
overlap during sealing, plus the physical adapter's copy allowance. All live
transfers share that allowance; byte equality does not merge allocations.
Reservation issues custody before allocating the large staging array. The
first admitted fill allocates storage under that existing reservation, so a
trap during transfer still leaves the caller's exact handle available.

The source decoder preserves raw JSON strings and keys, including Unicode and
NULL. It distinguishes parsing limits from malformed input. Sealing a transfer
does not check a Program or admit a Run.

An allocation is retired before cleanup. Readers must acknowledge physical stop
before their exact borrow is returned. Failed stop or cleanup retains the same
handle and allocation for retry. The root reservation is settled only after all
allocations are released. Closing a pool blocks further admission immediately.

## Instance-private Wasm facade

The physical adapter installs one fresh positive instance nonce. It supplies
positive physical input identifiers that cannot be reused while live. Core
issues monotonically increasing handles from a shared sequence for input and
reader kinds. Handles are never serialized Client references, durable operation
identities or execution authority. The adapter must keep handles private to the
owning instance; neither a handle nor a nonce is an authorization token.

The Python physical bridge checks the installed artifact digest, scalar ABI
version, exact callback signatures, required exports and linear-memory maximum
before opening the instance. `actql_host_abi_version` returns 1; this private ABI
version is independent of Client wire and package release versions. Optional
Wasmtime import is deferred until physical Local construction. Remote import
does not load Wasmtime or DuckDB.

Calls into an instance are serialized. Physical callbacks cannot reenter it.
Input loans belong to their exact bridge object; copying a loan or using it in
another instance cannot acquire custody. Python retains immutable bytes and
measures their copy allowance before transfer. Only an explicit physical
callback returning true acknowledges stop or cleanup; exceptions retain pending
custody. Failed close keeps the same instance and its reservations for retry.
The bridge retains a successful physical cleanup fact until Core acknowledges
retirement. A trap between physical completion and its acknowledgement cannot
repeat cleanup. Acknowledged input close discards its private loan and completion
record; repeated transfers do not accumulate released descriptors.
Closing this Host bridge is separate from closing a Client connection and
cannot decide Run cancellation.

All exports use scalar arguments. Input chunks are ordered, at most 16,384 bytes,
and admitted before the physical callback runs. The three imports are
`actql_host.input_byte`, `input_cleanup` and `reader_stop`. Bytes must be in
0..255. Cleanup and stop return zero only when the corresponding physical fact
has completed; nonzero retains custody. Adapters must convert physical failures
to pending results rather than destroy the instance holding cleanup obligations.

The `actql_buffer_*` exports return zero for completed actions, positive handles
for reservations and borrows, or these negative outcomes:

| Code | Meaning |
| --- | --- |
| -1 | Foreign instance |
| -2 | Missing, stale or wrong-kind handle |
| -3 | Invalid configuration |
| -4 | Capacity refusal |
| -5 | Closed or unavailable transferred bytes |
| -6 | Invalid chunk position |
| -7 | Incomplete transfer |
| -8 | Malformed JSON input |
| -9 | Physical stop or cleanup pending |
| -10 | Other typed Ledger refusal |
| -11 | Input, node or depth parsing budget exhausted |
| -12 | Invalid physical byte |

Usage exports return signed 64-bit byte counts, or -1 for a foreign instance.
The module's linear memory has a 16 MiB maximum. This bound and the transfer
pool's payload allowance are separate limits. Transfer accounting alone does
not account for parsed object metadata, the complete Wasm heap, Python retained
objects, DuckDB workspace or aggregate Local execution. A product Host must
reserve and account for those resources using their existing Owners before
claiming an aggregate execution bound.

## Execution boundary

The `actql_program_*` source-free preparation profile installs a trusted Check
Environment through its existing canonical-wire Owner. Its environment handle
holds the configuration's exact buffer borrow. `prepare` selects structured JSON
or an AQL string explicitly and invokes the common frontend and Checker. AQL
retains the lowerer's parsed Program and authored provenance. There is no syntax
fallback, fabricated parameter value or physical Source lookup.

A preparation handle is reserved and returned before invoking the Checker. It
retains the original input borrow, its environment handle and the Core's typed
success or rejection. An interrupted invocation remains reachable for cleanup
under the already-issued handle and is not silently repeated. -23 means the
invocation has no completed typed outcome. Environment close is pending while
any dependent preparation is retained. Preparation close returns its exact loan
only after the physical callback acknowledges stop. Rejected preparations have
the same custody obligations. Root close retains capacity while any loan or
cleanup remains pending.

The private `prepared_results` and `prepared_tasks` exports project inventory
only from a prepared Core value. -22 means that the retained typed preparation
has an error; it is not a public invalid/undetermined classification. -20 rejects
an installation configuration and -21 rejects an input of the wrong ABI kind.
The public diagnostic projection must use the retained Core reason rather than
infer a verdict from these readiness codes. This source-free profile supplies
no bindings and grants no Run admission, execution or Result access.

Run admission, checked task progress, publication, cancellation eligibility and
durable recovery remain MoonBit Owner responsibilities. Python provides physical
callbacks and persistence, not a second Run or recovery state machine. This
transfer facade provides no execution or recovery operation.
