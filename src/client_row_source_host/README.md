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

### Supplementary provider overlap

`start_accounted_provider_row_acquisition` accepts a trusted installation's
`ExecutionCapacity` declaration for the same original acquisition, selected
implementation and target recipe. It checked-adds retained and execution
overlap, including the existing scratch, to the same Ledger's `reserve_attempt`
before attempt construction. Missing/unjustified supply remains unavailable;
declaration construction is not a physical measurement, reservation or grant.
Ordinary and listing-report entries keep their existing selection semantics.
The private Node `clientProgramRowSourceProviderCapacity` translates exact
Int64 amounts through the existing `execution_capacity` DATA validator only;
it does not issue an opaque Owner, reservation or physical-cleanup receipt.

Before any provider page or completion, this profile requires the exact
`RowRunResponseBorrow` cleanup binding above. The trusted installer must bind
the original reader's physical-retirement observer before I/O, not callback
return, cancellation acceptance or Promise resolution. Capture retains provider
backing in the original reservation rather than transferring it to a task;
execution and remaining retention survive evidence generation and pending
cleanup. False retirement keeps the same debt for retry. Only that observer's
confirmed retirement allows original close to settle the same reservation.
After successful settlement the closed RowRun detaches that observer and
provider declaration; repeated close cannot re-enter the retired reader.
No numeric profile or transport implementation follows from this primitive.

The existing `ClientInstalledCaptureCapacity` Owner's
`installed_provider_row_capture_capacity` projects these same checked sums
before Run Ledger preparation, retaining the exact acquisition and declaration.
`installed_provider_row_capture_capacity_matches` checks that original pair;
equal quantities or equal requirement CIDs cannot substitute another pair.
The existing finite Ledger ceilings, actual overlap admission and refusals
remain in force. The new projection neither raises them nor proves every
downstream Compute/Effect envelope fits. Listing profile substitution is refused.

The nullable profile reference on every RowPhysical, selected declaration,
reader/observer aliases and transition overlap belong to the original Host
inventory. Returned diagnostics, raw history, ID/cursor indexes, parsed page,
checked rows, output and closures must be covered concurrently by the supplier;
maxPageBytes and transfer counts are not substitutes for that declaration.
Every installed capacity record also has one nullable provider-pair reference;
the selected pair retains the original acquisition and declaration until the
existing planning/capture Owner retires it. No extra reference is free merely
because it aliases an existing object.

### Static Resource identity in saved relation declarations

A saved relation view may carry `resource_identity_wire`, containing the existing
six-field `actql.resource_identity/0.1` SourceView contract. Restoration validates
its shape through the SAME generated SourceView rule in `check_environment`.
Only provider-ID field and output ResourceKind association belongs to the local
relation schema owner. Source parsing, generated-rule work, canonical body and
retained output consume the declaration's remaining byte/node/depth/work bounds. The ordinary
public relation constructor and declarations without this optional wire retain
their existing contracts and bytes.

The static contract is sealed into the same SourceView and Catalog identities.
It contains no current authority, concrete connection revision or boundary CID,
and issues no ResourceReference. The existing Host and value-admission owner
must separately resolve original connection evidence and issue an original
reference; a file name, returned JSON envelope or equal CID cannot stand in for
that authority. Source reads, Content custody, Plan funding and terminal cleanup
remain with their existing owners.
