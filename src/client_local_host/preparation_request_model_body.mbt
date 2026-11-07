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
    owner.program_domain_compilation_inputs is Some(_) ||
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
/// Compile the selected single Model component on the original Request. The
/// existing construction borrow keeps Graph and output live through this
/// call and until the actual module/Plan/Scope has retained them. Provider,
/// codec and complete Model construction backing still belongs to the caller.
pub fn[I] prepare_request_model_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  graph : @publication_host.ClientInferPlanGraph,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(graph.owner, prepared) &&
    owner.program_compilation is None &&
    owner.program_model is None &&
    !owner.program_body_attempted &&
    owner.program_artifact_work is None &&
    owner.program_artifact_work_issue is None else {
    return Err(Preparation(ForeignOriginal))
  }
  if !installed_managed_run_shape_supported(prepared, true) {
    // A selected component must come from this SAME Request's backed Graph
    // constructor. Continue that original compiler for plain or serialized
    // input; module/provider/Scope/adoption remain separate original duties.
    let retained = match owner.program_domain_compilation_inputs {
      Some(RequestModelGraph(_, _, _, original)) => Some(original)
      Some(RequestModelCompilation(_, _, _, original)) => Some(original)
      _ => None
    }
    guard retained is Some(original) &&
      physical_equal(original, graph) &&
      installed_managed_owner_shape_supported(
        Pure(prepared),
        true,
        model=Some(graph),
      ) else {
      return Err(Installed(Unsupported))
    }
  }
  match owner.program_domain_compilation_inputs {
    Some(RequestModelGraph(old_manifests, old_limits, old_contracts, original)) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        physical_equal(original, graph) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_compilation_inputs = Some(
        RequestModelCompilation(manifests, compilation_limits, contracts, graph),
      )
    }
    Some(
      RequestSerializationGraph(
        old_manifests,
        old_limits,
        old_contracts,
        component
      )
    ) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        graph.serialization is Some(original) &&
        physical_equal(original, component) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_compilation_inputs = Some(
        RequestModelCompilation(manifests, compilation_limits, contracts, graph),
      )
    }
    Some(
      RequestModelCompilation(
        old_manifests,
        old_limits,
        old_contracts,
        old_model
      )
    ) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        physical_equal(old_model, graph) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    Some(_) => return Err(Preparation(ForeignOriginal))
    None =>
      owner.program_domain_compilation_inputs = Some(
        RequestModelCompilation(manifests, compilation_limits, contracts, graph),
      )
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @publication_host.bind_prepared_client_compiler_contracts(
          prepared,
          contracts.original.value.ordered_contract,
        ) {
        Err(_) => return Err(Preparation(ForeignOriginal))
        Ok(_) => ()
      }
      let result = prepare_request_compilation_owned(
        owner, input, prepared, manifests, compilation_limits,
      )
      match result {
        Err(issue) => return Err(issue)
        Ok(@publication_host.Tasks(compilation)) => {
          owner.phase = ModelPlanReserved
          Ok(compilation)
        }
        _ => Err(Preparation(ForeignOriginal))
      }
    },
    () => {
      ignore(finish_request_program_artifact_work(owner))
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
    },
  )
}

