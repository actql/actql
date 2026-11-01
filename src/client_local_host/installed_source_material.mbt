///|
/// Read the same prepared Environment from the existing Resource body's
/// original Source installation aggregate. The first tuple member is the
/// actual initialized Source/profile aggregate, never its static manifest,
/// CID, copied JSON or a newly installed counterpart.
///
/// The initial carrier must reserve construction before completing this body.
/// It retains the actual Source graph and this Environment across Requests;
/// existing Resource sibling borrows, returns and retirement own that lifetime.
/// This accessor adds no reservation, current/Account decision, permission or
/// cleanup acknowledgement. A retiring borrow still exposes DATA for cleanup;
/// the Resource owner separately refuses new sibling borrows.
pub fn[S] borrowed_installed_source_environment(
  holder : @resources.PreparationBodyBorrow[
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  source_original : S,
) -> Result[
  @source_publication.PreparedPublishedQueryEnvironment,
  @resources.PreparationCapacityIssue,
] {
  guard @resources.preparation_body_borrow_value(holder)
    is Some((original, environment)) else {
    return Err(@resources.BorrowReturned)
  }
  if !physical_equal(original, source_original) {
    return Err(@resources.ForeignOriginal)
  }
  Ok(environment)
}

///|
/// Variable Source initialization material only. Counts describe actual native
/// input/output trees, decoded text and simultaneous owned Buffers. Before a
/// native JSON decode, its original input-byte bound also bounds its possible
/// value occurrences; this is a conservative logical Host allowance, not the
/// different Common Parser/JsonDocument inventory or measured VM/RSS backing.
/// The shared capacity owner supplies all conversion/overflow rules. Fixed
/// callbacks, tuples and control frames remain the trusted Host baseline.
pub fn installed_source_construction_capacity(
  retained_nodes : Int64,
  retained_text_bytes : Int64,
  retained_wire_bytes : Int64,
  workspace_nodes : Int64,
  workspace_text_bytes : Int64,
  workspace_wire_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  @execution.execution_capacity_inventory(
    [
      { unit: @execution.ValueNodeSlots, count: retained_nodes, copies: 1, },
      {
        unit: @execution.DecodedTextBytes,
        count: retained_text_bytes,
        copies: 1,
      },
      { unit: @execution.QuotedBytes, count: retained_wire_bytes, copies: 1, },
    ],
    [
      { unit: @execution.ValueNodeSlots, count: workspace_nodes, copies: 1, },
      {
        unit: @execution.DecodedTextBytes,
        count: workspace_text_bytes,
        copies: 1,
      },
      { unit: @execution.QuotedBytes, count: workspace_wire_bytes, copies: 1, },
    ],
    @execution.RetainedAlongsideExecution,
  )
}

///|
/// Same Source constructor aggregate with selected original native recipes.
/// Native peak DATA remains conservatively retained until the Source owner
/// retires: success/throw alone never releases its constructor backing. This
/// only composes the shared quantities; it issues no owner or permission.
pub fn compose_installed_source_construction_capacity(
  original : @execution.ExecutionCapacity,
  providers : Array[@execution.ExecutionCapacity],
) -> @execution.ExecutionCapacity? {
  let mut result = original
  for provider in providers {
    let peak = @execution.execution_capacity_execution_bytes(provider)
    guard @execution.execution_capacity(peak, peak) is Some(retained) &&
      @execution.add_execution_capacity(result, retained) is Some(composed) else {
      return None
    }
    result = composed
  }
  Some(result)
}

///|
/// Fund the complete next constructor peak on its original live reservation.
/// An already sufficient debit still crosses the same original current fence;
/// it does not resize solely to observe currentness or issue another budget.
pub fn[I, S] reserve_installed_source_construction(
  owner : @resources.PreparationCapacity[
    I,
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  input : I,
  quote : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  let (old_retained, old_execution) = match
    @resources.preparation_capacity_working_extents(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let retained = Int64::max(
    old_retained,
    @execution.execution_capacity_retained_bytes(quote),
  )
  let execution = Int64::max(
    old_execution,
    @execution.execution_capacity_execution_bytes(quote),
  )
  if retained == old_retained && execution == old_execution {
    @resources.check_working_preparation_capacity_current(owner, input)
  } else {
    @resources.reserve_working_preparation_phase(
      owner, input, retained, execution,
    )
  }
}

///|
/// Only the fixed caller may reconcile after the original constructor and
/// physical file close have completed. A failed child keeps the original
/// peak; elapsed time, a stop request or a returned Promise is not disposal.
pub fn[I, S] reconcile_installed_source_construction(
  owner : @resources.PreparationCapacity[
    I,
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  input : I,
  retained : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  if @execution.execution_capacity_execution_bytes(retained) !=
    @execution.execution_capacity_retained_bytes(retained) {
    return Err(@resources.InvalidExtent)
  }
  @resources.reconcile_working_preparation_phase(
    owner,
    input,
    @execution.execution_capacity_retained_bytes(retained),
    @execution.execution_capacity_execution_bytes(retained),
  )
}

///|
pub fn[I, S] complete_installed_source_material(
  owner : @resources.PreparationCapacity[
    I,
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  input : I,
  source_original : S,
  environment : @source_publication.PreparedPublishedQueryEnvironment,
  retained : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  if @execution.execution_capacity_execution_bytes(retained) !=
    @execution.execution_capacity_retained_bytes(retained) {
    return Err(@resources.InvalidExtent)
  }
  @resources.complete_preparation_capacity(
    owner,
    input,
    (source_original, environment),
    @execution.execution_capacity_retained_bytes(retained),
    0L,
  )
}

///|
/// Existing Source/physical cleanup must have settled before calling. This
/// retires only the Source successor, never B's imported initial admission.
/// Live body borrowers keep that same debit pending; a failed constructor
/// uses the existing original-input abort only after its scratch unwinds.
pub fn[I, S] retire_installed_source_material(
  owner : @resources.PreparationCapacity[
    I,
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  input : I,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  match @resources.retire_preparation_capacity(owner) {
    Err(@resources.WorkActive) =>
      @resources.abort_preparation_capacity_after_cleanup(owner, input)
    value => value
  }
}
