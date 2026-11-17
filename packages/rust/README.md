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

Raw Wasmtime errors and callback unwinding now fence the same instance to typed
cleanup/inspection routes. Normal fuel cannot be replenished after that fence;
ordinary negative Core status codes remain distinct. Actual fuel-trap and
callback-unwind controls retain their original input and exercise pending then
successful cleanup. This remains an internal invocation layer: the public
supervisor/retirement owner and Run cancellation are not supplied by this flag.

The private retirement component now keeps the same Core/Host/input owners in
a cleanup worker. Pending/error survives ordinary handle Drop, its bounded
notification does not wait on the Store, and the original primary error and
first cleanup cause remain separate. Actual Core close precedes worker join.
This is physical component coverage, not public shutdown/cancellation or normal
resource admission. No public Run outcome or cleanup Receipt follows from a
notification, Drop or detached thread.

Cleanup progress uses bounded categories. The critical path does not format or
clone user error/panic text, and retains their opaque originals through pending
custody. Observation handles do not retain Core themselves; the supervisor's
explicit strong custody reference is released only after actual Core cleanup.
The new error/payload controls cover a user Display that panics and a panic
payload whose destructor records premature release. This remains private
component coverage, with public failure-retention funding still unqualified.

Failure slots are explicitly bounded by the caller and allocated before worker
creation. Cleanup reserves one before guest entry; exhausted custody reports
terminal pending without another guest call or discarding an original. An
unexpected worker exit remains a retained, observable failure. This finite
component does not claim a public recovery path for exhausted custody.