///|
/// Compile the complete ordered vector already constructed and retained on
/// this SAME Request. Reuse the existing multi-INFER compiler, measurement,
/// work token and TaskCompilation. The selected vector must contain every
/// SAME retained graph in order; its wrapper supplies no new body authority.
/// Callers do not rebuild graphs or supply another parent/compiled artifact.
pub fn[I] prepare_request_models_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : Array[@publication_host.ClientInferPlanGraph],
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is None &&
    owner.program_model is None &&
    !owner.program_body_attempted &&
    owner.program_artifact_work is None &&
    owner.program_artifact_work_issue is None else {
    return Err(Preparation(ForeignOriginal))
  }
  let graphs = match owner.program_domain_compilation_inputs {
    Some(
      RequestModelGraphs(old_manifests, old_limits, old_contracts, originals)
    ) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        @publication_host.prepared_client_composed_infer_occurrences(prepared)
        is Some(occurrences) &&
        occurrences.length() > 1 &&
        originals.length() == occurrences.length() &&
        selected.length() == originals.length() else {
        return Err(Preparation(ForeignOriginal))
      }
      for index, graph in originals {
        if !physical_equal(graph, selected[index]) ||
          !physical_equal(graph.owner, prepared) ||
          !@publication_host.client_infer_occurrence_matches_plan(
            occurrences[index],
            graph,
          ) {
          return Err(Preparation(ForeignOriginal))
        }
      }
      originals
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  owner.program_domain_compilation_inputs = Some(
    RequestModelsCompilation(manifests, compilation_limits, contracts, graphs),
  )
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @publication_host.bind_prepared_client_compiler_contracts(
          prepared,
          contracts.original.value.ordered_contract,
        ) {
        Err(_) => return Err(Preparation(ForeignOriginal))
        Ok(_) => ()
      }
      match
        prepare_request_compilation_owned(
          owner, input, prepared, manifests, compilation_limits,
        ) {
        Err(issue) => Err(issue)
        Ok(@publication_host.Tasks(compilation)) => {
          owner.phase = ModelPlanReserved
          Ok(compilation)
        }
        _ => Err(Preparation(ForeignOriginal))
      }
    },
    () => {
      ignore(finish_request_program_artifact_work(owner))
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
    },
  )
}

///|
/// Bind the actual Model module and its optional Content prefix from this
/// original Request. The Plan record was admitted by the existing input borrow;
/// no caller-supplied prefix or equal compiler can replace its retained original.
pub fn[I] prepare_request_model_source_free_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(same_input) &&
    physical_equal(same_input, input) &&
    owner.program_source_free is Some(selected_module) &&
    physical_equal(selected_module, original) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelCompilation(_, _, _, same_graph)) &&
    physical_equal(same_graph, graph) &&
    owner.program_model is None else {
    return Err(ForeignOriginal)
  }
  let content_prefix = match (graph.serialization, owner.program_content) {
    (None, NoContent) => None
    (Some(_), SerializationContent(prefix)) => Some(prefix)
    _ => return Err(ForeignOriginal)
  }
  prepare_installed_mock_model_source_free_plan(
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    content_prefix~,
    bootstrap~,
  )
}

///|
/// Bind the existing installed Node read envelope to this SAME Request Plan.
/// Layout correspondence and declared extents are DATA; the existing Plan and
/// Scope constructors still reserve their complete overlap on the parent.
/// No read, Scope, claim, permission or provider is issued by this binding.
pub fn[I] prepare_request_node_model_source_free_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  match
    @publication_host.check_client_node_model_preparation_layout(
      layout, graph, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(ModelLayout(issue))
    Ok(_) => ()
  }
  guard layout is Some(layout) else {
    return Err(ModelLayout(@publication_host.Unavailable))
  }
  prepare_request_model_source_free_plan(
    owner,
    input,
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    layout.retained_bytes,
    layout.execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    bootstrap~,
  )
}

///|
/// Bind the actual Model module and its optional Content prefix from this
/// original Request. The Plan record was admitted by the existing input borrow;
/// no caller-supplied prefix or equal compiler can replace its retained original.
pub fn[I] prepare_request_model_capture_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedCapturePlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(same_input) &&
    physical_equal(same_input, input) &&
    owner.program_captured is Some(selected_module) &&
    physical_equal(selected_module, original) &&
    physical_equal(original.request, request) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelCompilation(_, _, _, same_graph)) &&
    physical_equal(same_graph, graph) &&
    owner.program_model is None else {
    return Err(ForeignOriginal)
  }
  let content_prefix = match (graph.serialization, owner.program_content) {
    (None, NoContent) => None
    (Some(_), SerializationContent(prefix)) => Some(prefix)
    _ => return Err(ForeignOriginal)
  }
  prepare_installed_mock_model_capture_plan_binding(
    original,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    content_prefix~,
    bootstrap~,
  )
}

