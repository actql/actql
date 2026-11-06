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
  // Pure capture templates are resolved once from the SAME completed Plan.
  // This multiplicity is storage DATA, never an occurrence/authority flag.
  checked_row_capacity : @execution.ExecutionCapacity?
  // Resolved once from the SAME checked effect_id, never a caller name amount.
  checked_effect_id_capacity : @execution.ExecutionCapacity?
  // An optional immutable upper bound for later original-input construction.
  // The Plan admits capacity now; only an actually owned input can grow this
  // SAME token toward maximum before its callback, within the original Root.
  maximum : ClientInstalledEffectOperationExtent?
  // The same member's Host Preview parser is selected later from its owned
  // wire. Its immutable codec limits remain a bound, not initial tree storage.
  host_input_limits : @source.ParseLimits?
}

///|
pub fn prepare_installed_effect_operation_extent(
  operation : String,
  capacity : @execution.ExecutionCapacity,
  transfer_bytes : Int64,
  physical_attempt : Bool,
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  if operation.is_empty() ||
    transfer_bytes < 0L ||
    (!physical_attempt && transfer_bytes != 0L) {
    return Err(Unsupported)
  }
  Ok({
    operation,
    capacity,
    transfer_bytes,
    physical_attempt,
    checked_row_capacity: None,
    checked_effect_id_capacity: None,
    maximum: None,
    host_input_limits: None,
  })
}

///|
/// Stage an existing operation, not a new occurrence or authority. Both
/// original templates retain their same operation, purpose and transfer.
/// Checked row/id multiplicities are resolved by the same existing traversal.
pub fn prepare_installed_effect_staged_extent(
  initial : ClientInstalledEffectOperationExtent,
  maximum : ClientInstalledEffectOperationExtent,
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  let host_input_changed = match
    (initial.host_input_limits, maximum.host_input_limits) {
    (None, None) => false
    (Some(a), Some(b)) =>
      a.max_input_bytes != b.max_input_bytes ||
      a.max_nodes != b.max_nodes ||
      a.max_depth != b.max_depth
    _ => true
  }
  if initial.maximum is Some(_) ||
    maximum.maximum is Some(_) ||
    initial.operation != maximum.operation ||
    initial.physical_attempt != maximum.physical_attempt ||
    initial.transfer_bytes != maximum.transfer_bytes ||
    (initial.checked_row_capacity is Some(_)) !=
    (maximum.checked_row_capacity is Some(_)) ||
    (initial.checked_effect_id_capacity is Some(_)) !=
    (maximum.checked_effect_id_capacity is Some(_)) ||
    host_input_changed ||
    !installed_effect_capacity_within(initial.capacity, maximum.capacity) {
    return Err(Unsupported)
  }
  Ok({ ..initial, maximum: Some(maximum), })
}

///|
fn installed_effect_capacity_within(
  required : @execution.ExecutionCapacity,
  maximum : @execution.ExecutionCapacity,
) -> Bool {
  @execution.execution_capacity_retained_bytes(required) <=
  @execution.execution_capacity_retained_bytes(maximum) &&
  @execution.execution_capacity_execution_bytes(required) <=
  @execution.execution_capacity_execution_bytes(maximum)
}

///|
/// One member capture retains storage for all checked input rows, but remains
/// ONE child/occurrence. Resolve this template only after the original Compute
/// Plan has supplied its row inventory. It cannot select a physical attempt,
/// transfer or a row-operation slot, and does not reserve or grant anything.
pub fn prepare_installed_effect_capture_extent(
  operation : String,
  fixed_capacity : @execution.ExecutionCapacity,
  capacity_per_checked_row : @execution.ExecutionCapacity,
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  if operation.is_empty() {
    return Err(Unsupported)
  }
  Ok({
    operation,
    capacity: fixed_capacity,
    transfer_bytes: 0L,
    physical_attempt: false,
    checked_row_capacity: Some(capacity_per_checked_row),
    checked_effect_id_capacity: None,
    maximum: None,
    host_input_limits: None,
  })
}

///|
// The recipe Owner returns fixed/per-row/.../effect-id quantities together.
// This is immutable constructor DATA; no resource, row, attempt or transfer
// grant is issued. The original checked descriptor resolves the final term.
pub fn prepare_installed_effect_capture_recipe_extent(
  operation : String,
  recipe : Array[@execution.ExecutionCapacity],
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  if recipe.length() != 6 {
    return Err(Unsupported)
  }
  prepare_installed_effect_capture_extent(operation, recipe[0], recipe[1]).map(original => {
    ..original,
    checked_effect_id_capacity: Some(recipe[5]),
  })
}

