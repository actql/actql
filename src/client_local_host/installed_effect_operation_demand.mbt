///|
/// One selected implementation's simultaneous request/response/decode/replay
/// and control allowance. This is immutable Host DATA, not an admission, an
/// Account grant, a physical operation or a receipt. Pure capture holders have
/// no physical attempt or transfer; each physical dispatch has its own extent.
struct ClientInstalledEffectOperationExtent {
  operation : String
  capacity : @execution.ExecutionCapacity
  transfer_bytes : Int64
  physical_attempt : Bool
}

///|
pub fn prepare_installed_effect_operation_extent(
  operation : String,
  capacity : @execution.ExecutionCapacity,
  transfer_bytes : Int64,
  physical_attempt : Bool,
) -> Result[ClientInstalledEffectOperationExtent, ClientInstalledManagedRunIssue] {
  if operation.is_empty() || transfer_bytes < 0L || (!physical_attempt && transfer_bytes != 0L) {
    return Err(Unsupported)
  }
  Ok({ operation, capacity, transfer_bytes, physical_attempt, })
}

///|
/// Selected original implementation inventory for one checked Effect member.
/// Member operations occur once; row operations occur for each checked input
/// row. Equal extent references at different occurrences still count twice.
/// These are implementation facts, not mandatory public profile knobs.
struct ClientInstalledEffectOperationDemand {
  prepared : @publication_host.PreparedClientEffectComputation
  member_index : Int
  stage_index : Int
  effect_id : String
  member_extents : Array[ClientInstalledEffectOperationExtent]
  row_extents : Array[ClientInstalledEffectOperationExtent]
}

