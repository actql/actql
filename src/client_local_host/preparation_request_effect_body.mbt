///|
/// Continue the SAME Request reservation to its actual Effect Plan body type.
/// The already completed original compiler/candidate is retained, never redone.
pub fn[I] continue_request_effect_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.PreparedClientEffectComputation,
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramCheck &&
    owner.effect_capacity is None &&
    owner.program_capacity is None &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == CompilationComplete &&
    child.compiled_effect is Some(prepared) &&
    child.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  clear_request_parameter_source(owner)
  if owner.program_json is Some(source) {
    match clear_program_json_preparation(source) {
      Err(issue) => return Err(ProgramJson(issue))
      Ok(_) => ()
    }
  }
  owner.phase = Selecting
  child.busy = true
  let next : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan] = match
    @resources.continue_preparation_capacity(owner.capacity, input) {
    Err(issue) => {
      child.busy = false
      owner.phase = ProgramCheck
      return Err(Capacity(issue))
    }
    Ok(value) => value
  }
  owner.effect_capacity = Some(next)
  owner.compiled_effect = Some(prepared)
  owner.program_data = Some(data)
  transfer_program_check_input(child)
  child.busy = false
  owner.program_check = None
  owner.computation_limits = None
  owner.program_json = None
  owner.phase = EffectCompiled
  Ok(prepared)
}

