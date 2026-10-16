# Portable execution boundary

The portable Core owns checked meaning, lowering, candidate validation and cost
composition, fixed-input computation, and the owned reservation, completion and
recovery state machines. It does not own environment access. Host, Connector and
Store implementations drive authorized I/O and return facts through those common
contracts. An abstract port is permitted in Core; a concrete filesystem, network,
SDK session or Cloudflare binding is not.

The explicit Core roots are `program_check`, `lowering_relation`,
`execution_relation`, `query_planning`, `connector_sdk`, `physical_strategy` and
`physical_host`. Their production dependency closure is separate from test
imports and from concrete Connector composition. The dependency inspection is
conservative: unrecognized manifest directives or unreviewed external packages
are errors rather than silently ignored edges. Three-target isolated compilation
and generated-artifact inspection complement source inspection; none alone is
proof of environment compatibility.

Implicit prelude and builtin imports are part of the external closure. A pinned
per-package source inventory covers them as well as explicit imports; unknown
packages and changed sources fail closed. Auditing a runtime support package is
not permission for arbitrary ambient operations. Source restrictions and the
reachable generated-code gate remain separate requirements.

## Composition and Host lifetime

Node and Workers use the same JavaScript strategy coordinator under
`adapters/host-common`. It calls implementations by their exact opaque
registration, not by provider names, and checks retained Core completion before
reporting a task's success. Installed callbacks cannot manufacture completion by
resolving a Promise. Core remains the reservation and publication authority.

The Workers profile selects Local in the declarative build-time assembly before
resolving Connector modules. The profile does not import every Connector and
depend on dead-code elimination to remove unused Node dependencies. Local remains
a concrete Connector outside Core. A different supported module set requires a
different generated composition, not a new checker or planner.

The thin Workers Host is invocation-scoped. A scoped consumer can use completed
outputs while the Host owns them. Returning from consumption triggers output
close and cleanup; a failed close does not erase recovery responsibility. A
cleanup handle describes unresolved recovery, not a lease authorizing a future
request. Cross-request handles, durable capture and Store are separate contracts.
Cancellation is rechecked after every asynchronous preparation boundary and
before dispatch. It prevents further normal preparation and unstarted work;
cleanup remains mandatory. It does not imply synchronous-kernel preemption.
Internal task success is not publication of a successful Program or durable Run.

Application preparation and generated Host operations share one linked MoonBit
runtime instance per invocation. Opaque handles and generated exception tags are
not a cross-link-unit ABI. The reusable JavaScript Host binds a frozen view of
that trusted runtime's exports; ordinary request data cannot replace them.

An asynchronous Connector retains its own pending transport state while the
common Core owns reservation and completion. A cancellation request does not
prove stopping. Failed stop or cleanup keeps recovery responsibility and reserved
capacity until confirmation; neither Promise resolution nor an absent rejection
payload can manufacture a retained successful output. Test-only asynchronous
composition exercises this boundary without adding I/O to the Local product
profile.

## Language bindings and artifact correspondence

Existing contracts and owner declarations define an operation. Generated
bindings project its named arguments, units, scalar widths, result shape and
calling convention into the consuming language. The actual compiled exports,
imports, memory conditions and consuming wrapper must agree with that
declaration. Comparing generated sources alone does not admit an unrelated
runtime artifact.

The [private JavaScript compiler binding](../development/js-compiler-bindings.md)
isolates the selected compiler's Result, Option and tuple layouts in one
template, with generated copies where packages install independently. Product
consumers use those projections rather than reading compiler fields directly.
Option representation is qualified by the actual export; a specialized probe
does not establish a universal boxed or unboxed layout. Action projections read
the existing MoonBit owner's closed mapping and name its decision; they do not
maintain another lifecycle or permission table.

The [Python Local boundary](python-local-abi.md) covers Wasm declarations,
original C/ctypes transport, memory/Rust forwarding and selected DuckDB layouts.
Names and units remain significant when scalar types match. A matching C or
Wasm function type alone cannot distinguish reversed argument roles. Binding
fingerprints identify a physical declaration; original library selection,
current authority and same-owner custody remain separate checks.

Conversion does not settle a Store attempt, acknowledge a physical stop,
release a holding or permit replay. A refusal, an uncertain outcome and pending
cleanup retain their existing meanings and original handles. The selected
Host's existing reservation, physical-limit and trusted-runtime contract must
cover borrowed buffers, native allocations, callbacks and overlapping copies
for their actual lifetime; identical content does not merge reservations. The
[public wire codec](public-wire-codecs.md) instead validates received DATA from
registered schemas and does not require a full execution engine for Remote.

Public wire versions, private ABI versions, package releases and toolchain pins
are independent. A selected distribution must still bind source, generator,
contract, wrapper, public types and actual runtime artifacts coherently. Cloud
consumers use the types from their actually adopted packages. Recovery returns
to the original Run's retained identities, rather than substituting the latest
installation or current build.

The [interface inventory](../development/interface-inventory.md) discovers
entrances and their resolved source/artifact dependencies. Existing generation
checks, actual target probes, independent behavior vectors and intentional
mutations complement that coverage. A source inventory or component test does
not establish an installed product profile; the
[runtime artifact rules](../development.md#runtime-package-artifacts) retain
their normal packaging and exact-artifact acceptance requirements.

## Pinned runtime initialization

The selected MoonBit JS builtin uses ambient entropy to initialize its physical
hash-table seed. This is an implicit runtime dependency, even when application
packages contain no FFI. A module loaded by workerd cannot perform that request-
scoped operation during initialization.

The Workers build therefore makes that one audited initialization an explicit
signed-32-bit Host input. It checks the exact generated declaration digest,
replaces only its seed acquisition, and wraps module initialization in an
instance factory. Changed toolchain output requires review. Global polyfills,
mutating the installed toolchain and hiding arbitrary FFI are not alternatives.
The resulting runtime is also inspected for additional imports and ambient I/O.

This physical seed is not canonical identity, an authorization token or an
observation identifier. Canonical hashing is unchanged. The Host may supply
entropy through an authorized environment operation; a fixed public seed must
not be represented as adversarial hash-flood protection. Seed changes must
preserve logical values, order, failure rules and logical accounting.

## Evidence and limits

The workerd profile explicitly disables Node compatibility. Its resolved module
graph is checked as well as emitted code, so an unused forbidden import is still
a violation. Tests deny external traffic at the runtime boundary; normal Host
I/O outside Core is not prohibited by this rule. Dependency and I/O injection
tests check the guards' detection behavior, not isolation of malicious plugin
code inside the same process.
Runtime finalization independently audits every outbound attempt, including
attempts whose failure the Worker catches. Phase-port spies and this ambient-I/O
audit cover different bypass paths; denying the network alone is not proof that
no I/O was attempted.

Node and workerd executions compare independent expected row content and content
CIDs. Distinct invocations need not have identical attempt, access or dispatch
evidence. Representative-input success does not establish deployed Workers CPU
or memory guarantees, Workers Wasm compatibility, or durable recovery. Execution
commands and tool pins belong in the [Workers guide](../../adapters/workers/README.md).
