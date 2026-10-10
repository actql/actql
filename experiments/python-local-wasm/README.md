# Python in-process Wasm feasibility probe

This separate experiment exercises a pinned, real MoonBit Wasm module from
Python without Node or CLI execution. It is not an embedded Client, public
Local provider, Scheduler, or Run service. Remote Client packages do not depend
on Wasmtime or DuckDB.

The primitive callback bridge schedules a Python async task, keeps input pending
until explicitly completed, transfers native DuckDB JSON through the existing
`source_value` and raw-data `canonical_json` owners, and returns a copied Python
value. Input/output buffers are bounded at 16 KiB, nesting at 32, and nodes at
1,024. Linear memory has a 16 MiB maximum; no borrowed view or opaque handle is
exported. Explicit release cancels pending callbacks, discards owned buffers,
and closes the Wasmtime Store. The probe delegates cancellation eligibility to
`run_publication_host.confirm_client_run_cancellation` with typed observations;
it neither accepts nor confirms cancellation of an actual Run.

The acceptance fixture independently checks decomposed Unicode keys and values,
CRLF, NULL, an absent field, repeated transfer ownership, pending callback
cancellation, and each missing cancellation prerequisite. Pending callback cancellation
happens before DuckDB opens a connection. A separate bounded native experiment
interrupts an active DuckDB worker, waits for its actual completion, and only
then closes the connection. This proves a physical adapter primitive, not
cancellation or restoration of an admitted Run. Durable admission and complete
accounting of live Core allocations remain subsequent ABI/Host work.

The existing `client_values_host_abi` is a JS-only foreign library using opaque
JS-owned values. Compiling portable Core packages does not make that Client ABI
available in Python. This experiment deliberately adds no alternate checking,
Run state machine, physical execution Owner, or compatibility fallback.

Build and consume this probe through `scripts/check-python-local-probe.mjs` with
`ACTQL_PYTHON_PROBE` pointing to an isolated Python environment containing the
pinned experimental build dependencies. The script selects only the fixture's
Wasm package, records module and source identities, builds an experimental wheel,
installs it into a new external venv, then executes `accept.py`. Do not publish
the experimental wheel or advertise it as Python Local support.
