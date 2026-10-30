///|
/// Select this Model Plan's actual record before constructing it. An existing
/// Program inventory borrow may remain live. Both borrows use the SAME body,
/// capacity and current callback; grown extents survive either borrow return.
/// This fixed record is not complete Model/compiler/provider/codec backing.
pub fn[I] borrow_request_model_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  if owner.phase == ContentPlanReserved ||
    owner.program_source_free is Some(_) ||
    owner.program_captured is Some(_) ||
    owner.program_artifact_inputs is Some(_) ||
    owner.program_body_attempted {
    return Err(WrongPhase)
  }
  let reserved = owner.phase == ModelPlanReserved
  let (r, e) = match request_program_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let previous_phase = owner.phase
  let capacity = owner.program_capacity.unwrap()
  let prepared = owner.compiled_program.unwrap()
  let (r, e) = if reserved || previous_phase == ProgramPlanReserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    (r, e)
  }
  let (r, e) = if reserved {
    (r, e)
  } else {
    guard @execution.preparation_representation_cost(
        installed_model_plan_record,
      )
      is Some(bytes) &&
      @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Policy)
    }
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) { ModelPlanReserved } else { previous_phase }
  result.map_err(issue => Capacity(issue))
}

///|
/// Bind this actual Model Plan before completing the original Prepared body.
/// The caller has backed and retained its complete selected Model/read/module
/// overlap at the current extents. This call does not derive backing from a
/// codec limit or start another Root/bootstrap/Node admission.
pub fn[I] prepare_request_model_read_scope(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedModelPlan,
) -> Result[
  @publication_host.ClientModelReadScope,
  ClientInstalledManagedRunIssue,
] {
  guard owner.phase == ModelPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_model is None &&
    !owner.program_body_attempted &&
    physical_equal(plan.prepared, prepared) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let available = match
    @resources.node_local_preparation_limits(owner.initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(plan.limits, available) {
    return Err(InsufficientCapacity)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  owner.phase = Selecting
  let result : Result[
    @publication_host.ClientModelReadScope,
    ClientInstalledManagedRunIssue,
  ] = match
    @resources.grow_preparation_capacity_inventory(
      capacity,
      input,
      r,
      e,
      Int::max(request_preparation_borrow_limit, plan.max_reservations),
      plan.max_holdings,
      plan.max_delegations,
    ) {
    Err(issue) => Err(Preparation(issue))
    Ok(_) =>
      match
        @resources.preparation_capacity_inventory_original(capacity, input) {
        Err(issue) => Err(Preparation(issue))
        Ok(identity) =>
          @publication_host.bind_client_model_read_scope(
            plan.compiled,
            plan.definition,
            plan.graph,
            owner.ledger,
            identity,
          ).map_err(issue => ModelRead(issue))
      }
  }
  if result is Ok(_) {
    owner.program_model = Some(plan)
  }
  owner.phase = ModelPlanReserved
  result
}

///|
/// Complete from the SAME Plan retained by the Scope selection. No compiler,
/// sequence, configuration or Model resource is reconstructed. The existing
/// ordinary completion owns the same full peak until this handoff unwinds.
pub fn[I] complete_request_model_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedModelPlan,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ModelPlanReserved &&
    owner.program_model is Some(original) &&
    physical_equal(original, plan) else {
    return Err(ForeignOriginal)
  }
  // Only the original selected Plan reaches this shared body handoff. Its
  // fixed record remains charged, and reentry is fenced by the existing
  // Selecting phase before the capacity engine invokes current.
  owner.phase = ProgramPlanReserved
  let result = match (plan.source_free, plan.captured) {
    (Some(original), None) =>
      complete_request_program_preparation_owned(owner, input, original)
    (None, Some(original)) =>
      complete_request_capture_preparation(owner, input, original)
    _ => Err(ForeignOriginal)
  }
  if owner.phase == ProgramPlanReserved {
    owner.phase = ModelPlanReserved
  }
  result
}

///|
/// The Model Scope remains on the original preparation census through this
/// adoption and its separate physical cleanup acknowledgement. Ordinary entry
/// guards remain unchanged; a missing/foreign Scope is never a fallback.
pub fn[I] begin_request_model_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
  scope : @publication_host.ClientModelReadScope,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_model is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) else {
    return Err(ForeignOriginal)
  }
  let identity = match
    @resources.preparation_capacity_inventory_original(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  if !@publication_host.client_model_read_scope_original_inventory(
      scope,
      owner.ledger,
      identity,
    ) ||
    !@publication_host.client_model_read_scope_live(
      scope,
      plan.compiled,
      plan.definition,
      plan.graph,
    ) {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = adopt_preparation_owned_pure_plan(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan.source_free,
    plan.captured,
  )
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_source_free = None
      owner.program_captured = None
      owner.program_model = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
      owner.submitted_intent = None
      owner.intent_base = None
      owner.intent_peak_live = false
      owner.input = None
      owner.query_syntax = None
      owner.phase = Selected
      Ok(run)
    }
  }
}
