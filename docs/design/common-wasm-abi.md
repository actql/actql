# Common Core Wasm ABI

The existing `client_host_wasm` MoonBit declarations and literal export map are
one scalar ABI authority for embedded Hosts. Its private ABI revision is
independent of the Client wire contract and package versions. A generated
signature is a declaration, not evidence that a compiled module or Host has
been admitted.

## Declaration authority and language projections

`scripts/generate-local-wasm-abi.py` reads the original MoonBit declarations
into a language-neutral model. It derives the Python binding, private C image
compiler header, private typed Rust binding and
`spec/contracts/core-wasm-abi.generated.json` from that
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

## Rust admission and physical Host ownership

The generated Rust binding binds every original function with its scalar type
and every import through the same admission fence. The Rust runtime checks the
actual module rather than accepting the declaration manifest as proof. All
imported memories are refused and exactly one defined memory is required; a
second unexported memory cannot escape the selected artifact memory profile. Import
callbacks cannot reach the physical Host during start initialization or ABI
version validation. An unimplemented physical operation refuses explicitly.

Initialization failure retains and returns the same physical Host owner with
the original error, including failures after a guest Store was created. The
runtime has not admitted business I/O in that phase; freeing its guest Store
therefore does not silently discard a live physical child or acknowledge Host
cleanup. Normal execution, cancellation, post-trap cleanup and explicit shutdown
remain distinct operation/lifetime connections, not consequences of scalar
signature validation.

## Bounded Rust transfers

The internal Rust adapter uses the existing original-input block copy and
same-instance memory read. It reserves under the existing Buffer Owner, retains
the original input/instance association and copies at most 16 KiB at a time.
Raw offsets and borrowed guest slices do not leave the synchronous Store scope.
No scalar fallback, user callback, guest reentry or asynchronous suspension is
inserted between obtaining an output offset and copying that block.

Compiled code is immutable reusable runtime material. Sharing it does not share
a Store, guest memory, physical Host, nonce or buffer holding. Equal numeric
handles in another instance do not supply the original association. Pending
cleanup retains the same holding; explicit Core success is required before the
adapter marks its input binding closed. These mechanisms do not issue a Run,
Source permission or substitute physical cleanup facts.

## Rust source responsibility coverage

The selected Rust CI job uses Cargo metadata to choose its actual library and
tooling entrances. A small private `syn` reader follows their source modules
and derives argument roles, type declarations, imports and exports. It does not
execute product modules, infer business decisions or define another ABI table.
Documentation and function bodies are not frozen as type signatures; unknown
item macros, ambiguous mounts and outside-root modules refuse source coverage.

The existing interface Owner checker validates these actual source facts and
all ten responsibility references. The Rust generated binding also passes its
original generator's read-only freshness check. This is source responsibility
coverage, separately from actual Cargo type checking, artifact identity,
compiled Wasm admission and Host/Run lifecycle acceptance. Tooling process
bounds and cancellation remain with the existing verification supervisor; the
source reader owns no business resource, permission or cleanup acknowledgment.

## Failed-instance invocation fence

The Rust instance keeps its Store, functions and memory private. Ordinary calls
enter one gate which disables normal work before guest entry and restores it
only after a successful raw invocation. A Wasmtime error or Rust unwinding
therefore leaves the same instance cleanup-only. An ordinary scalar Core refusal
is not a hard trap: its original code remains available to its original caller.
Invalid input rejected before guest entry likewise does not become a trap.

A failed instance cannot receive another normal fuel allowance. Explicit finite
cleanup funding can run only ABI-owned typed close/cleanup observation routes;
it never resets normal availability. Pending cleanup and repeated close errors
retain the same input and physical Host. Completing logical transfer-pool close
does not restore the instance or acknowledge asynchronous Host retirement.

This fence is a physical invocation rule, not another Run state machine. The
public runtime must retain its original owner under a supervisor through stop,
cleanup and actual retirement; dropping a private buffer or instance does not
supply that public lifecycle. Cancellation notification and physical I/O stop
remain separate from guest interruption and must not wait on a guest lock.
