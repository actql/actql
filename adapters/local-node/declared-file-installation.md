# Declared-file installation inventory

## Responsibility

`declared-file-installation.mjs` admits a generic file-backed implementation
through the normal installed connector table. It selects and checks the actual
source or effect module, retains its runtime identity in the existing Host
services, and begins the existing Source initialization context before native
declarations, exported environments or Mappings are constructed. It calls the
normal Row Source and Row Effect factories. It does not interpret business
models, parse sample rows, grant Account authority, issue read or write grants,
or replace the Common semantic owners.

## Inputs and outputs

`createDeclaredFileInstallationInventory` receives the original runtime,
admitted Project, already-created Host services, selected base Environment wire,
runtime URL and synchronous currentness check. `begin` receives that Project's
original connection collection, an in-range connection index and either the
`source` or `effect` role. It returns one original member per connection/index/
role, with its checked identities and the actual Source initialization context.

A source member's `prepareNativeDeclaration` forwards the caller's complete
native projection envelope to the existing context. Its `capacity` and `project`
operations must describe and construct all original logical and physical
results, including intermediate restoration overlap. An effect member borrows
that exact source member's prepared declaration and prepares its own checked
Mappings. `load` accepts the existing physical factory options, injects the
retained originals and rejects attempts to replace them. It returns the actual
registered adapter, not a descriptor standing in for a completed factory.
`cleanup` retains a settled unsuccessful member's original cleanup obligation.
Use inventory `fail` for cancellation while construction is pending: it closes
admission and joins retained work before cleanup.

## Identity

The logical `connectorId` is the exact configured connection name. The
configured provider is separate `providerNamespace` DATA; two connections to
the same provider do not share a Catalog or SourceRef namespace. The actual
supplier registration is `declared_file` with revision `declared_file/0.1`.
Neither the connection name nor a configured provider label selects authority.

The nominal Project registry, actual table entry, role-specific frozen profile,
original connection collection and index identify admission. The runtime CID is
read once through the existing installed runtime-identity reader and retained
against the actual admitted entry. Member copies cannot borrow declarations.
The underlying context also checks the same original Host services, material,
installation, connector and base Environment before borrowing. Equal serialized
values, copied context objects and matching provider labels are insufficient.

## Ownership

The existing Host services own the initial Source material and reservation
successor. The inventory retains every begun context before further preparation,
including contexts whose projection or factory later fails. Source declaration
originals remain with that material; an effect holds a checked reference to the
same declaration rather than restoring another one. Each context owns its own
prepared exported Environment and, when applicable, Mappings.

After physical construction, the actual registered Row adapter owns its Site
and reader cleanup. Failed installation uses the existing retained Host failure
carrier and finishes the exact original context once. A physical Site acquired
before an adapter registers remains the acquiring physical installer's duty;
this inventory does not acknowledge that Site's cleanup merely because its
factory rejected. Successful adapters retain their ordinary lifetime and must
close through their existing owner before the material can retire.

## Synchronization

Connection methods and the nominal Project original are captured when the
inventory is created. Admission checks currentness around module loading,
identity projection and the one shared runtime-identity flight. Repeated
`begin` calls reuse the same original promise, including a failed promise.

The begin flight is retained before module callbacks run. A member marks its
single load attempt and retains its promise before invoking option accessors or
the actual factory. Inventory failure prevents new admission and awaits both
begin and load flights before finishing unfinished contexts. The factory's own
failure handler cleans only its member; it never awaits the inventory cleanup
that is joining that same factory. This avoids a self-wait while preserving the
pending constructor's claim on the original material. Preparation is delegated
to the existing context's synchronous reservation-before-construction methods.

## Failure

Malformed profiles, foreign Project/connection/context originals, replacement
prepared values, out-of-range connections, unsupported roles and unavailable
runtime methods refuse. Reservation refusal precedes the corresponding native,
Environment or Mapping constructor. A failed preparation or load is not retried
with another declaration, runtime read, Root or capacity source. Earlier contexts
remain retained for the same failure cleanup path.

`retainBoundInstalledSourceFailure` preserves the primary failure and original
physical cleanup carrier. A thrown or false physical close is not a successful
cleanup acknowledgement. The existing Source-material owner decides whether
retirement is complete; table admission, a runtime CID and successful metadata
preparation do not establish physical closure.

## Cancellation

There is no independent AbortSignal or transport-cancellation protocol here.
Inventory `fail` closes admission immediately and joins existing constructor
work. A constructor may finish its own asynchronous step before its currentness
check refuses; its original adapter is retained before that check so cleanup can
reach the same physical owner. Joining a rejected promise is not evidence that
a pre-adapter Site or an external transport stopped. Such obligations remain
with the original acquiring owner and retained failure carrier.

## Resources

All admission and preparation use the already-selected Host services and the
same initial Source material. No new Root, late capacity source or fabricated
selected installation is created. The normal runtime reader owns its file
handle, bytes, hash and close. The native projection supplier must provide the
actual complete typed construction quantity before any native constructor;
this inventory has no guessed numeric fallback or independent quantity model.
Borrowing retains the source's same declaration capability while the effect
funds its own Environment and Mappings through the existing context.

Connection admission is bounded by the original collection's count and the
existing maximum of 128. Singleflight prevents duplicate runtime reads and
construction attempts; it is not a substitute for actual capacity reservation.
Pending construction and pending physical cleanup keep the original material
live until their existing owner can acknowledge retirement.

## Extension

The registered implementation is generic and the profile contains only the
connection name, configured provider namespace and role version. New physical
formats or schema projections belong to their existing model/Common owners.
Additional source/effect behavior must retain this nominal admission path,
reservation-before-construction order, original identity checks and physical
cleanup ownership. Adding a profile name, a mock flag or a business-specific
connection label cannot authorize reads, dispatch or a new installation path.

## Verification

`declared-file-installation.test.mjs` exercises the actual nominal table,
Project registry, initialization context, runtime file/hash path, Environment
preparation and Row Source/Effect JavaScript factories. It covers shared
original declarations, distinct same-provider connection namespaces, copied and
foreign contexts, pre-constructor reservation refusal, exactly-once attempts,
earlier-context cleanup, detached originals, runtime reservation failure,
currentness failure, pending physical close and reentrant cancellation inside
the actual Effect factory before its asynchronous ledger creation. The latter
checks that the constructor settles and its registered Site closes before the
initial material retires.

These are component tests. Their Common semantic/resource ports and typed
quantity are explicit fixtures, and no Account grant, Source request or Effect
send occurs. They do not establish production native quantity sufficiency,
Common compiler semantics, integrated read/Content/Effect execution, cross-target
coverage or normal workflow acceptance. The embedded startup identity tests
separately check the retained initialization ordering and original profiles.
