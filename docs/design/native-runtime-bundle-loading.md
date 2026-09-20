# Native runtime bundle loading

## Status

Accepted for the first native Remote Site profile.

## Context

Remote dispatch is authorized for an exact runtime bundle, Connector
registration, Site generation, and task occurrence. The physical runtime must
therefore execute the component that was admitted, installed, verified, and
activated for that bundle. Merely checking an active bundle CID while invoking
an unrelated callback does not establish that binding.

The MoonBit native backend currently cannot emit a `foreign_library` package
as a linkable shared-library artifact. A design based on loading MoonBit
Connector implementations with `dlopen` would consequently require a second
implementation language or unsupported toolchain behavior. That would work
against the requirement that Connector and Host product logic have one
MoonBit owner. This limitation is documented by the MoonBit FFI reference.

## Decision

The first native runtime bundle component is a complete, statically linked
Site executable.

- Connector implementations and their exact executable task registry are
  linked into the component.
- The bundle manifest identifies the complete component bytes, target triple,
  Connector registration, Connector revision, and strategy revision.
- A supervisor verifies and activates the component before starting it. The
  new process starts a new Site generation and proves that its loaded
  component matches the active bundle before accepting dispatch.
- Activation does not mutate a running process. Existing attempts retain the
  old executable and bundle holding while that Site generation drains.
- Rollback starts another new Site generation from a previously verified
  component. It does not revive authority from an old generation.
- The Site executable uses the portable MoonBit runtime, journal, completion,
  retention, and cleanup progression. Environment adapters only launch the
  process and observe its physical exit and resources.

Runtime bundle transport and storage remain implementation details. An OCI
artifact may carry the executable, but OCI is not part of ActQL identity and
is not required by the execution protocol.

## Loaded-component binding

The bootstrap boundary must produce a binding between:

- the exact active runtime bundle CID;
- the component CID and target triple admitted by that bundle;
- the current Site key and newly allocated Site generation; and
- the exact Connector and strategy revisions exposed by the executable.

The remote runtime accepts registrations only through this binding. A caller
cannot turn an installed but inactive bundle, a different component, or a
component for another target into dispatch authority by supplying a matching
string.

The component also exposes its exact executable task registry. Dispatch still
checks the Run Definition and task key before durable acceptance. A runtime
bundle is not authority to execute arbitrary tasks for its Connector.

## Update sequence

The standard update sequence is:

1. stream and verify the signed bundle component;
2. install and durably record its exact generation;
3. activate it with a conditional catalog update;
4. start the component as a new Site generation;
5. verify the loaded-component binding before advertisement;
6. stop new admission to the old generation and drain its existing attempts;
7. reclaim the old component only after its execution, reader, and cleanup
   holdings have all been released.

Crashes between these steps leave either the old generation authoritative or
the new generation unadvertised. They never make two generations share one
execution authority.

## Rejected alternatives

### MoonBit shared-library plugins

Rejected for the initial profile because the native backend does not provide a
supported linkable foreign-library artifact. This can be reconsidered if the
toolchain gains a stable native library ABI.

### A handwritten Connector plugin ABI

Rejected because it would move Connector execution and lifecycle decisions to
a second implementation and make native, JavaScript, and Wasm behavior diverge.

### Treating installation as loading

Rejected because verified bytes on disk do not prove that the running process
uses those bytes. Installation, activation, process start, loaded-component
binding, and dispatch admission remain separate facts.

## Acceptance evidence

The native Remote Site milestone must demonstrate all of the following:

- a component mismatch is rejected before durable dispatch acceptance;
- an inactive or draining bundle cannot authorize a new dispatch;
- update and rollback allocate new Site generations;
- an old attempt continues with its old executable and holdings while draining;
- restart never restores execution authority from the previous generation;
- the Node-free Local and DuckDB paths run through the loaded component; and
- separated-network tests use the same executable and bundle lifecycle as the
  standard native entrypoint.

## References

- [MoonBit Foreign Function Interface][moonbit-ffi]

[moonbit-ffi]: https://docs.moonbitlang.com/en/latest/language/ffi.html
