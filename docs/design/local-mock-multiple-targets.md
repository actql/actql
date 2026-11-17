# One Mock installation with several writable targets

The explicit Local Mock initializer selects the complete finite Project catalog
before it constructs an Account identity, configuration or signing key. A target
is the exact pair of logical connection and resource. A physical filename does
not identify a target and cannot supply an authorization decision.

## Inventory and Account

The initializer borrows every selected Source, its prepared Mapping and physical
declaration. It validates canonical control names and duplicate Source, Task and
target identities before creating keys. Target pairs are ordered by connection,
then resource, using the existing UTF-16 string comparison. Repeated target pairs
are refused rather than silently increasing or merging their authority.

One configuration contains a separate delegated Effect entry for every target.
Its original single-target entry remains `mock-update`; plural entries use
`mock-update-0`, `mock-update-1`, and so on in the ordered inventory. The exact
`result/updates` read entry occurs once. These entries neither approve an Effect
nor replace current Account, Reviewer, Checkpoint or dispatch-claim checks.

Initialization creates one Account and one original key cohort for the whole
selected Project. Reopening an adopted installation uses its saved configuration
and original keys. A larger current catalog, a recognized profile or absent key
cannot upgrade that saved Account or regenerate its grants.

## Shared physical document

Different logical targets can select disjoint collections in the same JSON
document. Equal or ancestor/descendant collection paths are ambiguous and are
refused as overlapping writable collections. Each admitted collection retains
its own resource, key path, Mapping, binding, Preview and recovery identity.

The installation retains one physical file owner for that document. Each write
enters through the original durable row claim and the same-path exclusive lock.
It reads and admits the latest complete document, compares the selected original
row version and before-image, and replaces only the checked Mapping's spans.
Thus a preceding legitimate write in another collection is preserved rather
than replaced by an old whole-document snapshot. External changes to the
selected row and changes during the actual file-operation window still refuse.

The write's returned replacement, subsequent directory synchronization, row
settlement and physical child release remain distinct observations. Cleanup
never repeats a write. A Run may release only its own retained physical children;
another Run's close does not acknowledge them. A lost or ambiguous outcome stays
with its original request and claim until the existing recovery owner establishes
the outcome; absence of a receipt does not authorize another send.

## Construction and execution ownership

The initializer prices complete inventory vectors, duplicate maps, normalization,
configuration entries and serialization overlap through its existing Account
construction Read before those constructors run. Pre-signing preparation uses
the key codec's finite output-name length, not a fabricated key or permission.
The eventual real configuration is retained once through the same Read.

Installed metadata construction uses the existing Source-initialization owner.
The shared file controls, per-Source driver and alias projection are separate
synchronous construction phases; temporary constructor capacity is not carried
across unrelated asynchronous work. Member loading retains the actual adapter
before a later currentness check can fail. Original cleanup custody survives a
construction failure or currentness loss.

Mappings, Account policy and row claims remain the existing owners' contracts.
Per-operation physical plans retain their actual operation names and original
limits. Neither the inventory length nor a maximum member count supplies free
execution capacity or expands the selected physical-operation profile.