///|
/// Bind the existing installed Node read envelope to this SAME Request Plan.
/// Layout correspondence and declared extents are DATA; the existing Plan and
/// Scope constructors still reserve their complete overlap on the parent.
/// No read, Scope, claim, permission or provider is issued by this binding.
pub fn[I] prepare_request_node_model_capture_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedCapturePlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  match
    @publication_host.check_client_node_model_preparation_layout(
      layout, graph, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(ModelLayout(issue))
    Ok(_) => ()
  }
  guard layout is Some(layout) else {
    return Err(ModelLayout(@publication_host.Unavailable))
  }
  prepare_request_model_capture_plan(
    owner,
    input,
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    layout.retained_bytes,
    layout.execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    bootstrap~,
  )
}

///|
/// Bind this actual Model Plan before completing the original Prepared body.
/// Fund the actual Scope records and the original census-slot growth before
/// binding. Complete selected Model/read/module/physical constructor overlap
/// remains separate; no codec ceiling or runtime allowance supplies it here.
pub fn[I] prepare_request_model_read_scope(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedModelPlan,
  quantity_limits? : @resources.QuantityAmounts? = None,
) -> Result[
  @publication_host.ClientModelReadScope,
  ClientInstalledManagedRunIssue,
] {
  if plan.models is Some(_) {
    return Err(ForeignOriginal)
  }
  prepare_request_model_read_scopes_owned(
    owner, input, plan, quantity_limits, bind_request_single_model_read_scope,
  )
}

