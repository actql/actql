///|
/// The Model component is a child of the original Request. Keep the Scope
/// and Read before an input, activation or later authority check can refuse.
priv struct StoredPortableModelMember {
  graph : @host.ClientInferPlanGraph
  limits : @infer.Limits
  provider : @model.AdmittedStructuredModelProvider
  quantities : @model.ModelQuantityCapacity
  model_retained_bytes : Int64
  model_execution_bytes : Int64
  scope_bytes : Int
  scope_nodes : Int
  dispatch_extent : (Int, Int, Int)
  dispatch_clock : Ref[String?]
  mut dispatch : @host.ClientInferDispatchAdmission?
  mut entry : @model.ModelCallEntry?
  mut entry_journal : PortableModelEntryJournal?
  mut capture : @host.ClientModelRawCaptureRegistration?
  mut capture_capacity : @resources.CapacityReservation?
  mut transport : @model.ModelPhysicalCall?
  mut request_material : Int?
  mut transport_worker : PortableModelHttpWorker
  mut transport_stop : Bool
  mut raw_output : Int?
  mut raw_save : @model.ModelRawCaptureSave?
  mut raw_capacity : @resources.CapacityReservation?
  mut raw_borrow : @buffers.BufferBorrow?
  mut raw_plaintext_bytes : Int
  mut raw_store : PortableModelRawStore?
  mut settlement : PortableModelSettlement?
  mut scope : @host.ClientModelReadScope?
  mut read : @host.ClientModelReadPreparation?
  mut active : @infer.Execution?
  mut publication_output : @infer.OutputUse?
  mut issue : @infer.Issue?
}

///|
priv struct StoredPortableModelRun {
  request : @host.ClientRequestIdentity
  compiled : @host.ClientCompiledRun
  definition : @publication.PublicationContract
  profile : @environment.ModelResponseProfileInstallation
  response_profile : @environment.ModelResponseProfile
  tls_ca : (String, String)?
  observe_egress : () -> @host.ClientInferEgressObservation?
  members : Array[StoredPortableModelMember]
  mut adopted : @local_host.ClientInstalledManagedRun?
  mut sources : StoredPortableModelSourceEvidence?
}

