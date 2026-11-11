# Original child Root custody

`Root::open_child_with_custody` is the child constructor for callers already
inside their original Native Domain read scope. It does not issue a domain,
adopt funding, or authorize a filesystem operation. The installed caller keeps
that same scope around the entire managed call, including encoding, diagnostics,
returned values and failure carriers.

A scoped child retains its own use of the parent's original read context before
acquisition. Both successful and failed constructor objects retain that use.
Closing the parent does not acknowledge the child, its Reader, or returned
managed aliases. Original child close releases its user only after that child's
physical acknowledgement; aliases still prevent context retirement. A foreign
current context or closed parent is refused before child acquisition.

The issue-only `Root::open_child` refuses scoped Roots. It cannot carry a failed
child and must not silently create an unselected Root/Reader. Existing
unselected callers retain their original behavior; the custody entrance also
supports them without claiming funding. Stock builds never create a scoped
child as a fallback.

As with the absolute Root constructor, the child starts with a confirmed
no-descriptor state and changes to open responsibility only when `openat`
succeeds. This state is established before the syscall, not inferred from a
negative descriptor after a close attempt. Unknown close remains sticky under
the original close Owner and cannot retry the raw FD.

## Child construction backing

`native_filesystem_read_layout` and `native_filesystem_write_layout` expose
only this compiled implementation's static payload and external-object header
sizes. They perform no filesystem operation and create no physical child. The
Writer borrows its original Root; its names, diagnostics, input bytes and any
co-held verification Reader need separate backing before their constructors.
Unsupported targets return no Native layout facts.

A positive diagnostic ceiling selected on the original Root also bounds its
Writer's construction, write, seal and cleanup details. The same limit bounds
the copied error bytes. Oversized detail is omitted without changing the typed
failure, original generation or pending cleanup. Omitting the Root ceiling
retains the existing unbounded diagnostic behavior and does not prove funding.

## Focused conformance

`child_custody_native_wbtest.mbt` checks the real typed unselected constructor,
absent-child cleanup, repeat cleanup and invalid names. The optional
`ACTQL_F_CALLER_CASES` branch of
`packages/python-local-runtime/native/pre-root/fixtures/scoped_read.c` adds
three actual child cases to the retained context/Root/Reader cases. Build it
against the output of the existing `prepare_scoped_read.py`, the matching
derived runtime objects and one original provider. Select both
`ACTQL_F_CALLER_CASES` and `ACTQL_ALIAS_CLEANUP_ENTRY`, and set `OWNED_SOURCE`
and `FILESYSTEM_SOURCE` to the exact selected source files. Its fixture directory
contains `sample` and `child/sample`, both with the independent bytes
`alpha\nbeta\n`. The test-only current-context projection uses that same
provider/TLS and supplies no installed funding or permission.

At source `18b473deb`, actual C conformance passed16/16 under non-Heavy60/TERM5,
cumulative child50, C11/O0 and the original64-page fixture. That run compiled
one fixture, linked one executable and reused five digest-checked matching
derived runtime objects. The typed Native2/2 and generated Native API were
checked against the preceding `23296c2b7` source; the child commit changes only
the C fixture's status oracle to the existing `Reader::next` contract
(`0 = chunk`, `1 = GenerationMismatch`). Earlier constructor, recipe-selection
and fixture failures remain separate evidence in workspace reviews under
`2026-10-10-python-client/scoped-child-custody`.

This conformance does not execute Native Host adoption/journal assembly, a
worker, Wasmtime, a new runtime DLL, or installed/public Python Local. Numerical
funding remains unadopted (`None`); fuel and capacity limits are unchanged.
