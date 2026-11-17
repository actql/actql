# Common Core Wasm ABI

The existing `client_host_wasm` MoonBit declarations and literal export map are
one scalar ABI authority for embedded Hosts. Its private ABI revision is
independent of the Client wire contract and package versions. A generated
signature is a declaration, not evidence that a compiled module or Host has
been admitted.

## Declaration authority and language projections

`scripts/generate-local-wasm-abi.py` reads the original MoonBit declarations
into a language-neutral model. It derives the Python binding, private C image
compiler header and `spec/contracts/core-wasm-abi.generated.json` from that
same model. `--check` checks every derived output without modifying it. A Host
binding must not recover the common contract by parsing another Host language's
output, or maintain a separate signature list.

The common projection preserves function names, scalar widths, argument order,
argument roles/units, import namespace and original declaration locations.
Unsupported syntax, unclassified roles, duplicate or missing exports, and
incomplete borrowed-buffer annotations refuse generation. Equal scalar widths
do not make argument roles interchangeable. Generation does not change the
original Core handle checks, resource accounting, authorization or lifecycle.

The two journal imports with byte-buffer payload offsets retain the original
whole-call borrow annotations. An offset is a bounded offset into the same
instance's linear memory, not a native pointer or transferable authority. A
physical Host copies or observes those bytes only while that synchronous borrow
is live, without guest reentry or an asynchronous suspension. Other scalar
handles keep their original instance and Owner validation.

A runtime artifact needs separate verification of its actual imports, exports,
memory shape, ABI revision, source/toolchain and artifact identity. Before
admission completes, instance initialization and start callbacks must not perform
business I/O. A declaration projection cannot establish execution, cancellation,
cleanup, platform support or normal distribution acceptance. Host-specific
physical resource and failure responsibilities remain with the corresponding
Host; common Run and recovery decisions remain in MoonBit.
