# Installed Environment construction under the existing Source material

## Responsibility

`installed-funded-environment.mjs` surrounds the shared Environment merge with
construction reservations from the existing installed Source material. It owns
no new Run, authority, Source or Ledger. `installed-check-environment-construction.mjs`
quotes only JavaScript construction inventory. Native wire and model admission
remain separate Core operations and separate native construction quantities.
The exported pure `composeAdmittedCheckEnvironmentOriginals` preserves the
existing merge semantics; calling it alone establishes no installed provenance.

## Inputs and outputs

The installed composer takes exact services/runtime, a base wire or issued base
original, and optional Source/Effect wires or issued originals. It returns a
frozen tuple of runtime, body, canonical wire, evidence CID and admitted native
Environment. Parsing/freezing, canonical verification and body hashing precede
native wire admission and model admission, each under its own funded constructor.
The frozen parse census is collected in that same traversal. Merging borrows
member trees and derives conservative counts from the input censuses; it does
not parse again to discover demand. Source/Effect aggregate loaders retain the
returned original alongside its wire. DuckDB exposes its prepared original,
mock Source folding forwards the same installation services, and embedded Host
joins those originals at its final Environment boundary. Local file Effects
forward services into the ordinary Effect aggregate rather than creating a
separate composition path.

## Identity

Private WeakMaps associate each issued tuple with the exact services, runtime
and construction reader. Copies, equal wires and equal CIDs do not confer this
provenance. Every borrowed original rechecks the current reader. The first base
is retained on that service; later calls must pass that exact base or its wire.
An independently supplied string is admitted, not looked up in a global cache.
The shared pure merge still validates policies, selector conflicts, canonical
member equivalence and evidence identity; it cannot authorize installed reuse.

## Ownership

All native construction passes through `reader.prepareNativeInput`, retaining
quantities, inputs and outputs on the same Source material. Parsed documents
and borrowed member trees are immutable. New composed section arrays, manifest
containers and bodies are sealed before issuance. The composer keeps its base,
failure and busy state tied to the actual services, not to caller-owned options.
Published Source contexts retain the central result instead of rebuilding it
or manufacturing a Row declaration. Existing aggregate cleanup continues to
own partially loaded adapters and physical children.

## Synchronization

The composer sets its busy fence before reader lookup, refuses reentry and
rechecks currentness when borrowing and after new composition. Aggregate Source
and Effect loaders snapshot their options and require the same live Source
construction reader before the first loader callback. Later callbacks cannot
replace the runtime/services pair or revive a missing-services fallback.
Capacity callbacks precede each constructor. Native wire construction and
native Environment construction are separately quoted and admitted; JavaScript
geometry is never used as native funding.

## Failure

Malformed/noncanonical wire, wrong evidence CID, excessive input size, foreign
originals, changed base, conflicting merge members, unavailable native capacity
or failed admission refuse through the existing construction path. A separate
failed flag retains even an undefined thrown cause: subsequent calls cannot
restart failed construction merely because the cause is falsy. A failed partial
construction remains on its original Source material. Aggregates retain their
existing partial-adapter cleanup rather than treating a failed merge as a
successful installation.

## Cancellation

These constructors are synchronous; cancellation/currentness belongs to the
same Source initializer and its cleanup. Finishing one merge does not retire
that material. `releaseRetiredInstalledEnvironmentComposition` requires the
actual Source retirement acknowledgement; pending cleanup retains the base and
failure. Source retirement marks the material retired before releasing the
composer index. Neither a copied service nor a successful Promise is this ACK.

## Resources

Parse geometry bounds retained parsed nodes/text and parse/freeze workspace
before JSON parsing, including malformed prefixes. Document geometry includes
canonical comparison, body spread, hashing, native-original index and temporary
encoding overlap. Composition geometry accounts for policy comparisons,
selector conflict keys, deduplication, sorting, member canonicalization/hashing,
manifest construction, shallow envelopes, merged census and original index.
Repeated or equal inputs do not discount construction demand. ASCII escaping
and conservative non-ASCII normalization bounds are computed without performing
the canonical constructor in the quote. Shape inspection requires frozen plain
DATA, rejects proxies/accessors/cycles/sparse arrays, and caps depth. These
quantities describe JavaScript inventory only; native wire/model recipes consume
the retained census and native wire original respectively. No physical backing
or actual Resource budget acceptance is established by a numeric quote alone.

## Extension

New Environment sections, canonicalization allocation behavior or native
admission work require corresponding inventory and semantic coverage. The
central composer is not an alternate provider registry, general wire/CID cache,
scenario-specific data model or permission bypass. Existing direct diagnostic
composition is not proof of installed funding and does not replace the mandatory
services requirement at installed aggregate entrances.

## Verification

`installed-funded-environment.actual.test.mjs` exercises generated constructors,
original reuse and foreign-copy refusal, reservation-before-construction,
sticky failure including undefined causes, currentness loss, retirement ACK and
mandatory services before aggregate loading. Its Resource ports are fixtures:
this establishes component sequencing, not actual budget admission or physical
backing. `installed-check-environment-construction.test.mjs` checks JavaScript
geometry separately. Source-scoped interface checking establishes actual syntax,
exports and these ten obligations only. Neither it nor those component checks
establishes normal-package README acceptance, live SaaS acceptance, release or
production deployment.
