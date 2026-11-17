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

## Retained Rust cleanup worker

The private retirement supervisor takes the same Core, physical Host and input
owners. A bounded one-entry notification channel wakes its cleanup worker
without taking a Store lock. The worker attempts only the original typed
cleanup routes under the caller's explicit finite cleanup budget. Pending or
failed cleanup retains those owners; it neither spins nor starts replacement
business work. A later physical notification can retry that same cleanup.

The original primary error is retained as the same shared error object. Cleanup
status is a closed category, with no diagnostic text. Original cleanup errors
and panic payloads are held opaquely until actual retirement; the first of each
is observed separately from the primary. The critical path never calls their
Display/Debug/Clone or discards a secondary failure while custody is pending.
Later pending or complete observations cannot overwrite the first causes.
Spawn/validation failure returns the same resources. Callback unwinding is
caught around cleanup while the retained resource remains owned.

Dropping the supervisor only queues a retirement request. The worker keeps its
original resources even after ordinary handles disappear. Core completion is
reported only after the original input and pool close return success; explicit
join then waits for that same worker. No wake, Drop, empty worker map or detached
thread is a Run cancellation result, physical cleanup ACK or public Receipt.
Progress observers retain only observations, not the Core. A same-supervisor
strong custody reference is established before worker creation and released only
after actual Core close succeeds. Unexpected worker exit cannot make the last
ordinary handle release a still-pending Core. No formatter or payload destructor
can serve as an implicit retirement path.

This component still requires the public runtime's actual resource admission,
physical stop notification, same-parent cleanup holding and Run control binding.
Its finite diagnostic budget is DATA, not a new allowance or authorization.
Opaque failure holdings also remain part of that future public retention
accounting; this private component does not establish normal funding for them.

Failure custody is finite even in this private component. The caller supplies
an explicit positive slot count. The constructor allocates and initializes that
fixed array before creating a worker; allocation refusal returns the original
Core and inputs. Each cleanup attempt reserves a free slot before fuel reset or
guest entry. A scalar pending/success frees only that unused reservation; an
original error or panic occupies its slot until actual Core cleanup succeeds.
The array never grows and no earlier opaque original is discarded for a retry.

With no free slot, the supervisor reports `RetentionFull` and invokes no cleanup,
even if physical cleanup has become ready. This is an explicit terminal pending
state, not completion or permission to reopen/reissue. A later funded recovery
owner is not supplied by this component. Unexpected worker exit is caught by a
separate outer boundary and uses fixed, pre-established worker/join unwind
cells. Its original payload and first causes remain retained, its failure is
observable, and joining cannot report success for that pending state.
