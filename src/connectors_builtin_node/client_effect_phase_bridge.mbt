///|
/// A private view of the existing captured-input/Resource custody, not a new
/// Run, ledger, scheduler or authority. The Host retains this view before
/// preparation and keeps it with its original captured payload until release.
struct ClientEffectCommandWorkspace {
  mut origin : (ClientLocalEffectHost, @strategy.CapturedEffectInputs)?
  member_index : Int
  limits : @publication_host.PublicationOutputExportLimits
  max_work : Int
  quote : @execution.ExecutionCapacity
  mut capacity : @resources.SharedCapacity?
  mut allocation : @resources.SharedAllocation?
  mut borrow : @resources.SharedBorrow?
  mut importing : ClientEffectManagedInputImport?
  mut key : @strategy.CapturedEffectCommandKeyValidation?
  mut operating : Int
}

///|
pub(all) enum ClientEffectCommandWorkspaceIssue {
  ForeignOrigin
  Unavailable
  Resource(@resources.LedgerIssue)
  Import(ClientEffectManagedInputIssue)
  Key(@strategy.CapturedEffectCommandKeyIssue)
}

///|
fn client_effect_command_workspace_current(
  value : ClientEffectCommandWorkspace,
) -> Bool {
  guard value.origin is Some((owner, inputs)) else { return false }
  @strategy.captured_effect_inputs_match_run(inputs, owner.run) &&
  @strategy.captured_effect_inputs_match_computation(
    inputs,
    @publication_host.prepared_client_effect_computation_graph(
      @publication_host.prepared_client_effect_run_computation(owner.prepared),
    ),
  )
}

///|
fn client_effect_workspace_wire_limits_equal(
  a : @execution.RowWireLimits,
  b : @execution.RowWireLimits,
) -> Bool {
  a.max_columns == b.max_columns &&
  a.max_order_work == b.max_order_work &&
  a.max_bytes == b.max_bytes &&
  a.max_nodes == b.max_nodes &&
  a.max_depth == b.max_depth
}

///|
fn client_effect_workspace_limits_equal(
  a : @publication_host.PublicationOutputExportLimits,
  b : @publication_host.PublicationOutputExportLimits,
) -> Bool {
  a.max_result_fields == b.max_result_fields &&
  a.max_result_mapping_work == b.max_result_mapping_work &&
  a.max_result_order_work == b.max_result_order_work &&
  a.max_result_workspace_entries == b.max_result_workspace_entries &&
  a.max_rows == b.max_rows &&
  a.max_batch_bytes == b.max_batch_bytes &&
  a.values.max_nodes == b.values.max_nodes &&
  a.values.max_text_bytes == b.values.max_text_bytes &&
  a.values.max_depth == b.values.max_depth &&
  a.values.max_work == b.values.max_work &&
  a.schema.max_fields == b.schema.max_fields &&
  a.schema.max_bytes == b.schema.max_bytes &&
  a.schema.max_nodes == b.schema.max_nodes &&
  a.schema.max_depth == b.schema.max_depth &&
  client_effect_workspace_wire_limits_equal(a.payload_wire, b.payload_wire) &&
  client_effect_workspace_wire_limits_equal(a.logical_wire, b.logical_wire)
}