///|
/// Bind a closed installing parser's original limits to this same capture.
/// Actual input construction remains on the existing Run control reservation.
pub fn prepare_installed_effect_host_input_capture_recipe_extent(
  operation : String,
  recipe : Array[@execution.ExecutionCapacity],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(Unsupported)
  }
  // Standard CREATE owns fixed/per-row capture quantities. Described
  // drivers additionally retain their original checked effect-id role.
  let capture = if recipe.length() == 2 {
    prepare_installed_effect_capture_extent(operation, recipe[0], recipe[1])
  } else {
    prepare_installed_effect_capture_recipe_extent(operation, recipe)
  }
  capture.map(original => {
    ..original,
    host_input_limits: Some({
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }),
  })
}

///|
pub fn installed_effect_managed_plan_has_host_input(
  plan : ClientInstalledEffectManagedPlan,
) -> Bool {
  plan.operations.any(demand => {
    demand.member_extents.any(extent => extent.host_input_limits is Some(_))
  })
}

///|
fn resolve_installed_effect_id_extent(
  original : ClientInstalledEffectOperationExtent,
  effect_id : String,
) -> ClientInstalledEffectOperationExtent? {
  let original = match original.maximum {
    None => original
    Some(value) => {
      guard resolve_installed_effect_id_extent(value, effect_id)
        is Some(resolved) else {
        return None
      }
      if physical_equal(value, resolved) {
        original
      } else {
        { ..original, maximum: Some(resolved), }
      }
    }
  }
  let maximum = original.maximum
  guard original.checked_effect_id_capacity is Some(rate) else {
    return Some(original)
  }
  if original.physical_attempt || original.transfer_bytes != 0L {
    return None
  }
  guard @execution.execution_capacity_inventory_add(
      @execution.execution_capacity_retained_bytes(original.capacity),
      QuotedBytes,
      @execution.execution_capacity_retained_bytes(rate),
      effect_id.length(),
    )
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      @execution.execution_capacity_execution_bytes(original.capacity),
      QuotedBytes,
      @execution.execution_capacity_execution_bytes(rate),
      effect_id.length(),
    )
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(capacity) else {
    return None
  }
  if maximum is Some(bound) &&
    !installed_effect_capacity_within(capacity, bound.capacity) {
    return None
  }
  Some({ ..original, capacity, checked_effect_id_capacity: None, })
}

///|
fn resolve_installed_effect_capture_extent(
  original : ClientInstalledEffectOperationExtent,
  rows : Int,
) -> ClientInstalledEffectOperationExtent? {
  let original = match original.maximum {
    None => original
    Some(value) => {
      guard resolve_installed_effect_capture_extent(value, rows)
        is Some(resolved) else {
        return None
      }
      if physical_equal(value, resolved) {
        original
      } else {
        { ..original, maximum: Some(resolved), }
      }
    }
  }
  let maximum = original.maximum
  guard original.checked_row_capacity is Some(per_row) else {
    return Some(original)
  }
  if original.physical_attempt || original.transfer_bytes != 0L {
    return None
  }
  guard @execution.execution_capacity_inventory_add(
      @execution.execution_capacity_retained_bytes(original.capacity),
      QuotedBytes,
      @execution.execution_capacity_retained_bytes(per_row),
      rows,
    )
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      @execution.execution_capacity_execution_bytes(original.capacity),
      QuotedBytes,
      @execution.execution_capacity_execution_bytes(per_row),
      rows,
    )
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(capacity) else {
    return None
  }
  if maximum is Some(bound) &&
    !installed_effect_capacity_within(capacity, bound.capacity) {
    return None
  }
  Some({ ..original, capacity, checked_row_capacity: None, })
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
  // Implementation material constructed before an individual body borrow
  // (for example the original grant). The SAME Run's existing control debit
  // owns it; it is not another occurrence, physical attempt or transfer.
  controls_per_row : @execution.ExecutionCapacity?
}

