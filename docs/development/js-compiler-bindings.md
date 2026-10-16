# Private JavaScript compiler bindings

## Responsibility

`scripts/templates/js-compiler-binding.mjs` is the sole implementation of the
selected MoonBit compiler's Result/Option/tuple representation in product
JavaScript. `scripts/generate-js-compiler-bindings.mjs` emits byte-identical
private copies for independently installed packages. The copies are not public
wire codecs, semantic Owners, or opaque-value constructors. Connector checks,
Model decisions, publication, retention and physical cleanup remain with their
existing Owners. `runtime-result.mjs` retains its existing checked facade.

## Inputs and outputs

The selected compiler and core are pinned by `toolchain.json`. Result accessors
recognize success/refusal without copying the original payload. Required and
optional accesses retain the original nullish behavior. A tuple projection
retains its field order, reference identity, exact Int64 and original strings.
Pair/triple constructors only encode existing callback tuple arguments; they
cannot issue an opaque Model, Run, Scope, receipt or grant.

Option representation is type-dependent. A reference Option uses its original
reference or `undefined`; a Unit Option uses `undefined` or the compiler's
absent sentinel. These are not general malformed-value validators. A caller
must use the actual declared MoonBit return type and retain its existing value
validation. Explicit `runtimeIsTaggedPresent/Absent` helpers preserve legacy
tagged-adapter behavior; they are not a universal Option rule. Public DATA
fields spelled `$tag` or `_0` are unrelated to this compiler binding.

## Identity

These operations do not serialize, reconstruct, transfer or re-admit opaque
values. The same original payload and callback receiver remain under the
existing adapter/Owner membership. A matching field value or CID is not a
substitute for that membership, currentness, authority or original custody.

## Ownership

Projection does not transfer ownership. Existing aliases, pending callbacks,
Store responsibilities and cleanup handles retain their original lifetimes.
Temporary tuple aliases used for destructuring are cleared after projection.
Pair/triple construction replaces one existing tuple object with one object.
Sparse local tuples additionally overlap their temporary numeric-field record
and `Object.keys` workspace with the returned tuple. That workspace is not free
capacity; existing Host/Run phase accounting remains responsible for it.

## Synchronization

Compiler conversion and action-name projection are synchronous and perform no
I/O, await, retry, state transition or callback invocation. They do not create a
second scheduler or decide whether an operation may reenter. Existing callbacks
and receiver binding remain the consuming adapter's responsibility.

## Failure

Existing checked facades retain their error classes, codes and original causes.
Malformed Result discriminants are not accepted as success or definitive
Provider refusals. The Salesforce preparation marker still requires the
existing observed Catalog boundary; a transport/observation failure is not made
a definitive refusal by moving representation access.

## Cancellation

Conversion does not cancel, stop, settle or release anything. Cancel acceptance,
physical I/O quiescence, raw saving, Journal commit, holding retirement and
resource return remain distinct original observations. Unknown is neither
success nor an unsent request, and no retry permission is issued here.

## Resources

No Ledger, reservation, allowance, normal numerical profile or physical ACK is
created by these helpers. Conversion work, callback references and any temporary
projection workspace remain in their existing Host/Run responsibility. Reference
retirement is not a GC or process/module/native-memory release acknowledgment.

## Extension

Action names come from `scripts/js-action-boundaries.mjs`, which references the
existing Owner enum and `*_action_code` function. It contains no action numbers.
The generator reads the closed Owner mapping and emits the publication and
strategy facades. These facades only name decisions already made by MoonBit;
they store no lifecycle state. Existing unknown-code refusals and the explicit
unsupported managed-fallback result remain unchanged. Toolchain/Owner changes
must update reviewed bindings and their actual-target correspondence together.

## Verification

Run `node scripts/check-js-compiler-bindings.mjs` with the pinned toolchain.
This bounded, nonzero check builds only the JS binding probes, checks real
generated-output freshness and uses the actual compiled Owners. The primitive
probe covers success, contract refusal, malformed Result, reference/Unit Option,
Unicode, exact Int64, original identity and same-typed tuple-role reversal.
The action probe checks every declared projection and rejects valid-number
swaps at actual close/holding and unknown-commit boundaries. Its fixtures are
not distributed runtime entrances or new operation Owners.

These receipts do not establish Native/Wasm runtime behavior, physical Provider
success, normal funding, public Model execution or whole-product completion.
