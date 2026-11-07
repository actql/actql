# Source declaration and Mapping continuations

## Responsibility

The existing installed Source initializer owns these continuations. An Effect
may borrow an already prepared immutable native declaration from a Source on
that same initializer. CREATE and UPDATE Mapping construction remain separate
closed Common operations under the same initializer reservation. Before any
connection context exists, the configuration reader can reserve a pure native
metadata projection through this same original material; it does not invent a
connection or begin a second initialization.

## Inputs and outputs

`prepareBorrowedDeclaration` receives the actual Source context and returns its
exact prepared tuple. `prepareMappings` consumes frozen write descriptors and
their original wire. A descriptor's optional `operation` is `create` by default
or explicitly `update`; unknown operations refuse. `rowSourceMapping` dispatches
to the corresponding Common constructor and projects its existing metadata.
The configuration reader's `prepareNativeInput` takes an exact synchronous
capacity/project pair. Its strict `readUtf8` retains the existing bounded file
and decode custody. Native declaration preparation returns its already-owned
export as `wire`, so consumers do not serialize the declaration again.

An Effect's native Mapping projection needs its already-produced declaration
CID. The context therefore admits native input after that exact declaration,
until any Mapping, Command or provider-driver attempt begins. This does not
open Source post-declaration input or a published Environment-only holder.

## Identity

Borrowing requires the same original material, service, installation entry,
connector identity and base Environment. Copied contexts and equal declaration
bytes do not substitute for those originals. Metadata projections check the
actual configuration-reader receiver and original material, including after the
reservation callback; copied readers do not gain a construction entrance. A configured provider name does
not replace a connection namespace. UPDATE's schema and target identity come
from the retained declaration, not a repeated caller-supplied field schema.

## Ownership

The Source context and its native construction quantity remain retained by the
same material. Borrowing adds no declaration restoration, execution owner or
physical grant. The Effect context owns its subsequent Mapping and Environment
construction. Existing actual Row factories register their exact prepared
objects; finishing a metadata-only holder is not successful installation.

## Synchronization

Each declaration and Mapping attempt is recorded before the original reservation
callback. Original currentness and context state are rechecked after that
callback. Constructors are synchronous; reentry, replacement or repeated attempts
refuse. Metadata projection attempts are recorded by exact projection identity
before callbacks. Promise-returning constructors retain their unsettled cleanup
obligation and cannot be mistaken for synchronous completion. Reading an
optional operation never invokes an inherited getter.

Post-declaration native input pins the original prepared tuple before entering
the shared input owner. Every reserve, projection and retained-only completion
fence requires that same tuple and the still-unstarted Effect phase. A callback
cannot replace the tuple, finalize its Mapping or begin a driver and continue
the old projection. Exact projection attempts remain once-only.

## Failure

Reservation refusal occurs before the corresponding constructor. A failed
attempt stays spent and its constructor extent remains with the initializer.
Invalid or unknown Mapping data never falls back from UPDATE to CREATE.

## Cancellation

Cancellation follows the same initializer and actual adapter cleanup. Borrowing
is not cleanup acknowledgement. A pending physical close retains the original
material; the inventory joins its in-flight constructors before finishing failed
contexts, without restarting or resending anything.

## Resources

Borrowing stores references to the existing prepared tuple in existing contexts;
it does not copy or reconstruct the declaration. Both contexts are already
retained in the same material. Mapping construction uses the existing reserved
Mapping/Environment geometry before calling Common. These continuations do not
fund a prior dynamic declaration or file read retroactively.

## Extension

Additional write operations require their own closed Common continuation and
matching tests. No scenario name, business field, provider implementation or
sample row determines the dispatch. Public platform support is unchanged.

## Verification

`declared-file-installation.test.mjs` exercises real nominal table and Row
factories with explicit Common/resource fixtures: exact borrowing, foreign
contexts, refusal before construction, once-only attempts, pending constructor
cancellation and physical close. `installed-effect-profile-cleanup.test.mjs`
checks UPDATE dispatch, metadata before connection creation, foreign receivers,
reservation refusal, reentry, unsettled constructors and the borrowed original
export under the existing owner. These are Host
component tests, not normal-package README or live provider acceptance.

`hubspot-mapping-parent.test.mjs` uses the real Common initialization parent,
Ledger, declaration and Native Mapping producer. It checks the completed
Mapping Environment, real quantity refusal before projection, foreign/copied
originals, Source/retired refusal and reentry/attempt spending. It does not open
a Site or Client and supplies no physical cleanup or provider-send evidence.