///|
/// Plan only: no reservation, allocation, read, key work or callback. The
/// selected sequence comes from this original installed Host, never a caller
/// byte count, equal CID, foreign Run, structural limit or unrelated token.
#export_name("clientProgramPlanEffectCommandKeyWorkspace")
pub fn client_program_plan_effect_command_key_workspace(
  owner : ClientLocalEffectHost,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  max_work : Int,
) -> Result[ClientEffectCommandWorkspace?, ClientEffectCommandWorkspaceIssue] {
  if max_work < 0 ||
    !@strategy.captured_effect_inputs_match_run(inputs, owner.run) {
    return Err(ForeignOrigin)
  }
  match
    @strategy.captured_effect_command_requires_input_key(
      inputs, member_index, max_work,
    ) {
    Ok(false) => return Ok(None)
    Ok(true) => ()
    Err(issue) => return Err(Key(issue))
  }
  let count = @strategy.captured_effect_local_result_count(inputs)
  if count > max_work {
    return Err(Unavailable)
  }
  let mut task = None
  for index in 0..<count {
    if @strategy.captured_effect_local_result_matches_member(
        inputs, index, member_index,
      ) {
      if task is Some(_) {
        return Err(ForeignOrigin)
      }
      let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
      task = Some(@strategy.captured_effect_local_result_task(result))
    }
  }
  guard task is Some(task) && owner.sequences.get(task) is Some(sequence) else {
    return Err(Unavailable)
  }
  let graph = @strategy.captured_dag_graph(
    @strategy.captured_effect_run_dag(owner.run),
  )
  guard @strategy.graph_task_owner(graph, task) is Some(original) &&
    physical_equal(@execution.generated_sequence_owner(sequence), original) else {
    return Err(ForeignOrigin)
  }
  let limits = client_program_own_effect_export_limits(limits)
  guard @client_local_host.client_command_key_workspace_capacity(
      sequence, limits,
    )
    is Some(quote) else {
    return Err(Unavailable)
  }
  Ok(
    Some({
      origin: Some((owner, inputs)),
      member_index,
      limits,
      max_work,
      quote,
      capacity: None,
      allocation: None,
      borrow: None,
      importing: None,
      key: None,
      operating: 0,
    }),
  )
}

///|
fn begin_client_effect_command_key_workspace(
  value : ClientEffectCommandWorkspace,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
) -> Result[ClientEffectManagedInputImport, ClientEffectCommandWorkspaceIssue] {
  if !client_effect_command_workspace_current(value) ||
    value.importing is Some(_) {
    return Err(ForeignOrigin)
  }
  let (owner, inputs) = value.origin.unwrap()
  guard @strategy.captured_effect_input_at(inputs, value.member_index)
    is Some(input) else {
    return Err(ForeignOrigin)
  }
  if !@strategy.captured_effect_input_matches_managed(input, output) {
    return Err(ForeignOrigin)
  }
  let ledger = @strategy.captured_dag_ledger(
    @strategy.captured_effect_run_dag(owner.run),
  )
  if value.capacity is None {
    let capacity = match
      @resources.reserve_shared_workspace_capacity(
        ledger,
        @execution.execution_capacity_retained_bytes(value.quote),
        @execution.execution_capacity_execution_bytes(value.quote),
      ) {
      Ok(capacity) => capacity
      Err(issue) => return Err(Resource(issue))
    }
    // Custody precedes the next Resource/Host callback and any allocation.
    value.capacity = Some(capacity)
  }
  if !client_effect_command_workspace_current(value) {
    return Err(Unavailable)
  }
  let capacity = value.capacity.unwrap()
  if value.allocation is None {
    match
      @resources.allocate_shared_capacity(
        capacity,
        @execution.execution_capacity_execution_bytes(value.quote),
      ) {
      Ok(allocation) => value.allocation = Some(allocation)
      Err(issue) => return Err(Resource(issue))
    }
  }
  if !client_effect_command_workspace_current(value) {
    return Err(Unavailable)
  }
  if value.borrow is None {
    match
      @resources.borrow_shared_capacity(capacity, value.allocation.unwrap()) {
      Ok(borrow) => value.borrow = Some(borrow)
      Err(issue) => return Err(Resource(issue))
    }
  }
  if !client_effect_command_workspace_current(value) {
    return Err(Unavailable)
  }
  let importing = match
    client_program_effect_managed_input_begin(
      input,
      output,
      material,
      value.limits,
    ) {
    Ok(importing) => importing
    Err(issue) => return Err(Import(issue))
  }
  value.importing = Some(importing)
  if !client_effect_command_workspace_current(value) {
    return Err(Unavailable)
  }
  Ok(importing)
}

///|
/// Retain the planned view before calling this synchronous preparation. A
/// refusal can retain the SAME reservation/allocation/borrow for cleanup.
#export_name("clientProgramBeginEffectCommandKeyWorkspace")
pub fn client_program_begin_effect_command_key_workspace(
  value : ClientEffectCommandWorkspace,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
) -> Result[ClientEffectManagedInputImport, ClientEffectCommandWorkspaceIssue] {
  // Every invocation, including a refused reentrant one, owns one synchronous
  // stack entry. Its private caller's finally releases only that entry.
  value.operating += 1
  if value.operating != 1 {
    return Err(Unavailable)
  }
  guard value.origin is Some((_, original)) &&
    physical_equal(original, inputs) &&
    value.member_index == member_index &&
    client_effect_workspace_limits_equal(value.limits, limits) else {
    return Err(ForeignOrigin)
  }
  begin_client_effect_command_key_workspace(value, output, material)
}

