# Bounded helper call boundaries

The bounded Session, kernel, managed record storage and retained-output owners
keep their existing responsibilities. Shared helpers do not create a second
execution context or resource ledger.

## Caller workspace is an explicit decision

`managed_record_runtime.start_record_append` and
`managed_record_storage.start_append` require the labeled
`external_workspace_slots` argument. Callers compiled against the earlier
optional argument must now supply it. This is a MoonBit source-compatibility
change; it changes no wire schema, canonical identity or contract version.

The argument reserves caller-owned scratch that remains live while the child
append advances. The storage owner already accounts for the append cursor,
its dynamically growing continuations and retained output records. Do not add
those child-owned quantities to the caller argument a second time. An earlier
comparison of a combined workspace estimate against a limit does not transfer
that reservation to the child.

A caller with no enclosing kernel scratch sharing the storage limit may
explicitly pass zero. Standalone storage-owner tests use that scope. Executing
kernels must carry their independently justified reservation through the whole
append lifetime, including failure and cancellation before confirmed cleanup.
The compiler catches omitted arguments; it does not prove that an explicitly
supplied amount is sufficient.

## Eager and incremental sorter admission remain distinct

`bounded_tuple_sort.prepare` retains its synchronous all-key shape validation
and error timing. `prepare_deferred` retains pending shape validation in the
charged initialization steps. Completion, not preparation alone, establishes
a valid sorted index.

Production consumers use the deferred entry point. The existing resource
accounting gate rejects eager `prepare` references using each consumer's
actual package alias, including references saved as function values. It
discovers new importing packages as part of the source snapshot. Test code
may still exercise both public APIs and their distinct admission behavior.

This source restriction prevents accidental selection of the eager helper.
It is not a proof that all computation is bounded or a sandbox against
deliberately obscured source. Existing work, cancellation, cleanup and
independent boundary tests remain necessary.