///|
/// Fund the Core sequence/Plan construction coexistence before the actual
/// constructor. Selected provider/request/response backing remains the normal
/// Host's independent domain on this same parent, never a connector knob.
fn[I] request_effect_plan_quote(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard (
      owner.phase == EffectCompiled ||
      owner.phase == EffectPlanQuoted ||
      owner.phase == EffectPlanReserved
    ) &&
    owner.effect_capacity is Some(capacity) &&
    owner.program_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == EffectCompiled {
    let (r, e) = match
      original_request_plan_construction_quote(capacity, input, data) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    guard owner.compiled_effect is Some(prepared) &&
      @publication_host.client_effect_direct_acquisition_count(
        prepared, 1000000,
      )
      is Ok(source_count) &&
      installed_direct_occurrences_layout(source_count)
      is Some((selector_retained, selector_execution)) &&
      @execution.checked_preparation_add_product(r, selector_retained, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(e, selector_execution, 1L)
      is Some(e) else {
      return Err(Policy)
    }
    // The captured Effect's existing schema walk also resolves its SAME
    // checked Result endpoints. Back the additional fixed scratch before
    // that call; no new graph, proof arrays or caller-selected bounds.
    let scratch = match owner.compiled_effect {
      Some(prepared) if @strategy.graph_captured_prefix(
          @strategy.checked_effect_computation_graph(
            @publication_host.prepared_client_effect_computation_graph(prepared),
          ),
        ) >
        0 ||
        !@publication_host.prepared_client_effect_serialization_occurrences(
          prepared,
        ).is_empty() => installed_effect_source_result_bound_scratch_bytes()
      _ => 0L
    }
    let control_phase = installed_effect_control_phase_quote_capacity()
    guard @execution.checked_preparation_add_product(
        r,
        @execution.execution_capacity_retained_bytes(control_phase),
        1L,
      )
      is Some(r) &&
      @execution.checked_preparation_add_product(
        e,
        @execution.execution_capacity_execution_bytes(control_phase),
        1L,
      )
      is Some(e) &&
      @execution.checked_preparation_add_product(e, scratch, 1L) is Some(e) else {
      return Err(Policy)
    }
    owner.program_plan_quote = Some((r, e))
    owner.phase = EffectPlanQuoted
  }
  Ok(owner.program_plan_quote.unwrap())
}

///|
pub fn[I] reserve_request_effect_plan(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.phase != EffectCompiled && owner.phase != EffectPlanQuoted {
    return Err(WrongPhase)
  }
  let (r, e) = match request_effect_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.effect_capacity.unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  owner.phase = if result is Ok(_) {
    EffectPlanReserved
  } else {
    EffectPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Same Effect compiler DATA borrowed for its original Plan constructor. The
/// final body type remains the actual Effect Plan; this token cannot invent it.
pub fn[I] borrow_request_effect_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  ClientRequestPreparationIssue,
] {
  let (r, e) = match request_effect_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.effect_capacity.unwrap()
  let prepared = owner.compiled_effect.unwrap()
  let reserved = owner.phase == EffectPlanReserved
  let (r, e) = if reserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) || reserved {
    EffectPlanReserved
  } else {
    EffectPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Bind the selected original Model to this preparation's existing census
/// before completing its Plan or issuing Source/read children. The caller
/// retains the selected original. Fund this Owner's Scope records and the
/// Resource-owned census-slot delta before binding; runtime Model/body and
/// complete physical Host/provider overlap remain their separate domains.
/// The returned Scope must remain with that owner through adoption refusal
/// and receive its actual cleanup acknowledgement before parent retirement.
pub fn[I] prepare_request_effect_model_read_scope(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
  quantity_limits? : @resources.QuantityAmounts? = None,
) -> Result[
  @publication_host.ClientModelReadScope,
  ClientInstalledManagedRunIssue,
] {
  if plan.model is Some(selected) && selected.components is Some(_) {
    return Err(ForeignOriginal)
  }
  prepare_request_effect_model_scopes_owned(
    owner,
    input,
    plan,
    quantity_limits,
    (selected, ledger, identity) => {
      @publication_host.bind_client_model_read_scope(
        selected.compiled,
        selected.definition,
        selected.graph,
        ledger,
        identity,
        model_limits=Some(selected.model_limits),
      )
    },
  )
}

///|
pub fn[I] prepare_request_effect_models_read_scopes(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
  quantity_limits? : @resources.QuantityAmounts? = None,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  ClientInstalledManagedRunIssue,
] {
  guard plan.model is Some(selected) && selected.components is Some(_) else {
    return Err(ForeignOriginal)
  }
  prepare_request_effect_model_scopes_owned(
    owner,
    input,
    plan,
    quantity_limits,
    (selected, ledger, identity) => {
      let originals = selected.components.unwrap()
      @publication_host.bind_client_effect_model_read_scopes(
        selected._compilation,
        selected.compiled,
        selected.definition,
        ledger,
        identity,
        originals.map(value => value.read_retained_bytes),
        originals.map(value => value.read_execution_bytes),
      )
    },
  )
}

///|
fn[I, T] prepare_request_effect_model_scopes_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
  quantity_limits : @resources.QuantityAmounts?,
  bind : (
    ClientInstalledEffectModelDemand,
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
  ) -> Result[T, @publication_host.ClientModelReadPreparationIssue],
) -> Result[T, ClientInstalledManagedRunIssue] {
  let quoted = owner.phase == EffectModelScopeQuoted
  guard (
      (
        owner.phase == EffectPlanReserved &&
        owner.effect_plan is None &&
        owner.program_domain_quote is None
      ) ||
      (
        quoted &&
        owner.effect_plan is Some(selected_plan) &&
        physical_equal(selected_plan, plan) &&
        owner.program_domain_quote is Some(_)
      )
    ) &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    physical_equal(plan.prepared, prepared) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard plan.model is Some(selected) else { return Err(Unsupported) }
  if !installed_effect_model_demand_complete(selected) {
    return Err(ForeignOriginal)
  }
  match check_preparation_owned_effect_limits(owner.initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !quoted {
    let quote = match
      request_model_scope_construction_quote(
        capacity,
        input,
        selected.max_reservations,
        selected.max_holdings,
        selected.max_delegations,
        model_count=selected.components
          .map(value => value.length())
          .unwrap_or(1),
      ) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    // Keep the original Plan and absolute quote before current can fail.
    // A retry consumes this same quote, never another relative increment.
    owner.effect_plan = Some(plan)
    owner.program_domain_quote = Some(quote)
  }
  let (r, e) = owner.program_domain_quote.unwrap()
  owner.phase = Selecting
  // The original six input/borrower slots already exist. Growing this same
  // census retains their backing and the selected Model maxima; it never
  // replaces preparation history with a new pristine inventory.
  let quantities_ready : Result[Unit, ClientInstalledManagedRunIssue] = match
    quantity_limits {
    None => Ok(())
    Some(installed) => {
      let quantities = match
        request_model_group_quantity_limits(
          selected.graph,
          None,
          installed,
          effect_models=selected.components,
        ) {
        None => return Err(InsufficientCapacity)
        Some(value) => value
      }
      // Same preparation-only Resource entrance as Pure Model. An identical
      // retry observes its original configuration; it never resets history.
      if @resources.quantity_configuration_matches(
          owner.ledger,
          Some(quantities),
        ) {
        Ok(())
      } else {
        @resources.configure_quantities(owner.ledger, quantities).map_err(issue => {
          Ledger(issue)
        })
      }
    }
  }
  if owner.phase != Selecting {
    return match quantities_ready {
      Err(issue) => Err(issue)
      Ok(_) => Err(ForeignOriginal)
    }
  }
  let result : Result[T, ClientInstalledManagedRunIssue] = match
    quantities_ready {
    Err(issue) => Err(issue)
    Ok(_) =>
      match
        @resources.grow_preparation_capacity_inventory(
          capacity,
          input,
          r,
          e,
          Int::max(request_preparation_borrow_limit, selected.max_reservations),
          selected.max_holdings,
          selected.max_delegations,
        ) {
        Err(issue) => Err(Preparation(issue))
        Ok(_) => {
          guard owner.phase == Selecting &&
            owner.input is Some(original_input) &&
            physical_equal(original_input, input) &&
            owner.effect_capacity is Some(original_capacity) &&
            physical_equal(original_capacity, capacity) &&
            owner.effect_plan is Some(original_plan) &&
            physical_equal(original_plan, plan) &&
            owner.program_domain_quote is Some(current_quote) &&
            current_quote.0 == r &&
            current_quote.1 == e else {
            if owner.phase == Selecting {
              owner.phase = EffectModelScopeQuoted
            }
            return Err(ForeignOriginal)
          }
          match
            @resources.preparation_capacity_inventory_original(capacity, input) {
            Err(issue) => Err(Preparation(issue))
            Ok(identity) =>
              bind(selected, owner.ledger, identity).map_err(issue => {
                ModelRead(issue)
              })
          }
        }
      }
  }
  if result is Ok(_) {
    owner.program_domain_quote = None
  }
  owner.phase = if result is Ok(_) {
    EffectPlanReserved
  } else {
    EffectModelScopeQuoted
  }
  result
}

///|
/// Complete with the actual original selected Plan. No independently rebuilt
/// plan, request, configuration or prepared computation can stand in for it.
pub fn[I] complete_request_effect_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    physical_equal(plan.prepared, prepared) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_plan is Some(original) && !physical_equal(original, plan) {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  if owner.effect_plan is None {
    owner.effect_plan = Some(plan)
  }
  owner.program_body_attempted = true
  owner.phase = Selecting
  let result = @resources.complete_preparation_capacity(
    capacity, input, plan, r, e,
  )
  owner.phase = if result is Ok(_) { EffectBodyReady } else { EffectBodyFailed }
  result.map_err(issue => Capacity(issue))
}

///|
pub fn[I] borrow_request_effect_preparation(
  owner : ClientRequestPreparation[I],
) -> Result[
  @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == EffectBodyReady &&
    owner.effect_capacity is Some(capacity) else {
    return Err(WrongPhase)
  }
  owner.phase = Selecting
  let result = @resources.borrow_preparation_body(capacity)
  owner.phase = EffectBodyReady
  result.map_err(issue => Capacity(issue))
}

///|
/// The existing Effect Run adopts this SAME initial admission and original
/// Plan body. Existing current permission, dispatch and retirement duties stay.
pub fn[I] begin_request_effect_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == EffectBodyReady &&
    owner.input is Some(input) &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    owner.effect_plan is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_effect_managed_run_original(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
  )
  finish_request_effect_run_adoption(owner, result)
}

///|
/// Adopt the SAME completed Model Plan and previously retained Scope. The
/// ordinary entry above still rejects Model; neither entry chooses a purpose
/// from caller DATA or starts another Node child/bootstrap reservation.
pub fn[I] begin_request_effect_model_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
  scope : @publication_host.ClientModelReadScope,
  scopes? : Array[@publication_host.ClientModelReadScope]? = None,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == EffectBodyReady &&
    owner.input is Some(input) &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    owner.effect_plan is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_effect_model_run(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
    owner.ledger,
    scope,
    scopes~,
  )
  finish_request_effect_run_adoption(owner, result)
}

///|
fn[I] finish_request_effect_run_adoption(
  owner : ClientRequestPreparation[I],
  result : Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue],
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  match result {
    Err(issue) => {
      owner.phase = EffectBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.effect_capacity = None
      owner.compiled_effect = None
      owner.effect_plan = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_domain_quote = None
      owner.program_domain_compilation_inputs = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
      clear_request_source_input(owner)
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