///|
/// The private Node caller invokes this in finally after the synchronous
/// Begin/Start call returns or throws. It clears only that stack-call fence;
/// it does not return a borrower, retire workspace or acknowledge cleanup.
#export_name("clientProgramEffectCommandKeyWorkspaceSynchronousEnd")
pub fn client_program_effect_command_key_workspace_synchronous_end(
  value : ClientEffectCommandWorkspace,
) -> Unit {
  if value.operating > 0 {
    value.operating -= 1
  }
}

///|
#export_name("clientProgramStartEffectCommandKeyWorkspace")
pub fn client_program_start_effect_command_key_workspace(
  value : ClientEffectCommandWorkspace,
) -> Result[
  @strategy.CapturedEffectCommandKeyValidation,
  ClientEffectCommandWorkspaceIssue,
] {
  value.operating += 1
  if value.operating != 1 ||
    value.key is Some(_) ||
    !client_effect_command_workspace_current(value) {
    return Err(Unavailable)
  }
  guard value.origin is Some((_, inputs)) &&
    value.importing is Some(importing) &&
    value.borrow is Some(borrow) else {
    return Err(Unavailable)
  }
  let result = client_program_effect_managed_command_key_start(
    inputs,
    value.member_index,
    importing,
    value.max_work,
  )
  let result = match result {
    Err(issue) => Err(Key(issue))
    Ok(None) => Err(Unavailable)
    Ok(Some(key)) => {
      value.key = Some(key)
      if !@strategy.bind_captured_effect_command_key_workspace(key, borrow) ||
        !client_effect_command_workspace_current(value) {
        Err(Unavailable)
      } else {
        Ok(key)
      }
    }
  }
  result
}

///|
/// Release only through the same captured child's existing cleanup. Revoking
/// origin or cancelling the bridge alone is not the Resource acknowledgement.
#export_name("clientProgramCloseEffectCommandKeyWorkspace")
pub fn client_program_close_effect_command_key_workspace(
  value : ClientEffectCommandWorkspace,
) -> Result[Bool, ClientEffectCommandWorkspaceIssue] {
  value.origin = None
  if value.operating != 0 {
    return Ok(false)
  }
  if value.capacity is Some(capacity) &&
    !@resources.shared_capacity_usage(capacity).closing {
    match @resources.close_shared_capacity(capacity) {
      Ok(_) => ()
      Err(issue) => return Err(Resource(issue))
    }
  }
  if value.key is Some(key) {
    match @strategy.cleanup_captured_effect_command_key_validation(key) {
      Ok(false) => return Ok(false)
      Ok(true) => value.key = None
      Err(issue) => return Err(Key(issue))
    }
  }
  if value.importing is Some(importing) {
    client_program_effect_managed_input_cancel(importing)
    value.importing = None
  }
  if value.borrow is Some(borrow) {
    match @resources.return_shared_capacity(borrow) {
      Ok(_) => value.borrow = None
      Err(issue) => return Err(Resource(issue))
    }
  }
  if value.allocation is Some(allocation) {
    if !@resources.shared_allocation_usage(allocation).retiring {
      match @resources.retire_shared_capacity(allocation) {
        Ok(_) => ()
        Err(issue) => return Err(Resource(issue))
      }
    }
    match @resources.release_shared_capacity(allocation) {
      Ok(_) => value.allocation = None
      Err(issue) => return Err(Resource(issue))
    }
  }
  if value.capacity is Some(capacity) {
    match @resources.settle_shared_capacity(capacity) {
      Ok(_) => value.capacity = None
      Err(issue) => return Err(Resource(issue))
    }
  }
  Ok(true)
}

///|
#export_name("clientProgramEffectCommandKeyWorkspacePending")
pub fn client_program_effect_command_key_workspace_pending(
  value : ClientEffectCommandWorkspace,
) -> Bool {
  value.origin is Some(_) ||
  value.operating != 0 ||
  value.capacity is Some(_) ||
  value.allocation is Some(_) ||
  value.borrow is Some(_) ||
  value.importing is Some(_) ||
  value.key is Some(_)
}
