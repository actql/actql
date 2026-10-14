# Private original backing-loan C transport

The signature authority is the actual regular C emitted at source
`67411824b9bc0414b98f38d3a8cf32bf8943f14d`, run-6xXQbc, SHA256
`5c3c5820cad4e89163cd8570401f812f3af7fb29cc51758fb71f8c7bfbecd3b0`.
Eight callback prototypes and their generated bodies were inspected: managed
Host/Loan/Reply inputs are borrowed; returned Reply and non-NULL Host/Loan/String
references are owned. Loan accessors incref Some; None is NULL. This qualification
does not apply to arbitrary MoonBit exports or a different generated module.

`backing_shim.h/c` stores only those code references, as the existing control shim
does. It neither issues a supplier nor creates a second physical provider/TLS,
Ledger, Root, Run, transfer or permission. A matching trusted installed component
must provide both registration entry points and the same original physical
provider. No generated struct fields are read and no nominal pointer is on wire.

Borrow/current/return invoke the existing Owner once and publish the owned typed
result into an empty caller-owned persistent slot. Transport status zero means
only that the result exists. It does not turn a typed refusal into success. A
foreign current/return keeps the true original loan and Host in that result.
The metadata accessor publishes the Host before acquiring the loan reference;
losing a later response cannot erase already-published custody.

Dropping a live-loan reply requires independently retained matching Host/loan
references. Clearing an owning loan reference requires the exact typed Return/Ok
result with matching Host/loan. That same proof can retire another data alias
without invoking return twice. After successful logical return, the proof reply
can be dropped without an independent loan reference. Logical return is not
physical stop, Host close, Run cancellation, Store commit or durable ACK. The
trusted physical adapter must stop its original use before requesting return.

Unknown retains its original slots and library; this layer has no retry or
exception classifier. It never calls a raw provider close or reacquires a lease.
The original Host remains responsible for full physical retirement and Resource
settlement, including ReadersPending and failed cleanup.

The thin Python borrower binds the same selected library as the original control
Host and retains that Host plus three owning C out-slots. All Python metadata
allocation happens before the first borrow call. Call scope and reentry reuse
the existing control custody checks. No method reports a physical stop:
`return_after_stop` is private and requires the trusted adapter to have stopped
the same use already. Known refusal and sticky Unknown keep their original
carrier; an Unknown return never invokes another return or acquires another loan.

Two additional C data-only helpers release captured owning references after
exact Return/Ok or Borrow/refusal-with-no-loan evidence. They do not perform
logical return, Host close or physical-provider cleanup. Slots are cleared before
their data decref. A lost response still reports Unknown in Python even if all
data slots were cleared; it does not acknowledge Host retirement. The original
Host and loaded component remain strongly retained by the same borrower.

Ten independent scalar Python fault/call-counter tests are provided. They are
not actual C/Core/physical conformance. The newly added data helpers have not
been compiled or executed merely by passing those Python doubles.

Four actual-Core C cases are prepared, not executed: pending Host close then
same-loan return; foreign refusal retaining true original custody; returned alias
refusing a second Owner return; occupied slots and live reply custody refusal.
They consume the unchanged 64-page supplier fixture and one initializer. There
is no mock provider, second capacity implementation, Engine, VM, worker, Run,
Store or wheel execution in this source unit. Native3 reply tests and Native4
original borrowing cases remain separate from these C cases.

The actual emitter completed three new build-package tasks plus link-core using
nine source-identical dependency packages from original run-pMBStt. Ordinary
unused-field and deprecated-Bytes warnings were retained. Compiler-only success
does not prove this new C shim compiled, linked or initialized. The next allocated
physical conformance must link this exact shim/header to that actual generated C
and the single existing provider, inspect dependencies, and verify original
RC/loan/close behavior. Python binding and installed-product integration follow;
100M fuel, 12Mi transfer, 16Mi VM and unknown bootstrap domains are unchanged.
