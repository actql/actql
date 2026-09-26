# Effectful checked Fragment compiler handoff

## Ownership and adoption

Distribution owns the shared compiler. Connector owns Effect application and
provider execution and does not need a second compiler issuer.

The common base is `44f00eab0a73819b45a0f64627898f796717ea29`.
Connector proposal `cf9177abb60e33e5c1d090a1fed79a6c7d0e10eb` is adopted
with conflict resolution preserving the base's final-step output contract.
Its older first-step output selection is not restored. The Node bridge keeps
existing integrated declarations instead of duplicating moved declarations.
Public interfaces are regenerated from the resolved source.

Proposal `78e73fe627b41f2209ee273d27c244ca07013d18` is applied as a focused
consumer change on this base. Its later Client-request changes and historical
validation statements are not imported as dependencies or new evidence.
The consumer passes the issued computation CID to its existing test evidence
helper. That helper still supplies example full-Plan and Host policy evidence.

## Public operations

The MoonBit package `actql/actql/run_publication_host` exposes:

- `issue_prepared_client_effect_values_fragment`: accepts the original
  `PreparedClientEffectComputation`, task index, `SequenceLimits`, and wire,
  node and depth limits; returns `Result[ClientValuesFragmentNode,
  ClientValuesFragmentIssue]`.
- `admit_prepared_client_effect_values_fragment`: accepts the same owner and
  limits plus saved Fragment wire, regenerates the expected Fragment and
  rejects mismatched evidence with `ClientValuesFragmentAdmissionIssue`.
- Existing `client_values_fragment_wire`, `client_values_fragment_logical_cid`
  and output-contract accessors inspect the issued typed Fragment.

The internal Node bridge provides this minimal call after ordinary Effectful
preparation has returned its checked owner:

```js
const fragment = checked(
  moon.clientProgramIssueEffectValuesFragment(prepared, 0));
const computationCid = moon.clientProgramValuesFragmentLogicalCid(fragment);
```

`checked` unwraps the existing MoonBit Result ABI; it does not construct owner
or evidence objects. Connector can use this call in place of a fixture AoA
CID. Keep the original `prepared` owner for Effect capture and execution.

This is a computation Fragment, not a complete Program Executable Plan,
Bound Invocation Template, local Unit identity, local Invocation identity,
current authorization, or Effect apply permit. The shared implementation
uses the original graph and Effect declarations and does not recheck an
Effect-free Program. No Salesforce-specific compiler branch is introduced.

## Validation scope

The Effectful fixture checks an independent pipeline CID, exact output
schema, saved-wire admission, rejection of changed rows and missing tasks,
output size limits, and retention of the original checked Effect owner.
The package's existing Values tests exercise the unchanged shared issuer.
The shared package passed 14 tests on each of JS, Wasm and native.
Generated bridge, package freshness and formatting checks passed.
The connected provider and packed SDK regressions are recorded with the
final fixed SHA in the handoff.
Local provider fixtures are not live Salesforce or hosted Linux CI evidence.