///|
pub fn prepare_installed_effect_operation_demand(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  member_extents : Array[ClientInstalledEffectOperationExtent],
  row_extents : Array[ClientInstalledEffectOperationExtent],
) -> Result[ClientInstalledEffectOperationDemand, ClientInstalledManagedRunIssue] {
  let work = @publication_host.client_standard_program_preparation_limits().max_graph_work
  if member_extents.length() > work || row_extents.length() > work - member_extents.length() ||
    (member_extents.is_empty() && row_extents.is_empty()) {
    return Err(Unsupported)
  }
  let descriptor = match @publication_host.client_effect_member_descriptor(
    prepared, stage_index, effect_id, work,
  ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  Ok({ prepared, member_index: descriptor.0, stage_index, effect_id,
    member_extents: member_extents.copy(), row_extents: row_extents.copy(), })
}

///|
/// Same checked Program/request and installed contract originals for the quote
/// and actual managed-parent constructor. The original Node service separately
/// binds its runtime/installation and retains this plan before fallible start.
/// This plan creates no second Resource owner and carries no current Allow.
struct ClientInstalledEffectManagedPlan {
  prepared : @publication_host.PreparedClientEffectComputation
  request : @publication_host.ClientRequestIdentity
  query_time : @publication_host.ClientQueryTimePreparation?
  declarations : Array[@row_source_host.RowDeclaration]
  acquisitions : Array[@row_source_host.RowAcquisition]
  captures : Array[ClientInstalledCaptureCapacity]
  transport_bytes : Array[Int64]
  transport_execution_bytes : Array[Int64]
  installed_contracts : ClientInstalledSequenceContracts
  values_body : String
  fragment_body : String?
  ordered_body : String?
  operations : Array[ClientInstalledEffectOperationDemand]
  source_free : ClientInstalledManagedSourceFreePreparation?
  sequences : Array[@execution.GeneratedSequence]
  compute_sequences : Array[@execution.GeneratedSequence]
  capacity_plan : ClientLocalCapacityPlan
  provider_retained_bytes : Int64
  provider_execution_bytes : Int64
  rows : Int
  held_children : Int
  compute_limits : @resources.LedgerLimits
  limits : @resources.LedgerLimits
}

///|
fn installed_effect_requirements(limits : @resources.LedgerLimits) -> Array[Int64] {
  [limits.planning_work.to_int64(), limits.attempts.to_int64(),
    limits.holdings.to_int64(), limits.transfer_bytes,
    limits.retained_bytes, limits.execution_bytes]
}

///|
fn installed_effect_plan_matches(
  plan : ClientInstalledEffectManagedPlan,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  physical_equal(plan.prepared, prepared) && physical_equal(plan.request, request)
}

///|
fn installed_effect_add_extent(total : Int64, count : Int64, bytes : Int64) -> Int64? {
  if total < 0L || count < 0L || bytes < 0L ||
    (bytes > 0L && count > (9223372036854775807L - total) / bytes) {
    None
  } else {
    Some(total + count * bytes)
  }
}

///|
fn installed_effect_limits_fit(
  required : @resources.LedgerLimits,
  admitted : @resources.LedgerLimits,
) -> Bool {
  required.planning_work <= admitted.planning_work &&
  required.attempts <= admitted.attempts && required.holdings <= admitted.holdings &&
  required.transfer_bytes <= admitted.transfer_bytes &&
  required.retained_bytes <= admitted.retained_bytes &&
  required.execution_bytes <= admitted.execution_bytes
}

///|
/// Quote the original selected implementation and checked row inventory before
/// importing the existing managed parent. All still-retained operation bodies
/// overlap the Compute/Source inventory; no phase is discarded based on a
/// Promise, a consumed response or an assumed early physical retirement.
pub fn prepare_installed_effect_managed_plan(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  selected_operations : Array[ClientInstalledEffectOperationDemand],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  if !installed_effect_managed_request_matches(prepared, request) {
    return Err(ForeignOriginal)
  }
  // Preserve this supplier's existing purpose boundary. Model/serialization
  // work cannot acquire its different scope merely by carrying operation DATA.
  if !installed_managed_owner_shape_supported(Effect(prepared), false) {
    return Err(Unsupported)
  }
  let headers = @checked.effect_program_static_headers(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  if selected_operations.length() != @syntax.effect_header_count(headers) {
    return Err(ForeignOriginal)
  }
  for index, demand in selected_operations {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if !physical_equal(demand.prepared, prepared) ||
      demand.member_index != index ||
      demand.stage_index != @syntax.effect_header_stage(header) ||
      demand.effect_id != @syntax.effect_header_id(header) {
      return Err(ForeignOriginal)
    }
  }
  let graph = installed_managed_owner_graph(Effect(prepared))
  let invocation = query_time.map(original => (original, request))
  let source_free = if @strategy.graph_captured_prefix(graph) == 0 {
    source_free_installed_managed_preparation_owned(
      Effect(prepared), installed_contracts, values_body, fragment_body, ordered_body, false,
      query_time=invocation,
    )
  } else { None }
  let acquisitions = match prepare_installed_managed_acquisitions_owned(
    Effect(prepared), declarations, query_contract_body, evidence_contract_body,
    installed_contracts, values_body, fragment_body, ordered_body,
    query_time=invocation,
  ) { Err(issue) => return Err(issue); Ok(value) => value }
  let sequences = match source_free {
    Some(value) => value.sequences
    None => match prepare_client_local_sequences_owned(
      Effect(prepared), installed_contracts, values_body, fragment_body, ordered_body,
      query_time=invocation,
    ) {
      Some(value) => value
      None => return Err(Unsupported)
    }
  }
  let captures = []
  for acquisition in acquisitions {
    guard installed_row_capture_capacity(acquisition) is Some(capacity) else { return Err(Unsupported) }
    captures.push(capacity)
  }
  // Retain the same concrete Local configuration used for this quote. Opening
  // Compute never selects the sequences or derives their capacity a second time.
  let (compute_sequences, capacity_plan, local_capacity) = match source_free {
    Some(original) => (original.sequences, original.capacity_plan, {
      limits: original.limits,
      provider_retained: original.provider_retained_bytes,
      provider_execution: original.provider_execution_bytes,
      simultaneous: None,
    })
    None => {
      let first = @strategy.graph_captured_prefix(graph)
      let tail = []
      for task in first..<sequences.length() { tail.push(sequences[task]) }
      let max_rows = @publication_host.client_standard_values_sequence_limits().max_rows
      let configuration = client_local_capacity_plan(tail, max_rows, graph=Some(graph), graph_offset=first)
      let inputs = Array::make(tail.length(), 0)
      for task in first..<sequences.length() {
        guard @strategy.graph_task_input_count(graph, task) is Some(count) else {
          return Err(Unsupported)
        }
        inputs[task-first] = count
      }
      guard client_local_sequence_capacity_original(
        tail, @strategy.graph_task_count(graph), capacity_plan=Some(configuration),
        retained_inputs=Some(inputs), max_rows~,
      ) is Some(capacity) else { return Err(Unsupported) }
      (tail, configuration, capacity)
    }
  }
  let compute_limits = match source_free {
    Some(original) => {
      if !declarations.is_empty() || !transport_bytes.is_empty() ||
        !transport_execution_bytes.is_empty() { return Err(Unsupported) }
      original.limits
    }
    None => {
      if @strategy.graph_captured_prefix(graph) == 0 { return Err(Unsupported) }
      guard multi_captured_capacity_limits_selected(
        graph, captures.map(value => (value.retained_bytes, value.execution_bytes)),
        transport_bytes, transport_execution_bytes, sequences, local_capacity=Some(local_capacity),
      ) is Some(limits) else { return Err(Unsupported) }
      limits
    }
  }

  // The exact checked graph/sequence inventory supplies the domain-independent
  // row bound. The existing executor guard remains the fallback for open input;
  // no independent row ceiling is introduced for the operation implementation.
  let workspace : ClientLocalSchemaProofWorkspace = {owners:0,rows:0,input_rows:0,row_bounds:0}
  let proof = client_local_schema_proof_inventory(sequences, graph=Some(graph), scalar_only=false, workspace=Some(workspace))
  let rows = match proof {
    Some({closed_rows: Some(count), ..}) => count
    _ => @publication_host.client_standard_values_sequence_limits().max_rows
  }
  let mut attempts = compute_limits.attempts.to_int64()
  let mut held_children = 0L
  let mut transfer = compute_limits.transfer_bytes
  let mut retained = compute_limits.retained_bytes
  let mut execution = compute_limits.execution_bytes
  let mut extent_count = 0L
  let mut remaining = @publication_host.client_standard_program_preparation_limits().max_graph_work
  for demand in selected_operations {
    for (extents, multiplicity) in [(demand.member_extents, 1), (demand.row_extents, rows)] {
      if extents.length() > remaining { return Err(Unsupported) }
      remaining -= extents.length()
      extent_count += extents.length().to_int64()
      for extent in extents {
        let count = multiplicity.to_int64()
        if count < 0L || held_children > 2147483647L - count {
          return Err(Unsupported)
        }
        held_children += count
        if extent.physical_attempt {
          if attempts > 2147483647L - count { return Err(Unsupported) }
          attempts += count
        }
        guard installed_effect_add_extent(transfer, count, extent.transfer_bytes) is Some(next) else {
          return Err(Unsupported)
        }
        transfer = next
        let r = @execution.execution_capacity_retained_bytes(extent.capacity)
        let e = @execution.execution_capacity_execution_bytes(extent.capacity)
        guard installed_effect_add_extent(retained, count, r) is Some(next) else { return Err(Unsupported) }
        retained = next
        guard installed_effect_add_extent(execution, count, e) is Some(next) else { return Err(Unsupported) }
        execution = next
      }
    }
  }
  // Own only new plan/demand/container controls. Borrow installed immutable
  // extents, contract/Program bodies and generated originals once at their
  // actual owners. Array spare capacity uses the existing pinned builtin rule.
  let members = selected_operations.length().to_int64()
  let sources = declarations.length().to_int64()
  let time_holder = if query_time is Some(_) { 1L } else { 0L }
  let acquisition_slots = closed_values_append_capacity(declarations.length()).unwrap()
  let owner_slots = closed_values_append_capacity(workspace.owners).unwrap()
  let row_slots = closed_values_append_capacity(workspace.rows).unwrap()
  let input_slots = closed_values_append_capacity(workspace.input_rows).unwrap()
  // Fixed retained controls: Plan(1H,19R,4W), six Array wrappers/backings
  // (12H,6R,6W), two LedgerLimits(2H,0R,12W), source-free Some(1H,1R,1W).
  // Operations/declarations are exact copies; transport arrays own scalar
  // slots; acquisitions are appended with pinned spare capacity. Per selected
  // member: Demand(1H,4R,2W) and two exact extent-reference copies(4H,2R,2W).
  // The optional query-time holder adds one Some header/payload/tag. Its
  // original caller-owned sample/Run backing is borrowed, not copied here.
  // Existing generated sequences and acquisition bodies remain charged by
  // their original Compute/capture components, not decoded/copied here.
  let controls = preparation_representation_cost({
    record_headers: 16L + 5L * members + sources + time_holder,
    reference_slots: 26L + members + sources + 2L * acquisition_slots + 6L * members + extent_count + 2L * sources + time_holder,
    scalar_words: 23L + 5L * sources + 4L * members + time_holder,
    owned_utf16_units: 0L, owned_wire_bytes: 0L,
  }).unwrap()
  // Scratch controls: workspace/Some, proof inventory/Some/closed-row Some,
  // three Array wrappers/backings, two multiplicity tuples/their Array, three
  // live checked-add Options, two layouts and the final Result (21H,12R,40W).
  // Seen-owner and optional-row slots hold references; input-row slots hold
  // scalar words. Only actual retained Some row bounds own extra carriers.
  // These peaks are recorded by the SAME traversal, including refusal paths;
  // neither work counts nor a failed proof allocate hypothetical backing.
  let temporary = preparation_representation_cost({
    record_headers: 21L + workspace.row_bounds.to_int64() + 2L * time_holder, reference_slots: 12L + owner_slots + row_slots + 3L * time_holder,
    scalar_words: 40L + input_slots + 2L * workspace.row_bounds.to_int64() + time_holder,
    owned_utf16_units: 0L, owned_wire_bytes: 0L,
  }).unwrap()
  if retained > 9223372036854775807L - controls ||
    execution > 9223372036854775807L - controls - temporary {
    return Err(Unsupported)
  }
  let limits = { ..compute_limits, attempts: attempts.to_int(), transfer_bytes: transfer,
    retained_bytes: retained + controls, execution_bytes: execution + controls + temporary }
  Ok({prepared, request, query_time, declarations: declarations.copy(), acquisitions, captures, transport_bytes: transport_bytes.copy(),
    transport_execution_bytes: transport_execution_bytes.copy(), installed_contracts,
    values_body, fragment_body, ordered_body, operations: selected_operations.copy(),
    source_free, sequences, compute_sequences, capacity_plan,
    provider_retained_bytes: local_capacity.provider_retained,
    provider_execution_bytes: local_capacity.provider_execution,
    rows, held_children: held_children.to_int(), compute_limits, limits})
}

///|
pub fn prepared_installed_effect_managed_requirements(
  plan : ClientInstalledEffectManagedPlan,
) -> Array[Int64] {
  installed_effect_requirements(plan.limits)
}

///|
/// Live management capacity only, not a consumed send/row count or authority.
pub fn prepared_installed_effect_managed_capture_children(
  plan : ClientInstalledEffectManagedPlan,
) -> Int {
  plan.held_children
}

///|
/// Checked row, member and live-holder extents for the same Run consumer.
/// This cannot be used as installation-time catalogue admission or authority.
pub fn prepared_installed_effect_managed_shape(
  plan : ClientInstalledEffectManagedPlan,
) -> (Int, Int, Int) {
  (plan.rows, plan.operations.length(), plan.held_children)
}

///|
/// The execution consumer borrows the exact acquisition admitted during quote,
/// not a re-created requirement/contract tuple with equal bytes.
pub fn prepared_installed_effect_managed_source(
  plan : ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Result[
  (@row_source_host.RowDeclaration, @planning.QueryRequirement, @row_source_host.RowAcquisition, ClientInstalledCaptureCapacity),
  ClientInstalledManagedRunIssue,
] {
  guard plan.declarations.get(occurrence) is Some(declaration) &&
    plan.acquisitions.get(occurrence) is Some(acquisition) &&
    plan.captures.get(occurrence) is Some(capacity) else {
    return Err(Unsupported)
  }
  Ok((declaration, @row_source_host.row_acquisition_requirement(acquisition), acquisition, capacity))
}

///|
/// Same immutable selected extent, not an operation admission. Runtime/Account,
/// request, Site, claim and actual before-use debit remain with the caller.
pub fn prepared_installed_effect_managed_operation(
  plan : ClientInstalledEffectManagedPlan,
  member_index : Int,
  per_row : Bool,
  operation_index : Int,
  operation : String,
) -> Result[ClientInstalledEffectOperationExtent, ClientInstalledManagedRunIssue] {
  guard plan.operations.get(member_index) is Some(demand) else { return Err(ForeignOriginal) }
  let selected = if per_row { demand.row_extents } else { demand.member_extents }
  guard selected.get(operation_index) is Some(value) else { return Err(Unsupported) }
  if value.operation != operation { return Err(ForeignOriginal) }
  Ok(value)
}

///|
pub fn installed_effect_operation_extent_capacity(
  value : ClientInstalledEffectOperationExtent,
) -> @execution.ExecutionCapacity { value.capacity }

///|
pub fn installed_effect_operation_extent_transfer(
  value : ClientInstalledEffectOperationExtent,
) -> Int64 { value.transfer_bytes }

///|
pub fn installed_effect_operation_extent_physical(
  value : ClientInstalledEffectOperationExtent,
) -> Bool { value.physical_attempt }
