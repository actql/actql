# Original parent read custody

This private installed caller connects the existing parent physical read
context to the Common backed original child Ledger. It does not select an
installed profile, authenticate a cohort, or provide missing process funding.

The trusted caller prepares and transfers one original domain and its physical
read context before `prepare_domain_original_read`. The explicit budget is a
declaration within the existing child allowance. The first reservation is the
bootstrap census, followed by an owned workspace, the recorded descriptor and
the independently reserved read. A second purpose, including SQLite, cannot
reuse that domain. The worker/channel entry still excludes a parent context.

`InstalledArenaOriginalRead` joins all original references. Consumers borrow
its pair and workspace together and retain the same carrier until Root,
Reader, returned managed Bytes and partial failure aliases retire. They recheck
the original after awaits and physical operations. No raw Ledger or independent
pair, loan, callback or cleanup Boolean is accepted from Python.

Cleanup requests logical stop without releasing backing. The original C
context must confirm actual scope/user/last-alias retirement before workspace,
read and census settlement. A pending Common use return is distinct from C
retirement: retry never repeats a confirmed physical close. Cumulative actual
child usage is reported before the original live access is retired; uncertainty
retains its same frame and responsibility. Domain, outer view, FD and backing
retirement remain separate. Closed registration is cut only at the final domain
ACK, preserving the one-attempt tombstone until then.

The matching `installed_original_read_conformance` executable uses a fresh
disposable 64-page FD, a 48-page domain and the selected derived scoped runtime.
Its declaration and alias test are diagnostic inputs, not adopted normal byte
quantities. Ordinary funding remains unavailable. This is neither Wasmtime,
worker startup, Store ACK, installed-wheel acceptance nor public Run recovery.
