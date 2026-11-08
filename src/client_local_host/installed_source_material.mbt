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
/// Native JSON's original construction peak and one returned tree. The fixed
/// Host supplies facts from its existing wire scan, never a budget or a close
/// acknowledgement. Keep the full parsed/checked/identity envelope until that
/// SAME native parser and physical file owner have completed. The existing
/// provider fold retains this peak on failure; its retained-only projection
/// is selected only by the original successful constructor caller.
pub fn installed_source_json_construction_capacity(
  wire_nodes : Int64,
  wire_units : Int64,
  buffer_bytes : Int64,
  returned_nodes : Int64,
  returned_text_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  if wire_nodes < 0L ||
    wire_units < 0L ||
    buffer_bytes < 0L ||
    returned_nodes < 0L ||
    returned_text_bytes < 0L ||
    wire_nodes > 9223372036854775807L / 4L ||
    wire_units > 9223372036854775807L / 12L {
    return None
  }
  guard installed_source_construction_capacity(
      4L * wire_nodes,
      12L * wire_units,
      buffer_bytes,
      4L * wire_nodes,
      12L * wire_units,
      buffer_bytes,
    )
    is Some(workspace) &&
    installed_source_construction_capacity(
      returned_nodes, returned_text_bytes, 0L, 0L, 0L, 0L,
    )
    is Some(returned) else {
    return None
  }
  @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(returned),
    @execution.execution_capacity_execution_bytes(workspace),
  )
}

///|
/// Shared native profile parse/snapshot/alias inventory. Wire facts come from
/// the already owned original String; neither this recipe nor its retained
/// projection parses, validates a connector, authenticates or acknowledges IO.
/// Source and Effect use the SAME quantity owner before their native callbacks.
pub fn installed_profile_construction_capacities(
  nodes : Int64,
  units : Int64,
) -> Array[@execution.ExecutionCapacity]? {
  if nodes < 0L ||
    units < 0L ||
    nodes > 9223372036854775807L / 100L ||
    units > (9223372036854775807L - 50L) / 26L {
    return None
  }
  let workspace_text = 100L * nodes
  let decoded_workspace = 26L * units
  if decoded_workspace > 9223372036854775807L - workspace_text {
    return None
  }
  // Same inventory as the original Source profile constructor: parsed input,
  // provider root, alias rows and request snapshots; key/descriptor/ancestor,
  // prototype, sorting and serializer workspace. Strings remain borrowed.
  guard installed_source_construction_capacity(
      4L * nodes + 6L,
      2L * (units + 25L),
      0L,
      21L * nodes,
      decoded_workspace + workspace_text,
      0L,
    )
    is Some(parsed) &&
    installed_source_construction_capacity(4L * nodes + 6L, 0L, 0L, 0L, 0L, 0L)
    is Some(owned_containers) else {
    return None
  }
  // Split/checked profile projections retain their own arrays/records but
  // borrow the parsed original's immutable String leaves. Their temporary
  // serializer/check overlap is unchanged; do not retain another text copy.
  guard @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(owned_containers),
      @execution.execution_capacity_execution_bytes(parsed),
    )
    is Some(projected) else {
    return None
  }
  Some([parsed, projected])
}

///|
/// A fixed native inspection has no escaping variable output. The SAME
/// original profile recipe bounds its descriptor/stack/Set scan. Its caller
/// still retains that profile separately; selecting this DATA does not prove
/// that the inspection ran or that any physical child closed.
pub fn installed_source_inspection_construction_capacity(
  original : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity {
  @execution.execution_capacity(
    0L,
    @execution.execution_capacity_execution_bytes(original),
  ).unwrap()
}

///|
/// Existing Table snapshot/writer/frame inventory from its single funded
/// inspection. These are quantities for the original Source reservation, not
/// an admission or a second budget. No tree is walked to price it in Core.
pub fn installed_table_construction_inventory(
  nodes : Int64,
  wire : Int64,
  strings : Int64,
  serializer_text : Int64,
) -> Array[Int64]? {
  if nodes < 0L ||
    wire < 0L ||
    strings < 0L ||
    serializer_text < 0L ||
    nodes > 9223372036854775807L / 7L ||
    wire > (9223372036854775807L - 4L) / 4L ||
    strings > 9223372036854775807L / 8L ||
    serializer_text > 9223372036854775807L / 2L {
    return None
  }
  let retained_text = 8L * strings
  let recursive_text = 2L * serializer_text
  let frame_text = 4L * wire
  if recursive_text > 9223372036854775807L - retained_text ||
    frame_text > 9223372036854775807L - retained_text - recursive_text {
    return None
  }
  // Four retained profile/catalog/target views, three writer arrays; original
  // UTF16 strings, recursive canonical text, and body/framed/decoded bytes.
  Some([7L * nodes, retained_text + recursive_text + frame_text, 3L * wire + 4L])
}

///|
/// Same Source constructor aggregate with selected original native recipes.
/// Each supplied native peak remains conservatively retained. Only the
/// original caller of a closed synchronous constructor may replace its entry
/// with retained output DATA after retaining all returned outputs. Failed,
/// running and unproven constructors keep their full peak until retirement.
/// This fold issues no owner, completion proof or permission.
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
/// Only the retained DATA part of an original constructor quantity. This
/// projection observes no completion, currentness, Resource or physical ACK.
/// The original Source caller may select it only after a closed synchronous
/// constructor has returned and all its actual output is retained. Failed or
/// still-running constructors keep their full original quantity.
pub fn retained_installed_source_construction_capacity(
  original : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity {
  let retained = @execution.execution_capacity_retained_bytes(original)
  if retained == @execution.execution_capacity_execution_bytes(original) {
    original
  } else {
    @execution.execution_capacity(retained, retained).unwrap()
  }
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
  match @resources.check_working_preparation_capacity_current(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
