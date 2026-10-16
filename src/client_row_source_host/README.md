# Common installed row Source Owner

This package retains the existing checked Source requirement, nominal input
schema, acquisition/attempt, physical reservation, admitted rows, capture evidence
and cleanup responsibility used by provider row adapters. Provider material and
cost candidates alone never issue a captured Source. Exact checked contracts,
original transport verification and retained output must remain available.

`row_acquisition_column_contract` is a read-only projection of the original
checked input contract. A provider can use it for ordinary raw-value admission;
it cannot turn an equal foreign CheckedValue into a nominal original or grant
Source access. The input buffer still checks exact contract identity.

## Interface responsibilities

- Responsibility: Common owns checked row acquisition, attempt/capture evidence,
  keyed/listing semantics and original row lifetime; providers own physical I/O.
- Inputs and outputs: declarations and original QueryRequirements prepare typed
  acquisitions. Original attempts admit charged pages and may issue a live
  capture only after the existing completion and verification checks.
- Identity: requirement, schema/field contracts, RowAttempt, issuer, reservation,
  page ticket and captured input remain nominally bound to the original Owner.
- Ownership: the same RowRun holds admitted input, residual work, retention and
  cleanup. Transferred DAG holdings retain their original task responsibility.
- Synchronization: one-shot page tickets, attempt state and original callbacks
  guard consumption; a copied value or current observation cannot create a Run.
- Failure: typed Source/evidence/consumer/physical failures remain distinct.
  Failed cleanup retains the original holding/reservation and responsibility.
- Cancellation: abort stops logical admission; physical stop and final cleanup
  acknowledgement are separate. Cancellation never authorizes a new attempt.
- Resources: accounted entries reserve on the supplied original Ledger before
  physical reads; received bodies charge actual transfer before decoding, and
  original admitted input/residual/capture retention remains accounted.
- Extension: provider-specific spelling adapts to these existing typed ports;
  no provider equality, independent Ledger or generic retry replaces them.
- Verification: package and consuming query-integration cases exercise nominal
  values, page accounting, keyed/listing profiles, capture and retained cleanup.