///|
pub fn prepare_installed_effect_operation_demand(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  member_extents : Array[ClientInstalledEffectOperationExtent],
  row_extents : Array[ClientInstalledEffectOperationExtent],
) -> Result[
  ClientInstalledEffectOperationDemand,
  ClientInstalledManagedRunIssue,
] {
  let work = @publication_host.client_standard_program_preparation_limits().max_graph_work
  if member_extents.length() > work ||
    row_extents.length() > work - member_extents.length() ||
    (member_extents.is_empty() && row_extents.is_empty()) {
    return Err(Unsupported)
  }
  // A capture template co-funds one enclosing member. A row slot would apply
  // checked multiplicity twice, and cannot carry this member-only recipe.
  if row_extents.any(extent => {
      extent.checked_row_capacity is Some(_) ||
      extent.checked_effect_id_capacity is Some(_)
    }) {
    return Err(Unsupported)
  }
  let descriptor = match
    @publication_host.client_effect_member_descriptor(
      prepared, stage_index, effect_id, work,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let resolved_members = []
  for original in member_extents {
    guard resolve_installed_effect_id_extent(original, effect_id)
      is Some(resolved) else {
      return Err(Unsupported)
    }
    resolved_members.push(resolved)
  }
  Ok({
    prepared,
    member_index: descriptor.0,
    stage_index,
    effect_id,
    member_extents: resolved_members,
    row_extents: row_extents.copy(),
    controls_per_row: None,
  })
}

///|
/// Retain original implementation control DATA on the same checked member.
/// No caller row amount is accepted: the original completed Plan supplies its
/// row bound. The existing control reservation precedes any Node caller work.
pub fn prepare_installed_effect_operation_demand_with_controls(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  member_extents : Array[ClientInstalledEffectOperationExtent],
  row_extents : Array[ClientInstalledEffectOperationExtent],
  controls_per_row : @execution.ExecutionCapacity,
) -> Result[
  ClientInstalledEffectOperationDemand,
  ClientInstalledManagedRunIssue,
] {
  prepare_installed_effect_operation_demand(
    prepared, stage_index, effect_id, member_extents, row_extents,
  ).map(original => { ..original, controls_per_row: Some(controls_per_row), })
}

///|
/// Same checked Program/request and installed contract originals for the quote
/// and actual managed-parent constructor. The original Node service separately
/// binds its runtime/installation and retains this plan before fallible start.
/// This plan creates no second Resource owner and carries no current Allow.
// `_observed_*` fields retain exact bound observations for white-box tests;
// production consumes the admitted totals, not these diagnostic projections.
struct ClientInstalledEffectManagedPlan {
  prepared : @publication_host.PreparedClientEffectComputation
  request : @publication_host.ClientRequestIdentity
  query_time : @publication_host.ClientQueryTimePreparation?
  model : ClientInstalledEffectModelDemand?
  content : ClientInstalledEffectContentPreparation?
  declarations : Array[@row_source_host.RowDeclaration]
  direct_occurrences : @publication_host.ClientDirectAcquisitionOccurrences?
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
  configuration : ClientPreparedLocalConfiguration
  rows : Int
  closed_rows : Int?
  held_children : Int
  operation_control_capacity : @execution.ExecutionCapacity
  operation_control_idle_execution : Int64
  _observed_compute_limits : @resources.LedgerLimits
  limits : @resources.LedgerLimits
}

///|
fn installed_effect_requirements(
  limits : @resources.LedgerLimits,
) -> Array[Int64] {
  [
    limits.planning_work.to_int64(),
    limits.attempts.to_int64(),
    limits.holdings.to_int64(),
    limits.transfer_bytes,
    limits.retained_bytes,
    limits.execution_bytes,
  ]
}

///|
fn installed_effect_plan_matches(
  plan : ClientInstalledEffectManagedPlan,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  physical_equal(plan.prepared, prepared) &&
  physical_equal(plan.request, request) &&
  (match plan.content {
    None => true
    Some(original) =>
      installed_effect_content_preparation_matches(original, prepared)
  })
}

///|
fn installed_effect_limits_fit(
  required : @resources.LedgerLimits,
  admitted : @resources.LedgerLimits,
) -> Bool {
  required.planning_work <= admitted.planning_work &&
  required.attempts <= admitted.attempts &&
  required.holdings <= admitted.holdings &&
  required.transfer_bytes <= admitted.transfer_bytes &&
  required.retained_bytes <= admitted.retained_bytes &&
  required.execution_bytes <= admitted.execution_bytes
}

///|
// Fixed additional material of the control phase quote: one retained Plan
// scalar, two checked-add carriers and two new workspace projection/results.
// The SAME layout is backed by Request BEFORE Plan construction and recorded
// in the resulting Plan; it is not a later spare allowance or another Root.
fn installed_effect_control_phase_quote_capacity() -> @execution.ExecutionCapacity {
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 2L,
      reference_slots: 0L,
      // The shared Compute preparation retains one original tail aggregate;
      // the quote retains the two phase accumulators, also when unselected.
      scalar_words: 9L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  }).unwrap()
}

