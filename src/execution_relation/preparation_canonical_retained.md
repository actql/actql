# Canonical retained preparation projection

## Responsibility

`canonical_preparation_retained_bytes` shares the existing canonical backing
geometry with the original preparation tariff. Domains still own multiplicity,
aliasing and the lifetime of each counted representation.

## Inputs and outputs

The inputs are the immutable canonical extent and separately inventoried
control headers, references, words and UTF16 text. The output is optional
logical bytes, not engine heap size or a capacity token. Array/object spare
backing slots are counted. Traversal frames are not retained tree backing.

## Identity

No value is parsed, copied, encoded, hashed, admitted or assigned an identity.
Equal extent DATA does not prove that two representations alias.

## Ownership

The original domain keeps all bodies and their cleanup duties. This projection
neither transfers a body nor creates a Ledger, Reservation or Owner.

## Synchronization

This is a synchronous DATA calculation with no external callback or current
observation. The caller must already fund any traversal used to obtain extents.

## Failure

Negative counts, dimension arithmetic overflow and tariff overflow return None.
No overflowing count can cancel another invalid dimension or authorize use.

## Cancellation

No cancellation, retry, release or physical cleanup acknowledgement is issued.
The original owner still checks cancellation at its actual mutable boundary.

## Resources

The existing preparation tariff is applied once to the declared representation.
The fixed calculation creates no input-sized work container. A caller must
separately fund wrappers, outer arrays, traversal scratch and simultaneous live
representations; a retained-only cost is not their construction peak.

## Extension

Add representation meaning at its original domain and keep one tariff. Do not
copy the canonical geometry into a Host adapter or treat these bytes as a grant.

## Verification

`preparation_canonical_retained_wbtest.mbt` has independent geometry, spare-slot,
negative-count and overflow checks. The original keyed dependency workspace
cases exercise completed retained bodies and refusal through the same fold.
