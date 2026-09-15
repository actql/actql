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
Internal task success is not publication of a successful Program or durable Run.

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

Node and workerd executions compare independent expected row content and content
CIDs. Distinct invocations need not have identical attempt, access or dispatch
evidence. Representative-input success does not establish deployed Workers CPU
or memory guarantees, Workers Wasm compatibility, or durable recovery. Execution
commands and tool pins belong in the [Workers guide](../../adapters/workers/README.md).