///|
// These module-level binding functions capture nothing. The generic driver
// below performs the original quote/current/census handoff once; no retained
// callback, wrapper, duplicated checker or second admission is introduced.
fn bind_request_single_model_read_scope(
  plan : ClientInstalledManagedModelPlan,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Result[
  @publication_host.ClientModelReadScope,
  @publication_host.ClientModelReadPreparationIssue,
] {
  @publication_host.bind_client_model_read_scope(
    plan.compiled,
    plan.definition,
    plan.graph,
    ledger,
    identity,
  )
}

///|
fn[I, T] prepare_request_model_read_scopes_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedModelPlan,
  quantity_limits : @resources.QuantityAmounts?,
  bind : (
    ClientInstalledManagedModelPlan,
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
  ) -> Result[T, @publication_host.ClientModelReadPreparationIssue],
) -> Result[T, ClientInstalledManagedRunIssue] {
  // A mixed module carries the same already constructed prefix, not a
  // successful quote or a Model Scope standing in for Content retention.
  guard (match (plan.content_prefix, owner.program_content) {
    (None, NoContent) => plan.graph.serialization is None
    (Some(prefix), SerializationContent(original)) =>
      physical_equal(prefix, original) &&
      owner.program_content_request is Some(request) &&
      physical_equal(request, plan.request)
    _ => false
  }) else {
    return Err(ForeignOriginal)
  }
  let quoted = owner.phase == ModelScopeQuoted
  // This Request retained the actual funded module before Plan/Scope entry.
  // A separately reconstructed module with the same compiler is still foreign.
  guard (match
    (
      plan.source_free,
      plan.captured,
      owner.program_source_free,
      owner.program_captured,
    ) {
    (Some(selected), None, Some(original), None) =>
      physical_equal(selected, original)
    (None, Some(selected), None, Some(original)) =>
      physical_equal(selected, original)
    _ => false
  }) else {
    return Err(ForeignOriginal)
  }
  guard (
      (
        owner.phase == ModelPlanReserved &&
        (
          owner.program_model is None ||
          (
            plan.models is Some(_) &&
            owner.program_model is Some(original_plan) &&
            physical_equal(original_plan, plan)
          )
        ) &&
        owner.program_domain_quote is None
      ) ||
      (
        quoted &&
        owner.program_model is Some(selected_plan) &&
        physical_equal(selected_plan, plan) &&
        owner.program_domain_quote is Some(_)
      )
    ) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
    @publication_host.client_compiled_run_matches_tasks(
      plan.compiled,
      prepared,
      compilation,
    ) &&
    !owner.program_body_attempted &&
    physical_equal(plan.prepared, prepared) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  match check_preparation_owned_body_limits(owner.initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !quoted {
    let quote = match
      request_model_scope_construction_quote(
        capacity,
        input,
        plan.max_reservations,
        plan.max_holdings,
        plan.max_delegations,
        model_count=match plan.models {
          None => 1
          Some(models) => models.length()
        },
      ) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    owner.program_model = Some(plan)
    owner.program_domain_quote = Some(quote)
  }
  let (r, e) = owner.program_domain_quote.unwrap()
  owner.phase = Selecting
  // Configure the SAME Request before its original Run binding. This uses
  // Resource's one-shot preparation entrance; no reset or late configuration
  // is permitted. A retry may only observe an already identical configuration.
  let quantities_ready : Result[Unit, ClientInstalledManagedRunIssue] = match
    quantity_limits {
    None => Ok(())
    Some(installed) => {
      let selected = match request_model_plan_quantity_limits(plan, installed) {
        None => return Err(InsufficientCapacity)
        Some(value) => value
      }
      if @resources.quantity_configuration_matches(owner.ledger, Some(selected)) {
        Ok(())
      } else {
        @resources.configure_quantities(owner.ledger, selected).map_err(issue => {
          Ledger(issue)
        })
      }
    }
  }
  // Resource currentness may run the original caller's interruption fence.
  // Preserve that retirement and its primary; never restore a closed parent
  // to ModelScopeQuoted after the quantity configuration check.
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
      if owner.phase != Selecting {
        Err(ForeignOriginal)
      } else {
        match
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
          Ok(_) => {
            guard owner.phase == Selecting &&
              owner.input is Some(original_input) &&
              physical_equal(original_input, input) &&
              owner.program_capacity is Some(original_capacity) &&
              physical_equal(original_capacity, capacity) &&
              owner.program_model is Some(original_plan) &&
              physical_equal(original_plan, plan) &&
              owner.program_domain_quote is Some(current_quote) &&
              current_quote.0 == r &&
              current_quote.1 == e else {
              if owner.phase == Selecting {
                owner.phase = ModelScopeQuoted
              }
              return Err(ForeignOriginal)
            }
            match
              @resources.preparation_capacity_inventory_original(
                capacity, input,
              ) {
              Err(issue) => Err(Preparation(issue))
              Ok(identity) =>
                bind(plan, owner.ledger, identity).map_err(issue => {
                  ModelRead(issue)
                })
            }
          }
        }
      }
  }
  if result is Ok(_) {
    owner.program_domain_quote = None
  }
  owner.phase = if result is Ok(_) {
    ModelPlanReserved
  } else {
    ModelScopeQuoted
  }
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
  if result is Ok(_) {
    // The selected module/Plan owns this SAME artifact; no sizing inventory
    // has a later consumer. Keep the peak debit until construction unwinds.
    owner.program_compilation = None
    owner.program_domain_compilation_inputs = None
    owner.program_artifact_geometry = None
    owner.program_artifact_quote = None
    owner.program_measurement_quote = None
    owner.program_invocation_quote = None
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
  scopes? : Array[@publication_host.ClientModelReadScope]? = None,
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
  let matching_scopes = match (plan.models, scopes) {
    (None, None) =>
      @publication_host.client_model_read_scope_original_inventory(
        scope,
        owner.ledger,
        identity,
      ) &&
      @publication_host.client_model_read_scope_live(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
      )
    (Some(models), Some(originals)) =>
      originals.length() == models.length() &&
      originals.length() > 1 &&
      physical_equal(originals[0], scope) &&
      @publication_host.client_model_read_scopes_match_originals(
        originals,
        plan.compiled,
        plan.definition,
        owner.ledger,
        identity,
      )
    _ => false
  }
  if !matching_scopes {
    return Err(ForeignOriginal)
  }
  let content = owner.program_content
  guard (match (plan.content_prefix, content) {
    (None, NoContent) => true
    (Some(prefix), SerializationContent(original)) =>
      physical_equal(prefix, original) &&
      owner.program_content_request is Some(bound) &&
      physical_equal(bound, request)
    _ => false
  }) else {
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
      // Closed original DATA handoff before another current callback. The
      // adopted Run retains this same prefix until its actual cleanup ACK.
      run.content = content
      owner.program_content = NoContent
      owner.program_content_request = None
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_source_free = None
      owner.program_captured = None
      owner.program_model_direct = None
      owner.program_model = None
      owner.program_compilation = None
      owner.program_domain_compilation_inputs = None
      owner.program_artifact_inputs = None
      owner.program_artifact_geometry = None
      owner.program_artifact_quote = None
      owner.program_measurement_quote = None
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
