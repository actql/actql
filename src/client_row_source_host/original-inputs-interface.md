# Borrowed original Row inputs

- Responsibility: Row retains a capability-free snapshot of its original
  captured inputs for the existing prefix and keyed consumers.
- Inputs and outputs: Construction consumes bounded ordered RowSourceCaptures
  and the same Ledger. Accessors return only original capture/query DATA;
  eligibility and cleanup predicates return facts, never token getters.
- Identity: Private reservation/holding pairs are snapshotted while the strict
  live census matches. Every later live use compares the exact Row objects and
  tokens. Missing, duplicate, foreign or substituted inputs cannot be admitted
  by matching counts, wire contents, serials or declaration names.
- Ownership: The snapshot does not own execution, cleanup, resources or Source
  authorization. Row and the existing prefix retain those duties. Its private
  arrays cannot be replaced by callers and survive cancelled-source retirement.
- Synchronization: Copy the caller's capture list before callbacks. After all
  source-current callbacks, check every original pair again without callbacks,
  including earlier inputs that a later callback could invalidate. Resource
  eligibility follows this final fence before allocation or borrowing.
- Failure: Dead or foreign captures, changed token custody, insufficient work,
  phase mismatch or pending dependencies refuse new use. A failure does not
  fabricate another captured relation or forget the original cleanup obligation.
- Cancellation: Cleanup uses the immutable pre-retirement token snapshot even
  after Row clears a released holding. Resource checks distinguish actual
  retirement from pending cleanup and use immutable issuance serials rather than
  compacted live indices. These facts never permit new reads from retired inputs.
- Resources: The snapshot inventory counts its record, copied fixed arrays and
  original-token pair records using the shared pinned array representation.
  Callers fund that retained structure and surrounding construction controls
  before entry; source payloads and consumer overlap remain separately funded.
- Extension: A new consumer must retain the same snapshot and perform the final
  whole-input fence, not extract tokens or replace it with caller-reported state.
- Verification: The borrowed-original inventory test in
  client_local_host/original_keyed_prefix_wbtest.mbt uses actual Row capture and
  existing prefix cancellation, checks caller-array isolation, duplicate/work
  refusal and cleanup after real holding removal. Resource plural tests cover
  ordered pairs, alternate holdings, foreign tokens and pending dependents.
