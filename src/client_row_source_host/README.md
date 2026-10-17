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


### Non-row response charge consumption

`consume_row_run_response_charge` consumes exactly the same outstanding nominal
page-charge ticket of a live Reading attempt when its selected protocol observes
control input instead of rows. It neither increments pages nor admits values,
finishes the scan, creates evidence or acknowledges transport cleanup. The
existing ticket Owner checks original attempt, identity and single consumption;
foreign/stale/repeated tickets retain its ordinary typed refusal/abort behavior.

### Installed response-reader borrow

`check_row_acquisition_original` checks the exact original requirement and
declared view, not equal JSON or CID material. A trusted pure preparation callback
cannot substitute an independently prepared acquisition.

`borrow_row_run_responses` lends an already-begun accounted Direct RowRun once.
It creates no reservation, Run or authorization. Before provider I/O the reader
binds its same physical-stop observer into that RowRun's existing cleanup slot.
The original Host retains finish, capture and close; logical abort does not
erase the observer. Failed stop keeps the same reservation and cleanup debt.
Only confirmed physical retirement permits the reader's aliases to disappear
and the original Owner to release its root.

### Original provider declaration projection

`project_row_declaration` is a typed metadata port for an existing Common
producer's already-verified canonical Catalog, contracts, declared views and
manifest. It copies the metadata containers and keeps the exact supplied view
objects and canonical strings; it does not decode wire, regenerate a neutral
Catalog, validate a caller-computed CID, or issue permission/current/capacity
evidence. Salesforce exposes its projection from its original opaque static or
installed declaration, without a JavaScript entry accepting raw parts.

A new projection of equal canonical parts is not an acquisition's original
view. `check_row_acquisition_original` still requires that exact stored view
and checked requirement. The existing acquisition also checks original Source
evidence; a projection-only requirement lacking it remains refused. The
provider's already-bounded declaration owns the projection's input extent;
this metadata port introduces no generic view-count restriction or normal
numeric-profile adoption.