///|
fn portable_model_module_provider(
  run : StoredPortableModelRun,
  selected_task : StoredPortableModelMember,
  prefix : @execution.GeneratedSequence,
  suffix : @execution.GeneratedSequence?,
) -> @local_compute.ManagedProvider {
  let graph = selected_task.graph
  let limits = selected_task.limits
  @infer.composed_local_provider_with_workspace(
    graph.occurrence,
    limits,
    (current, inputs, prepaid_prefix) => {
      guard selected_task.scope is Some(scope) &&
        run.adopted is Some(_) &&
        selected_task.read is None &&
        selected_task.active is None else {
        return Err(@infer.InvalidAdvance)
      }
      let egress = match
        @host.admit_client_infer_occurrence_egress(
          graph.occurrence,
          graph.execution,
          run.observe_egress,
        ) {
        Ok(admitted) => admitted
        Err(issue) => return Err(@infer.Model(@model.Egress(issue)))
      }
      let prepared_prefix = match prepaid_prefix {
        Some(prepared) => prepared
        None => {
          guard @execution.borrow_generated_component_workspace(current, prefix)
            is Some(prepared) else {
            return Err(@infer.InvalidAdvance)
          }
          prepared
        }
      }
      let prepared_suffix = match suffix {
        None => None
        Some(original) => {
          guard @execution.borrow_generated_component_workspace(
              current, original,
            )
            is Some(prepared) else {
            return Err(@infer.InvalidAdvance)
          }
          Some(prepared)
        }
      }
      let retained = limits.mapping.logical.max_live_value_bytes
      let execution = limits.identity.wire.max_bytes.to_int64()
      let active = match
        @infer.start_scoped_portable_chat_composed(
          graph.occurrence,
          graph,
          prepared_prefix,
          inputs,
          selected_task.provider,
          run.profile,
          limits,
          run.compiled,
          run.definition,
          scope,
          retained,
          execution,
          selected_task.model_retained_bytes,
          selected_task.model_execution_bytes,
          read => selected_task.read = Some(read),
          sources=run.sources.map(evidence => evidence.selection),
        ) {
        Err(issue) => return Err(issue)
        Ok(active) => active
      }
      selected_task.active = Some(active)
      // Retain the installed Run on this exact execution while its input is
      // still unadvanced. The later issuer must read this same binding.
      if @infer.bind_run(active, run.compiled, run.definition) is Err(_) {
        return Err(@infer.Model(@model.OutputIdentity))
      }
      // The Python continuation enters through the durable Call boundary.
      // Neither a checked program nor its activation permits physical send.
      if @infer.require_model_call_entry(active) is Err(_) {
        return Err(@infer.InvalidAdvance)
      }
      match @infer.bind_quantity_capacity(active, selected_task.quantities) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match @infer.bind_egress_admission(active, egress) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // This Task prepares the exact wire before an installed physical
      // port can bind to it. Core waits with no Entry or transport claim.
      match
        @infer.bind_original_portable_chat_preflight(
          active,
          selected_task.provider,
          run.response_profile,
          run.profile,
          None,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if prepared_suffix is Some(suffix) {
        match @infer.bind_compute_suffix(active, suffix) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok(active)
    },
    issue => {
      if selected_task.issue is None {
        selected_task.issue = Some(issue)
      }
      @connector.ComputeUnsupported
    },
    retain_completed=active => {
      guard selected_task.active is Some(original) &&
        physical_equal(active, original) &&
        (
          selected_task.entry is None ||
          selected_task.settlement
          is Some({ persistence: Some({ state: Applied, .. }), .. })
        ) else {
        return false
      }
      if selected_task.publication_output is None {
        selected_task.publication_output = @infer.acquire_output(active)
      }
      selected_task.publication_output is Some(_)
    },
    input_prefix=Some(prefix),
    host_await_io=true,
    portable_vm=true,
  )
}

///|
fn portable_compute_model_plan(
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  run : StoredPortableModelRun,
  selected_module : @local_host.ClientInstalledManagedSourceFreePreparation,
  compilation : @host.ClientTaskCompilation,
) -> Result[
  @local_host.ClientInstalledManagedModelPlan,
  @local_host.ClientInstalledManagedRunIssue,
] {
  let count = run.members.length()
  let mut model_attempts = 0L
  let mut model_holdings = 0L
  for selected in run.members {
    model_attempts += selected.limits.model.ledger.attempts.to_int64()
    model_holdings += selected.limits.model.ledger.holdings.to_int64()
  }
  guard @local_host.portable_model_scope_inventory(
      selected_module, model_attempts, model_holdings,
    )
    is Some((reservations, holdings, delegations)) else {
    return Err(InsufficientCapacity)
  }
  if count == 1 {
    let first = run.members[0]
    let limits = first.limits
    return @local_host.prepare_request_model_source_free_plan(
      parent,
      slot,
      selected_module,
      run.request,
      run.compiled,
      run.definition,
      first.graph.occurrence,
      first.graph,
      limits.model.ledger,
      limits.mapping.logical.max_live_value_bytes,
      limits.identity.wire.max_bytes.to_int64(),
      reservations,
      holdings,
      delegations,
    )
  }
  match
    @local_host.reserve_request_models_plan_projection(parent, slot, count) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let occurrences = Array(capacity=count)
  let ledger = Array(capacity=count)
  let retained = Array(capacity=count)
  let execution = Array(capacity=count)
  for selected_task in run.members {
    let limits = selected_task.limits
    occurrences.push(selected_task.graph.occurrence)
    ledger.push(limits.model.ledger)
    retained.push(limits.mapping.logical.max_live_value_bytes)
    execution.push(limits.identity.wire.max_bytes.to_int64())
  }
  @local_host.prepare_request_models_source_free_plan(
    parent,
    slot,
    selected_module,
    run.request,
    run.compiled,
    run.definition,
    occurrences,
    compilation.infers,
    ledger,
    retained,
    execution,
    reservations,
    holdings,
    delegations,
  )
}

///|
fn portable_file_model_compute_plan(
  value : Instance,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  run : StoredPortableModelRun,
  compilation : @host.ClientTaskCompilation,
  file : StoredPortableModelFile,
) -> Result[
  @local_host.ClientInstalledManagedModelPlan,
  @local_host.ClientInstalledManagedRunIssue,
] {
  guard run.members is [selected_task] else { return Err(ForeignOriginal) }
  let module_ = match @local_host.prepare_request_model_capture_module(
      parent, slot, run.request, run.compiled, run.definition,
      compilation, [], "", "", [file.transfer], [file.execution],
      value.installed_sequences.contracts, true, 1, _ => [],
      whole_sources=[file.capacity],
      component_factory=Some((_, prefix, suffix) => {
        portable_model_module_provider(run, selected_task, prefix, suffix)
      }),
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignOriginal)
  }
  let limits = selected_task.limits
  guard @local_host.portable_file_model_scope_inventory(
      module_, limits.model.ledger.attempts.to_int64(),
      limits.model.ledger.holdings.to_int64(),
    ) is Some((reservations, holdings, delegations)) else {
    return Err(InsufficientCapacity)
  }
  @local_host.prepare_request_model_capture_plan(
    parent, slot, module_, run.request, run.compiled, run.definition,
    selected_task.graph.occurrence, selected_task.graph, limits.model.ledger,
    limits.mapping.logical.max_live_value_bytes, limits.identity.wire.max_bytes.to_int64(),
    reservations, holdings, delegations,
  )
}

///|
fn portable_compute_model_quantities(
  members : Array[StoredPortableModelMember],
) -> @resources.QuantityAmounts? {
  let mut tokens = 0L
  let mut cost = 0L
  let mut duration = 0L
  for selected_task in members {
    let limits = selected_task.quantities.limits
    guard @execution.checked_preparation_add_product(tokens, limits.tokens, 1L)
      is Some(next_tokens) &&
      @execution.checked_preparation_add_product(cost, limits.cost_units, 1L)
      is Some(next_cost) &&
      @execution.checked_preparation_add_product(
        duration,
        limits.duration_ms,
        1L,
      )
      is Some(next_duration) else {
      return None
    }
    tokens = next_tokens
    cost = next_cost
    duration = next_duration
  }
  Some({ tokens, cost_units: cost, duration_ms: duration, })
}

///|
fn configure_portable_model_compute(
  value : Instance,
  run_handle : Int,
  original : StoredRun,
  current : StoredRunConfiguration,
  plan : @local_run.LocalRunPlan,
  start : @local_run.LocalRunPhysicalStart,
  compute_handle : Int,
  compute : StoredNativeCompute,
  physical : StoredPhysicalStart,
) -> Result[@local_run.LocalComputeHost?, @local_run.LocalComputeIssue] {
  guard value.preparations.get(original.preparation) is Some(preparation) &&
    original.sdk_submission is Some(submission) &&
    retained_sdk_portable_request(
      value, preparation, original.configuration, current, submission,
    ) is Some(held) &&
    held.model_run_handle == Some(run_handle) &&
    held.model_run is None &&
    held.parent is Some(parent) &&
    held.access is Some(access) &&
    held.portable_execution is Some(execution) &&
    execution.bounds is Some(bounds) &&
    current.host_current is Some(host_current) &&
    current.sdk is Some({ portable_model: Some(model), .. }) &&
    installed_portable_model_task(value, model, host_current) is Some(_) &&
    value.original_metadata.get(model)
    is Some(
      {
        project: Some(
          ModelHttpTask(
            {
              _configured: Some((configured, profile, _)),
              _tls_ca: tls_ca,
              execution: Some((_, _, observed_egress)),
              ..
            }
          )
        ),
        ..
      }
    ) else {
    return Err(Configuration)
  }
  let compilation = @local_run.local_run_compilation(plan)
  let count = execution.members.length()
  guard count > 0 &&
    bounds.length() == count &&
    compilation.infers.length() == count else {
    return Err(Configuration)
  }
  for index in 0..<count {
    let (occurrence, contract, _, _) = execution.members[index]
    let graph = compilation.infers[index]
    if !@host.client_infer_occurrence_matches_plan(occurrence, graph) ||
      !physical_equal(contract, graph.execution) {
      return Err(Configuration)
    }
  }
  let configuration_handle = original.configuration
  let run : StoredPortableModelRun = {
    request: @local_run.local_run_request(plan),
    compiled: @local_run.local_run_compiled(plan),
    definition: @local_run.local_run_definition(plan),
    profile,
    response_profile: configured.profile,
    tls_ca,
    observe_egress: () => {
      guard run_configuration_current(value, current) is Ok(_) &&
        value.run_configurations.get(configuration_handle) is Some(installed) &&
        physical_equal(current, installed) else {
        return None
      }
      Some(observed_egress)
    },
    members: Array(capacity=count),
    adopted: None,
    sources: None,
  }
  held.model_run = Some(run)
  for index in 0..<count {
    let task_limits = bounds[index]
    let model_limits = task_limits.model
    let graph = compilation.infers[index]
    let slots = Int::min(model_limits.max_items, model_limits.ledger.attempts)
    guard portable_model_task_authorization(current, graph)
      is Some((connection, resource, entry)) else {
      return Err(AuthorizationMismatch)
    }
    guard portable_model_scope_dimensions(
        slots,
        current.account,
        entry,
        current.tuple.principal,
        connection,
        resource,
        @publication.run_publication_execution_context(run.compiled.admission),
        @host.client_infer_plan_graph_barrier_cid(graph),
      )
      is Some((scope_bytes, scope_nodes)) &&
      portable_model_scope_capacity(scope_bytes, scope_nodes, slots)
      is Some(scope) &&
      @host.measure_client_infer_account_dispatch_authority(
        run.compiled,
        run.definition,
        graph,
        current.account,
        current.tuple.principal,
        connection,
        resource,
        entry,
      )
      is Some((bytes, nodes, depth) as dispatch_extent) &&
      portable_model_scope_capacity(bytes, nodes, 0, depth~) is Some(authority) &&
      portable_model_serial_evidence_capacity(scope, authority)
      is Some(evidence) &&
      @infer.portable_chat_model_startup_capacity(
        task_limits,
        configured.profile,
        scope=Some(evidence),
      )
      is Some(capacity) else {
      return Err(Configuration)
    }
    let model_retained_bytes = @execution.execution_capacity_retained_bytes(
      capacity,
    )
    let model_execution_bytes = @execution.execution_capacity_execution_bytes(
      capacity,
    )
    if model_retained_bytes > model_limits.ledger.retained_bytes {
      return Err(
        Managed(
          @managed.ExecutionCapacityRefusal(
            @resources.RetentionLimit,
            model_retained_bytes,
            model_limits.ledger.retained_bytes,
            model_limits.ledger.retained_bytes,
          ),
        ),
      )
    }
    if model_execution_bytes > model_limits.ledger.execution_bytes {
      return Err(
        Managed(
          @managed.ExecutionCapacityRefusal(
            @resources.ExecutionLimit,
            model_execution_bytes,
            model_limits.ledger.execution_bytes,
            model_limits.ledger.execution_bytes,
          ),
        ),
      )
    }
    run.members.push({
      graph,
      limits: task_limits,
      provider: execution.members[index].2,
      quantities: execution.members[index].3,
      model_retained_bytes,
      model_execution_bytes,
      scope_bytes,
      scope_nodes,
      dispatch_extent,
      dispatch_clock: Ref(None),
      dispatch: None,
      entry: None,
      entry_journal: None,
      capture: None,
      capture_capacity: None,
      transport: None,
      request_material: None,
      transport_worker: Unclaimed,
      transport_stop: false,
      raw_output: None,
      raw_save: None,
      raw_capacity: None,
      raw_borrow: None,
      raw_plaintext_bytes: 0,
      raw_store: None,
      settlement: None,
      scope: None,
      read: None,
      active: None,
      publication_output: None,
      issue: None,
    })
  }
  execution.bounds = None
  let slot = preparation.slot
  let model_plan_result = if execution.file is Some(file) {
    guard project_request_configuration(value, preparation.environment) is Some((configuration, check)) &&
      physical_equal(configuration, current) &&
      check.local_file is Some(checker) && file.selection.matches_check(checker) else {
      return Err(Configuration)
    }
    portable_file_model_compute_plan(value, parent, slot, run, compilation, file)
  } else {
    let selected_module = match
    @local_host.prepare_request_model_source_free_module(
      parent,
      slot,
      run.request,
      run.compiled,
      run.definition,
      compilation,
      value.installed_sequences.contracts,
      true,
      if count == 1 {
        1
      } else {
        0
      },
      _ => [],
      component_factory=if count == 1 {
        Some((_, prefix, suffix) => {
          portable_model_module_provider(run, run.members[0], prefix, suffix)
        })
      } else {
        None
      },
      components_factory=if count > 1 {
        Some((index, _, prefix, suffix) => {
          portable_model_module_provider(
            run,
            run.members[index],
            prefix,
            suffix,
          )
        })
      } else {
        None
      },
    ) {
      Err(_) => return Err(Configuration)
      Ok(selected_module) => selected_module
    }
    portable_compute_model_plan(parent, slot, run, selected_module, compilation)
  }
  let model_plan = match model_plan_result {
    Ok(plan) => plan
    Err(_) => return Err(Configuration)
  }
  guard portable_compute_model_quantities(run.members) is Some(quantities) else {
    return Err(Configuration)
  }
  let scopes = if count == 1 {
    match
      @local_host.prepare_request_portable_model_read_scope(
        parent, slot, model_plan, access, quantities,
      ) {
      Ok(scope) => {
        run.members[0].scope = Some(scope)
        None
      }
      Err(_) => return Err(Configuration)
    }
  } else {
    match
      @local_host.prepare_request_portable_models_read_scopes(
        parent, slot, model_plan, access, quantities,
      ) {
      Ok(scopes) => {
        for index in 0..<count {
          run.members[index].scope = Some(scopes[index])
        }
        Some(scopes)
      }
      Err(_) => return Err(Configuration)
    }
  }
  guard run.members[0].scope is Some(first) &&
    @local_host.complete_request_model_preparation(parent, slot, model_plan)
    is Ok(_) else {
    return Err(Configuration)
  }
  if held.model_input is Some(input) {
    match @resources.return_preparation_body_borrow(input) {
      Err(_) => return Err(Configuration)
      Ok(_) => held.model_input = None
    }
  }
  let adopted = match
    @local_host.begin_request_model_managed_run(
      parent,
      run.request,
      first,
      scopes~,
    ) {
    Err(_) => return Err(Configuration)
    Ok(adopted) => adopted
  }
  run.adopted = Some(adopted)
  held.parent = None
  if run_configuration_current(value, current) is Err(_) {
    return Err(AuthorizationMismatch)
  }
  if execution.file is Some(selected) {
    guard physical.model_file is None && physical.file_managed is None &&
      physical.run == run_handle else {
      return Err(Configuration)
    }
    physical.model_file = Some({
      compute_handle, compute, selected, runtime: run, adopted, model: model_plan,
      source: { capture: None, csv_read: None },
      sealing: false,
      evidence_capacity: None,
    })
    return Ok(None)
  }
  @local_run.configure_local_source_free_model_compute(
    plan, start, adopted, model_plan,
  ).map(host => Some(host))
}

///|
// The installed account/start check runs before this bounded Model-only
// selection. Retain the exact Compute's adopted Request and installation;
// a different config, saved row or retired child cannot authorize this phase.
fn portable_compute_task_current(
  value : Instance,
  compute : StoredNativeCompute,
  original : StoredRun,
  current : StoredRunConfiguration,
  current_handle : Int,
) -> Int {
  if compute.host is Some(host) &&
    @local_run.local_compute_model_run(host) is Some(adopted) {
    guard !value.closing &&
      !value.runtime_closing &&
      !compute.closing &&
      compute.current_configuration == Some(current_handle) &&
      original.configuration == current_handle &&
      value.run_configurations.get(current_handle) is Some(retained) &&
      physical_equal(retained, current) &&
      compute.start is Some(start) &&
      physical_equal(start.host, host) &&
      original.outcome is Some(Ok(plan)) &&
      physical_equal(plan, host.plan) &&
      original.restoration is None &&
      current.host_current is Some(host_current) &&
      current.sdk is Some({ portable_model: Some(model), .. }) &&
      value.preparations.get(original.preparation)
      is Some({ project_request: Some({ model_run: Some(run), .. }), .. }) &&
      run.adopted is Some(same_run) &&
      physical_equal(same_run, adopted) &&
      physical_equal(run.request, @local_run.local_run_request(host.plan)) &&
      physical_equal(run.compiled, @local_run.local_run_compiled(host.plan)) &&
      physical_equal(run.definition, @local_run.local_run_definition(host.plan)) &&
      installed_portable_model_task(value, model, host_current) is Some(_) else {
      return -32
    }
  }
  0
}

///|
fn quiesce_portable_model_run(
  root : @resources.Ledger,
  run : StoredPortableModelRun,
) -> Bool {
  // The original Run/Compute/Task children are already closed here. A
  // failed component entrance can still have left an Input or Read.
  for selected_task in run.members {
    if !retire_portable_model_settlement(root, selected_task) {
      return false
    }
    if selected_task.active is Some(active) {
      if !@infer.execution_stopped(active) {
        @infer.cancel(active) |> ignore
        @infer.advance_cancelled(active, 1) |> ignore
      }
      if !(@infer.cleanup(active) is Ok(true)) {
        return false
      }
      if selected_task.entry_journal is Some(journal) &&
        !retire_portable_entry_workspace(journal) {
        return false
      }
      if !retire_portable_model_capture(root, selected_task) {
        return false
      }
      if selected_task.raw_borrow is Some(borrow) {
        if @buffers.return_buffer_borrow(borrow.owner, borrow) is Err(_) {
          return false
        }
        selected_task.raw_borrow = None
      }
      if selected_task.raw_store is Some(store) &&
        store.response_capacity is Some(capacity) &&
        @resources.settle_capacity(root, capacity) is Err(_) {
        return false
      }
      selected_task.raw_store = None
      if selected_task.raw_capacity is Some(capacity) {
        if @resources.settle_capacity(root, capacity) is Err(_) {
          return false
        }
        selected_task.raw_capacity = None
      }
      selected_task.raw_save = None
      selected_task.raw_output = None
      selected_task.active = None
      selected_task.dispatch = None
      selected_task.entry = None
      selected_task.entry_journal = None
      selected_task.transport = None
      selected_task.request_material = None
    }
    if selected_task.read is Some(read) {
      guard selected_task.scope is Some(scope) &&
        @host.stop_client_model_read_checked(
          scope,
          read,
          run.compiled,
          run.definition,
          selected_task.graph,
        )
        is Ok(_) &&
        @host.settle_client_model_read_checked(
          read,
          run.compiled,
          run.definition,
          selected_task.graph,
          true,
        )
        is Ok(_) else {
        return false
      }
      selected_task.read = None
    }
  }
  if run.adopted is Some(adopted) &&
    @local_host.quiesce_installed_managed_run(adopted) is Err(_) {
    return false
  }
  // The final checked group acknowledgement covers the earlier Scopes.
  // Keep all aliases until the group has actually finished.
  let mut finished = true
  for selected_task in run.members {
    if selected_task.scope is Some(scope) {
      match
        @host.finish_client_model_read_scope(
          scope,
          run.compiled,
          run.definition,
          selected_task.graph,
          true,
        ) {
        Ok(value) => finished = value
        Err(_) => return false
      }
    }
  }
  if !finished {
    return false
  }
  for selected_task in run.members {
    selected_task.scope = None
  }
  if run.adopted is Some(adopted) {
    match @local_host.retire_installed_managed_run(adopted) {
      Ok(_) => ()
      Err(Resource(Unavailable)) =>
        return @local_host.installed_preparation_payload_severed(
          adopted,
          run.request,
        )
      Err(_) => return false
    }
  }
  true
}
