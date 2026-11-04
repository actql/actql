# Selected Local lookup policy and nominal transfer ceiling

## Responsibility

`localResourceLookupExecutionPolicy` narrows an already explicitly selected
Local lookup policy using the existing nominal Resource preparation's initial
transfer limit. It neither selects a replacement service nor creates a Ledger,
permission, provider grant or new capacity owner.

## Inputs and outputs

The function receives the runtime, actual preparation original and selected
policy. It snapshots that policy, reads the six-field nominal Resource limits,
and returns a validated policy with only `max_total_response_bytes` narrowed to
the lesser of its selected ceiling and the initial transfer quantity. An absent
selection remains absent.

## Identity

The runtime's `clientLocalPreparationResourceLimits` must recognize the actual
preparation original. An equal numeric policy or copied record does not replace
that original. The selected service's explicit lookup policy remains the basis;
row counts or peak-memory values cannot stand in for it.

## Ownership

The function retains only validated policy DATA. The existing preparation owns
its limits and the same Run Ledger owns reservations and remaining capacity.
Policy projection neither borrows physical children nor retires the preparation.

## Synchronization

Snapshot the selected policy before reading the nominal original limits and
validate the resulting snapshot again. This is synchronous initial-ceiling
selection, not an observation of available capacity at a later I/O boundary.
Actual remaining transfer must still be reserved by the same Run before each
provider operation.

## Failure

Malformed or unavailable limits, an invalid six-field projection, nonintegral
transfer quantity, nonpositive transfer or values exceeding safe integer range
refuse. Invalid explicit policies retain the existing validator's refusal.
The function does not replace invalid or unavailable originals with defaults.

## Cancellation

No physical work starts here. Cancellation and cleanup remain with the actual
preparation and Run; computing a policy is not an acknowledgement or reason to
release either original.

## Resources

Only response wire transfer and the nominal transfer counter share this
cumulative dimension. Peak memory must not be converted to cumulative decoded
bytes, and cardinality estimates must not manufacture a lookup budget. The
initial ceiling cannot be reused as fresh remaining Ledger capacity. Snapshot
objects are bounded policy DATA, not native or physical admission evidence.

## Extension

Any additional narrowed field needs its own dimensionally matching original
quantity and explicit selected policy. Do not infer lookup support, a new
service, or permission from a positive limit.

## Verification

`local-files-lookup-policy.test.mjs` checks selected policy projection and
nominal Resource limit behavior. Component evidence and syntax coverage do not
establish whole Run execution, actual remaining-budget admission, normal README
acceptance or provider I/O acceptance.