///|
// The optional original Effect graph, current source/owner/target/bound
// carriers and nested row Option add at most six headers/references/tags;
// selected-source/max/count and scratch controls add four scalar words. No new arrays,
// copied graph or persistent inventory are introduced. Provider phase folding
// additionally holds its checked-add Options, result tuple/Some and caller
// phase-add Options, borrowed capture/transport selections, scalar arguments,
// loop accumulators and the caller's completed phase values. Keep their full
// simultaneous envelope rather than reusing hypothetical expression slots. The
// Request backs this
// scratch BEFORE Plan construction; the finished Plan records the same cost.
fn installed_effect_source_result_bound_scratch_bytes() -> Int64 {
  @execution.preparation_representation_cost({
    record_headers: 16L,
    reference_slots: 14L,
    scalar_words: 36L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
/// Quote the original selected implementation and checked row inventory before
/// importing the existing managed parent. All retained operation bodies overlap
/// Compute/Source. The normal pure-constructor loop retains each output but
/// returns its original workspace before its next callback. Physical and
/// implementation-control peaks remain fully simultaneous; neither a Promise
/// nor a received response implies early physical retirement.
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
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  source_providers? : Array[@execution.ExecutionCapacity]? = None,
  model? : ClientInstalledEffectModelDemand? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  prepare_installed_effect_managed_plan_owned(
    prepared,
    request,
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    provider_factory~,
    query_time~,
    source_providers~,
    model~,
    content~,
    runtime_admission~,
  )
}

///|
fn prepare_installed_effect_managed_plan_owned(
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
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  source_providers? : Array[@execution.ExecutionCapacity]? = None,
  model? : ClientInstalledEffectModelDemand? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
  source_inputs? : Array[ClientInstalledEffectSourceInput]? = None,
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  if !installed_effect_managed_request_matches(prepared, request) {
    return Err(ForeignOriginal)
  }
  // A Model plan retains its nominal checked binding and selected demand.
  // Ordinary operation DATA alone cannot convert the purpose or fund a Scope.
  if model is Some(selected) &&
    (
      !physical_equal(selected.prepared, prepared) ||
      !installed_effect_model_demand_complete(selected)
    ) {
    return Err(ForeignOriginal)
  }
  if content is Some(original) &&
    (
      !installed_effect_content_preparation_matches(original, prepared) ||
      (match model {
        None => false
        Some(selected) =>
          !physical_equal(original.compiled, selected.compiled) ||
          !physical_equal(original.compilation, selected._compilation) ||
          !physical_equal(original.definition, selected.definition)
      })
    ) {
    return Err(ForeignOriginal)
  }
  if !installed_managed_owner_shape_supported(
      Effect(prepared),
      model is Some(_),
      model_graphs=model.bind(value => {
        value.components.map(originals => {
          originals.map(original => original.graph)
        })
      }),
      content~,
    ) {
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
  // This is the selected original installed reader declaration, not a grant,
  // capacity credit or a replacement acquisition. The Plan constructs each
  // original acquisition once and retains its complete provider overlap.
  let provider_sources = match source_inputs {
    Some(inputs) => {
      if source_providers is Some(_) {
        return Err(ForeignOriginal)
      }
      let mut providers = 0
      for input in inputs {
        if input is InstalledEffectRowSource(_, Some(_)) {
          providers += 1
        }
      }
      providers
    }
    None =>
      match source_providers {
        None => 0
        Some(providers) => {
          if providers.is_empty() || providers.length() != declarations.length() {
            return Err(ForeignOriginal)
          }
          providers.length()
        }
      }
  }
  let source_free = if @strategy.graph_captured_prefix(graph) == 0 {
    Some(
      match
        source_free_installed_managed_preparation_owned(
          Effect(prepared),
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
          model is Some(_),
          model_graphs=model.bind(value => {
            value.components.map(originals => {
              originals.map(original => original.graph)
            })
          }),
          content~,
          query_time=invocation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      },
    )
  } else {
    None
  }
  let direct_occurrences = if @strategy.graph_captured_prefix(graph) == 0 {
    None
  } else {
    Some(
      match installed_direct_occurrences_owned(Effect(prepared)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      },
    )
  }
  let (declarations, acquisitions, captures) = match source_inputs {
    Some(inputs) =>
      match
        prepare_installed_effect_source_inputs(
          prepared, inputs, query_contract_body, evidence_contract_body, installed_contracts,
          values_body, fragment_body, ordered_body, direct_occurrences, invocation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    None => {
      let acquisitions = match
        prepare_installed_managed_acquisitions_owned(
          Effect(prepared),
          declarations,
          query_contract_body,
          evidence_contract_body,
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
          query_time=invocation,
          direct_occurrences~,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      let captures = []
      for index, acquisition in acquisitions {
        let selected = match source_providers {
          None => installed_row_capture_capacity(acquisition)
          Some(providers) =>
            installed_provider_row_capture_capacity(
              acquisition,
              Some(providers[index]),
            )
        }
        guard selected is Some(capacity) else { return Err(Unsupported) }
        captures.push(capacity)
      }
      (declarations, acquisitions, captures)
    }
  }
  let sequences = match source_free {
    Some(value) => value.sequences
    None =>
      match
        prepare_client_local_sequences_owned(
          Effect(prepared),
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
          query_time=invocation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  let compute = match
    prepare_installed_compute_preparation(
      Effect(prepared),
      source_free,
      sequences,
      captures,
      transport_bytes,
      transport_execution_bytes,
      true,
      base => {
        let providers = provider_factory(base)
        match content {
          None => providers
          Some(original) => {
            let selected = providers.copy()
            selected.push(original.provider)
            selected
          }
        }
      },
      runtime_admission~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let compute_sequences = compute.sequences
  let capacity_plan = compute.capacity_plan
  let configuration = compute.configuration
  let compute_limits = compute.limits

  let original_compute_limits = compute_limits
  let mut reading_execution = compute_limits.execution_bytes
  let mut completed_execution = compute_limits.execution_bytes
  if provider_sources > 0 && provider_sources == captures.length() {
    guard installed_effect_provider_execution_phases(
        captures,
        transport_execution_bytes,
        compute.tail_execution_bytes,
        compute_limits.retained_bytes,
      )
      is Some((reading, completed)) else {
      return Err(Unsupported)
    }
    reading_execution = reading
    completed_execution = completed
  }
  let compute_limits = match model {
    None => compute_limits
    Some(selected) =>
      match @resources.add_ledger_limits(compute_limits, selected.limits) {
        Some(value) => value
        None => return Err(InsufficientCapacity)
      }
  }

  // The exact checked graph/sequence inventory supplies the domain-independent
  // row bound. The existing executor guard still rejects oversized open input;
  // it is never a prediction charged as already retained rows.
  let workspace : ClientLocalSchemaProofWorkspace = {
    owners: 0,
    rows: 0,
    input_rows: 0,
    row_bounds: 0,
  }
  let proof = if source_free is Some(_) && content is None {
    // This branch retained exactly these sequences and this capacity Plan
    // from the same completed source-free preparation above. Reuse its
    // immutable inventory instead of traversing the same schemas again.
    capacity_plan.demand_inventory
  } else {
    // Select the exact checked Effect endpoints, not the largest intermediate
    // Compute relation. SERIALIZE preserves its full input/sort demand in the
    // Compute Plan while producing one row for the original STORE consumer.
    // The same existing traversal retains unknown/foreign refusal and records
    // its actual scratch alongside the already retained Compute inventory.
    client_local_schema_proof_inventory(
      sequences,
      graph=Some(graph),
      scalar_only=false,
      workspace=Some(workspace),
      effect_sources=Some(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      ),
    )
  }
  let closed_rows = proof.bind(value => value.closed_rows)
  let rows = closed_rows.unwrap_or(
    @publication_host.client_standard_values_sequence_limits().max_rows,
  )
  // Absence is not a zero-row fact. Retain the executor's original rejection
  // ceiling above, but fund only fixed member controls until completed inputs
  // supply their original inventory on this SAME adopted Run.
  let funded_rows = closed_rows.unwrap_or(0)
  // Complete the selected capture templates from the SAME immutable row
  // inventory above. Static extents keep their original identity. No second
  // schema traversal, Plan preparation or caller-supplied row count is used.
  let resolved_operations = selected_operations.copy()
  for index, demand in selected_operations {
    if closed_rows is Some(_) &&
      demand.member_extents.any(extent => extent.checked_row_capacity is Some(_)) {
      let member_extents = demand.member_extents.copy()
      for slot, original in demand.member_extents {
        guard resolve_installed_effect_capture_extent(original, rows)
          is Some(extent) else {
          return Err(Unsupported)
        }
        member_extents[slot] = extent
      }
      resolved_operations[index] = { ..demand, member_extents, }
    }
  }
  let mut attempts = compute_limits.attempts.to_int64()
  let mut held_children = 0L
  let mut child_limit = 0L
  let mut transfer = compute_limits.transfer_bytes
  let mut retained = compute_limits.retained_bytes
  let mut execution = compute_limits.execution_bytes
  let mut constructor_workspace = 0L
  let mut extent_count = 0L
  let mut staged_extents = 0L
  let mut controlled_members = 0L
  let mut implementation_control_retained = 0L
  let mut implementation_control_workspace = 0L
  let mut remaining = @publication_host.client_standard_program_preparation_limits().max_graph_work
  for demand in resolved_operations {
    if demand.controls_per_row is Some(original) {
      controlled_members += 1L
      guard @execution.execution_capacity_inventory_add(
          implementation_control_retained,
          QuotedBytes,
          @execution.execution_capacity_retained_bytes(original),
          funded_rows,
        )
        is Some(next_retained) else {
        return Err(Unsupported)
      }
      implementation_control_retained = next_retained
      if funded_rows > 0 {
        // Actual grant/Ledger/projector callbacks use one same-Run control
        // frame, complete synchronously and retain their outputs separately.
        let control_workspace = @execution.execution_capacity_execution_bytes(
            original,
          ) -
          @execution.execution_capacity_retained_bytes(original)
        implementation_control_workspace = Int64::max(
          implementation_control_workspace, control_workspace,
        )
        constructor_workspace = Int64::max(
          constructor_workspace, control_workspace,
        )
      }
    }
    for
      (extents, multiplicity, ceiling) in [
        (demand.member_extents, 1, 1),
        (demand.row_extents, funded_rows, rows),
      ] {
      if extents.length() > remaining {
        return Err(Unsupported)
      }
      remaining -= extents.length()
      extent_count += extents.length().to_int64()
      for original in extents {
        let extent = match
          resolve_installed_effect_capture_extent(original, funded_rows) {
          Some(value) => value
          None => return Err(Unsupported)
        }
        if extent.maximum is Some(_) {
          staged_extents += 1L
        }
        let count = multiplicity.to_int64()
        if count < 0L || held_children > 2147483647L - count {
          return Err(Unsupported)
        }
        held_children += count
        let ceiling = ceiling.to_int64()
        if child_limit > 2147483647L - ceiling {
          return Err(Unsupported)
        }
        child_limit += ceiling
        if extent.physical_attempt {
          if attempts > 2147483647L - count {
            return Err(Unsupported)
          }
          attempts += count
        }
        guard @execution.execution_capacity_inventory_add(
            transfer,
            QuotedBytes,
            extent.transfer_bytes,
            multiplicity,
          )
          is Some(next) else {
          return Err(Unsupported)
        }
        transfer = next
        let r = @execution.execution_capacity_retained_bytes(extent.capacity)
        let e = @execution.execution_capacity_execution_bytes(extent.capacity)
        guard @execution.execution_capacity_inventory_add(
            retained,
            QuotedBytes,
            r,
            multiplicity,
          )
          is Some(next) else {
          return Err(Unsupported)
        }
        retained = next
        // Normal pure children retain R before Source/Preview and enter E
        // only for their synchronous callback. The actual row/member loops
        // await completion before the next callback. Keep every returned R;
        // reuse only that completed scratch. A failed/async child stops the
        // enclosing loop and keeps E under its SAME original reservation.
        // Physical bodies and control allowances do not use this reuse law.
        let held_execution = if extent.physical_attempt { e } else { r }
        if !extent.physical_attempt && multiplicity > 0 {
          constructor_workspace = Int64::max(constructor_workspace, e - r)
        }
        guard @execution.execution_capacity_inventory_add(
            execution,
            QuotedBytes,
            held_execution,
            multiplicity,
          )
          is Some(next) else {
          return Err(Unsupported)
        }
        execution = next
      }
    }
  }
  if provider_sources > 0 && provider_sources == captures.length() {
    // Only the same ordinary provider profile selects this phase cut. Its
    // actual Row completion returns the reader's transient E-R first; all
    // acquisition/evidence/scratch and earlier capture remainders remain.
    // Keep Model/physical/held implementation material fully additive. The
    // normal Host retains inactive controls before Source, and its row Effect
    // callbacks first pin completed Compute sources. Source readers never
    // receive that controlConstruction function. Its workspace belongs to
    // the later constructor phase; the full retained control remains below.
    let coexist = execution - original_compute_limits.execution_bytes
    guard @execution.execution_capacity_inventory_add(
        coexist,
        QuotedBytes,
        reading_execution,
        1,
      )
      is Some(reading) &&
      @execution.execution_capacity_inventory_add(
        coexist,
        QuotedBytes,
        completed_execution,
        1,
      )
      is Some(completed) &&
      @execution.execution_capacity_inventory_add(
        completed,
        QuotedBytes,
        constructor_workspace,
        1,
      )
      is Some(completed) else {
      return Err(Unsupported)
    }
    execution = Int64::max(reading, completed)
  } else {
    guard @execution.execution_capacity_inventory_add(
        execution,
        QuotedBytes,
        constructor_workspace,
        1,
      )
      is Some(with_constructor_workspace) else {
      return Err(Unsupported)
    }
    execution = with_constructor_workspace
  }
  // Own only new plan/demand/container controls. Borrow installed immutable
  // extents, contract/Program bodies and generated originals once at their
  // actual owners. Array spare capacity uses the existing pinned builtin rule.
  let members = selected_operations.length().to_int64()
  let sources = captures.length().to_int64()
  let time_holder = if query_time is Some(_) { 1L } else { 0L }
  let model_holder = if model is Some(_) { 1L } else { 0L }
  let acquisition_slots = closed_values_append_capacity(captures.length()).unwrap()
  let owner_slots = closed_values_append_capacity(workspace.owners).unwrap()
  let row_slots = closed_values_append_capacity(workspace.rows).unwrap()
  let input_slots = closed_values_append_capacity(workspace.input_rows).unwrap()
  // Fixed retained controls: Plan(1H,20R,4W) and its operation-control
  // capacity(1H,0R,2W), its optional original closed-row inventory, six Array wrappers/backings
  // (12H,6R,6W), two LedgerLimits(2H,0R,12W), source-free Some(1H,1R,1W).
  // Operations/declarations are exact copies; transport arrays own scalar
  // slots; acquisitions are appended with pinned spare capacity. Per selected
  // member: Demand(1H,5R,2W) and two exact extent-reference copies(4H,2R,2W).
  // The added optional control field borrows its original implementation
  // capacity; a selected Some adds1H1R1W, never another copy of that capacity.
  // The optional query-time holder adds one Some header/payload/tag. Its
  // original caller-owned sample/Run backing is borrowed, not copied here.
  // The Model demand adds its record(1H,7R,7W), limits(1H,0R,6W),
  // Some(1H,1R,1W), and one Plan reference, only when selected. All six
  // compilation/definition/occurrence originals remain borrowed references.
  // Each provider capture additionally retains its Some/tuple(2H,3R,1W)
  // around the original acquisition and selected reader capacity. The capacity
  // itself is borrowed from the installation, never reconstructed from numbers.
  // Its original read handoff tuple adds 1H,4R and no scalar payload; retain
  // the full per-Source overlap until that Source's original preparation ends.
  // Existing generated sequences and acquisition bodies remain charged by
  // their original Compute/capture components, not decoded/copied here.
  // Each staged maximum retains its resolved extent/capacity and Some pair
  // beside the initial extent (4H8R8W). Immutable installation inputs are borrowed.
  let controls = @execution.preparation_representation_cost({
    record_headers: 17L +
    (if closed_rows is Some(_) { 1L } else { 0L }) +
    5L * members +
    controlled_members +
    sources +
    time_holder +
    3L * model_holder +
    3L * provider_sources.to_int64() +
    4L * staged_extents,
    reference_slots: 28L +
    members +
    sources +
    2L * acquisition_slots +
    6L * members +
    members +
    controlled_members +
    extent_count +
    2L * sources +
    time_holder +
    9L * model_holder +
    7L * provider_sources.to_int64() +
    8L * staged_extents,
    scalar_words: 26L +
    (if closed_rows is Some(_) { 1L } else { 0L }) -
    model_holder +
    controlled_members +
    5L * sources +
    4L * members +
    time_holder +
    14L * model_holder +
    provider_sources.to_int64() +
    8L * staged_extents,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // Scratch controls: workspace/Some, proof inventory/Some/closed-row Some,
  // three Array wrappers/backings, two multiplicity tuples/their Array, three
  // live checked-add Options, two layouts and the final Result (21H,12R,40W).
  // Seen-owner and optional-row slots hold references; input-row slots hold
  // scalar words. Only actual retained Some row bounds own extra carriers.
  // These peaks are recorded by the SAME traversal, including refusal paths;
  // neither work counts nor a failed proof allocate hypothetical backing.
  // Provider capture preparation is sequential: its one live argument Some,
  // temporary summed ExecutionCapacity and returned Some add 3H,2R,4W once,
  // not once per selected Source. Retained provider pairs are counted above.
  // The Model limit addition retains one intermediate limits record and its
  // Some through this quote only (2H,1R,7W); it is not a second Run limit.
  let provider_scratch = if provider_sources > 0 { 1L } else { 0L }
  let source_result_scratch = if source_free is None || content is Some(_) {
    installed_effect_source_result_bound_scratch_bytes()
  } else {
    0L
  }
  let temporary = @execution.preparation_representation_cost({
      record_headers: 21L +
      2L +
      workspace.row_bounds.to_int64() +
      2L * time_holder +
      3L * provider_scratch +
      2L * model_holder,
      reference_slots: 12L +
      owner_slots +
      row_slots +
      3L * time_holder +
      2L * provider_scratch +
      model_holder,
      // Empty/selected implementation control accumulator and the original
      // base capacity coexist with their combined result during this quote.
      // One sequential-constructor scratch accumulator and its selected
      // held-execution scalar are live in that same existing traversal.
      // Additional control phase material uses its one shared layout below.
      scalar_words: 42L +
      6L +
      input_slots +
      2L * workspace.row_bounds.to_int64() +
      time_holder +
      4L * provider_scratch +
      7L * model_holder,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap() +
    source_result_scratch
  let control_phase = installed_effect_control_phase_quote_capacity()
  let phase_retained = @execution.execution_capacity_retained_bytes(
    control_phase,
  )
  let phase_workspace = @execution.execution_capacity_execution_bytes(
      control_phase,
    ) -
    phase_retained
  if controls > 9223372036854775807L - phase_retained ||
    temporary > 9223372036854775807L - phase_workspace {
    return Err(Unsupported)
  }
  guard installed_direct_occurrences_layout(
      @strategy.graph_captured_prefix(graph),
    )
    is Some((selector_retained, _)) &&
    @execution.checked_preparation_add_product(controls, selector_retained, 1L)
    is Some(controls) &&
    @execution.checked_preparation_add_product(controls, phase_retained, 1L)
    is Some(controls) else {
    return Err(InsufficientCapacity)
  }
  let temporary = temporary + phase_workspace
  if retained > 9223372036854775807L - controls ||
    execution > 9223372036854775807L - controls - temporary {
    return Err(Unsupported)
  }
  let operation_control_capacity = match
    installed_effect_operation_control_capacity(
      held_children.to_int(),
      recovery_members=selected_operations.length(),
    ) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  // The existing mutable child/index inventory can grow before any control
  // callback. Keep that original base workspace prepaid in the same token.
  guard @execution.execution_capacity_inventory_add(
      @execution.execution_capacity_execution_bytes(operation_control_capacity),
      QuotedBytes,
      implementation_control_retained,
      1,
    )
    is Some(operation_control_idle_execution) else {
    return Err(Unsupported)
  }
  guard @execution.execution_capacity_inventory_add(
      implementation_control_retained,
      QuotedBytes,
      implementation_control_workspace,
      1,
    )
    is Some(implementation_control_execution) else {
    return Err(Unsupported)
  }
  guard @execution.execution_capacity(
      implementation_control_retained, implementation_control_execution,
    )
    is Some(implementation_control_capacity) &&
    @execution.add_execution_capacity(
      operation_control_capacity, implementation_control_capacity,
    )
    is Some(operation_control_capacity) else {
    return Err(Unsupported)
  }
  let control_retained = @execution.execution_capacity_retained_bytes(
    operation_control_capacity,
  )
  if retained + controls > 9223372036854775807L - control_retained ||
    execution + controls + temporary >
    9223372036854775807L - operation_control_idle_execution {
    return Err(Unsupported)
  }
  let limits = {
    ..compute_limits,
    attempts: attempts.to_int(),
    transfer_bytes: transfer,
    retained_bytes: retained + controls + control_retained,
    execution_bytes: execution +
    controls +
    temporary +
    operation_control_idle_execution,
  }
  Ok({
    prepared,
    request,
    query_time,
    model,
    content,
    declarations: declarations.copy(),
    acquisitions,
    direct_occurrences,
    captures,
    transport_bytes: transport_bytes.copy(),
    transport_execution_bytes: transport_execution_bytes.copy(),
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    operations: resolved_operations,
    source_free,
    sequences,
    compute_sequences,
    capacity_plan,
    configuration,
    rows,
    closed_rows,
    held_children: child_limit.to_int(),
    operation_control_capacity,
    operation_control_idle_execution,
    _observed_compute_limits: original_compute_limits,
    limits,
  })
}

///|
pub fn prepared_installed_effect_managed_requirements(
  plan : ClientInstalledEffectManagedPlan,
) -> Array[Int64] {
  installed_effect_requirements(plan.limits)
}

///|
/// Original operation-coordinate ceiling, not an initial reservation, observed
/// row count, consumed send or authority. Unknown rows grow the SAME Run token.
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
  (
    @row_source_host.RowDeclaration,
    @planning.QueryRequirement,
    @row_source_host.RowAcquisition,
    ClientInstalledCaptureCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard installed_effect_source_row_index(plan, occurrence) is Some(row_index) &&
    plan.declarations.get(row_index) is Some(declaration) &&
    plan.acquisitions.get(row_index) is Some(acquisition) &&
    plan.captures.get(occurrence) is Some(capacity) else {
    return Err(Unsupported)
  }
  Ok(
    (
      declaration,
      @row_source_host.row_acquisition_requirement(acquisition),
      acquisition,
      capacity,
    ),
  )
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
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  guard plan.operations.get(member_index) is Some(demand) else {
    return Err(ForeignOriginal)
  }
  let selected = if per_row {
    demand.row_extents
  } else {
    demand.member_extents
  }
  guard selected.get(operation_index) is Some(value) else {
    return Err(Unsupported)
  }
  if value.operation != operation {
    return Err(ForeignOriginal)
  }
  Ok(value)
}

///|
pub fn installed_effect_operation_extent_capacity(
  value : ClientInstalledEffectOperationExtent,
) -> @execution.ExecutionCapacity {
  value.capacity
}

///|
pub fn installed_effect_operation_extent_transfer(
  value : ClientInstalledEffectOperationExtent,
) -> Int64 {
  value.transfer_bytes
}

///|
pub fn installed_effect_operation_extent_physical(
  value : ClientInstalledEffectOperationExtent,
) -> Bool {
  value.physical_attempt
}
