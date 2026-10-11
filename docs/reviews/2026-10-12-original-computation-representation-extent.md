# Original computation representation extent

This is a preparation unit for the funding finding on #1481. It measures the
original admitted representation, not a replacement wire or a reconstructed
Receipt. It does **not** establish a funded production profile.

## Existing Owner and facts

`PublicationContract` retains four Strings (`name`, `identity_field`, `identity`,
`wire`) and a canonical tree. Its read-only projection counts these separately.
The canonical projection counts every node occurrence, key/value String and
UTF-16 unit, container, and actual `Array.capacity()` backing slot. Shared
immutable children are counted per occurrence, conservatively; no physical
deduplication or lifetime proof is inferred. The traversal reports its peak
frame-array capacity separately as workspace, without copying backing arrays
or serializing another body.

The Native capture projection selects exactly the six references already held
by `OriginalResidentEffectComputationEvidence`: Run, invocation, definition,
artifact, manifest and Receipt. It requires the same live capture and original
reservation. It accepts no candidate wire or substituted inventory. Per-contract
limits bound the six traversals. The facts grant neither funding nor disclosure.

The Core capacity API is backend dependent. Native/Wasm report allocated backing
slots; JS exposes the supported array length/capacity API, not the JS engine's
hidden heap allocation. JS results are not a Native heap measurement.

## Separate simultaneous retention

The existing physical capture reservation counts its encrypted Store body.
That is independent of the six contracts' heap representation and of the extra
six-reference `OriginalResidentEffectComputationEvidence` record. Source values,
Result payload and Named Result retention keep their existing Owners.

The #1536 caller also constructs these records on restore-only paths:

| Retained item | Separate control responsibility |
| --- | --- |
| `HolderEffectCatalogInitialUse` | Seven fields: original context, grant, thirteen-field scope, use ID, attempted flag, nominal claim option and original issue option |
| `HolderEffectCatalogInstallation` | Its added initial-use reference, plus the existing installation and service lifetime |
| Resource callbacks | The claim/save closures retain the initial-use record; the guarded-current closure retains the original Host/current context |
| Measurement | Traversal frames, six output descriptors and their backing, and the bounded temporary reference inventory |

Aliased original Strings and records are not newly copied bodies, but their
extended lifetime still needs funding until their cleanup Owner drops them.
These records and closures must be included in the independent control and
workspace envelope even when no initial GET occurs. The initial stamp's durable
record, heap control, and scratch budget are separate from Provider/body storage.

## Remaining funding connection

The current `physical.reserved_bytes()` does not cover this new heap lifetime.
Emitted UTF-8 length does not price a canonical tree. No coefficient, pool or
resource limit is introduced here. The adopted Host representation/layout bound
must cover these original facts and simultaneous control/workspace before the
existing `reserve_capacity` can fund retention. That byte-only token grants no
send/attempt allowance. Original cleanup must retain it through failure and
Store reopen, reuse the same token, and settle once after confirmed removal.

The original capture hold, its six references, and its cleanup tests remain
unchanged in this unit. Metadata funding and actual Native/Provider/public
acceptance remain uncompleted; the measured facts alone do not close #1481.
