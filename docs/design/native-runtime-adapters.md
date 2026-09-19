# Native runtime adapter boundary

## Purpose

The native runtime provides the same ActQL decisions as the JavaScript and
WebAssembly targets without requiring Node.js during startup, execution,
publication, delivery, or cleanup. Native adapters do not own language or Host
semantics. They perform physical operations selected and admitted by the
portable MoonBit control plane.

## Responsibility split

MoonBit owns:

- Connector capability and revision admission;
- exact task, attempt, material, and Site binding;
- query construction and result-shape requirements;
- capacity reservation and transfer charging decisions;
- completion, retry, reconciliation, retention, and reclamation progression;
- logical identity and publication contracts.

Native adapters own:

- loading an explicitly selected native library;
- opening, operating, stopping, and closing native resources;
- bounded exchange of physical batches and measurements;
- reporting physical errors and observed stop or cleanup facts.

An adapter may maintain physical state needed to operate a library. It must not
independently decide whether an ActQL attempt may be retried, completed, or
released.

## DuckDB integration

The native DuckDB adapter uses the official DuckDB C API through a thin
MoonBit C FFI. It does not invoke the DuckDB command-line program or a Node.js
subprocess. The generated C header is pinned with its upstream license under
`vendor/duckdb`.

The runtime library is loaded from an explicit path. The Host installation
must bind that path to the admitted runtime bundle and verify its revision and
integrity before the adapter can receive execution authority. Discovery of an
arbitrary library from a process search path is not an admission mechanism.

Opaque MoonBit handles own native resources. Database handles retain their
library handle, explicit close is idempotent, and automatic finalization is a
last-resort resource safeguard. ActQL settlement still requires an observed
operation outcome; garbage collection is not settlement evidence.

Dynamic loading keeps the portable MoonBit packages and unrelated native tests
independent of a locally installed DuckDB library. A packaged native Host must
ship or require a compatible, verified DuckDB shared library as part of its
runtime bundle.

## Supported native profiles

The initial native product profiles are:

- macOS on arm64; and
- Linux on x86-64.

Both profiles use the same MoonBit control logic. Platform-specific code is
limited to physical adapter operations. A target is not supported merely
because portable packages compile for it; the standard execution,
publication, restart retrieval, delivery, and cleanup paths must pass on that
target without spawning Node.js.

Additional operating systems require a physical loader, filesystem durability,
and native dependency packaging implementation with the same contract. They do
not require a second Host state machine.

## Data boundary

The scalar query entry point is only the native library integration slice. The
standard execution path must use bounded batch or column transfer and must not
turn the FFI into a per-cell application ABI. Physical result integrity and
logical relation identity remain separate obligations.

The native adapter must reject unsupported physical types or result shapes
before common completion. It must not repair values, reorder rows, or infer a
logical identity from a physical digest.

## Selected dependencies

- MoonBit native FFI and C stubs provide the language boundary.
- The DuckDB C API provides database execution.
- Operating-system filesystem primitives provide the local durable Store
  adapter, with durability claims limited to the selected filesystem profile.
- SQLite remains the first candidate for native durable journals. Its
  transaction and crash behavior must be verified by an integration slice
  before it is selected for the product journal.

TLS, HTTP, cryptography, and SQLite should use maintained libraries behind thin
physical adapters. ActQL-specific identities and state transitions must remain
independent of their transport encodings.
