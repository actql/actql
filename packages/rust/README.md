# ActQL Rust embedding implementation

This package is the Rust embedding implementation of the shared Core Wasm ABI.
The private scalar binding is generated from the original MoonBit declarations
by `scripts/generate-local-wasm-abi.py`; it is not a separate language semantics
or authorization implementation.

The current internal admission boundary checks the selected artifact digest,
actual complete imports/exports, total memory count and selected memory profile, typed functions and actual
ABI version. Every physical callback remains closed during instance/start
initialization and version validation. Missing physical callbacks return an
error rather than a successful stub. Initialization failure returns the same
physical Host owner and original cause; dropping the guest Store is not an
asynchronous Host cleanup acknowledgment.

This first boundary is implementation material. It does not yet expose the
planned public prepare/bind/execute, bounded Result, cancel/lookup and shutdown
API, and does not establish normal crate/Host distribution acceptance.
`publish = false` prevents accidental registry publication during development.

The focused component test requires `ACTQL_CORE_WASM` to name the actual
compiler-produced Core module. Absence refuses the test rather than skipping it
or substituting a synthetic module. Synthetic complete modules in the other
cases are only negative probes for initialization I/O and admission failures.

The declared Rust MSRV 1.88 is not yet independently qualified. The current
component checks use the repository-pinned Rust 1.90 toolchain.

The internal transfer adapter uses the existing `fill_block`/`read_block` ABI
with at most 16 KiB per copy. A returned guest offset never escapes the immediate
same-Store copy. Input handles keep an instance association separately from
equal numeric routing data; failed/pending cleanup keeps that same binding.
Compiled code may be reused, while each instance has its own Store, memory,
physical Host and admission fence.

The transfer component includes an actual Core AQL preparation consumer. Its
scalar diagnostic pools are not normal Host/Run admission. They select the
existing finite 1B bootstrap and one 32B operation scope explicitly; this is not
an unmetered test or evidence of default-budget public execution. Cleanup,
foreign-instance and short-copy controls retain their own actual outcomes.
