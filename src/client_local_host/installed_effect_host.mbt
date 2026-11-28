///|
/// Check the same managed preparation and Ledger that will open the actual
/// source-free Effect computation. This borrows the authenticated Map for one
/// synchronous selection; it does not mount control or retain the Map read.
pub fn preflight_installed_effect_compute_steps(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  map : @publication.RunEvidenceValue,
  map_cid : String,
  max_work : Int,
) -> Result[String?, ClientInstalledManagedRunIssue] {
  if owner.source_free_opening || owner.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  let prepared = @publication_host.prepared_client_effect_run_computation(bound)
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(PlannedEffectManaged(_, plan) as preparation) &&
    physical_equal(
      @strategy.checked_effect_run_graph(
        @publication_host.prepared_client_effect_run_graph(bound),
      ),
      plan.graph,
    ) else {
    return Err(ForeignOriginal)
  }
  if plan.query_time is Some(original) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound,
      original,
      plan.request,
    ) {
    return Err(ForeignOriginal)
  }
  if plan.source_free is None ||
    plan.model is Some(_) ||
    plan.content is Some(_) {
    return Ok(None)
  }
  owner.source_free_opening = true
  let selected = match require_installed_managed_run(owner) {
    Err(issue) => Err(issue)
    Ok(ledger) =>
      match
        @publication_host.preflight_client_effect_compute_steps(
          bound, ledger, map, map_cid, max_work,
        ) {
        Err(Resource(issue)) =>
          Err(ClientInstalledManagedRunIssue::Ledger(issue))
        Err(_) => Err(ClientInstalledManagedRunIssue::ForeignOriginal)
        Ok(step) =>
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => Err(issue)
            Ok(_) => Ok(step)
          }
      }
  }
  owner.source_free_opening = false
  selected
}

///|
fn installed_effect_debug_control_original(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
) -> Result[
  (ClientInstalledEffectDebugMap, @strategy.CapturedDAG, @resources.Ledger),
  @strategy.CapturedTaskControlIssue,
] {
  if owner.source_free_opening {
    return Err(InProgress)
  }
  if owner.effect_operation_closing {
    return Err(Stopped)
  }
  let graph = @publication_host.prepared_client_effect_run_graph(bound)
  let dag = @strategy.captured_effect_run_dag(captured)
  let prepared = @publication_host.prepared_client_effect_run_computation(bound)
  guard owner.effect_debug_map is Some(selected) &&
    physical_equal(
      selected.definition,
      installed_effect_debug_definition(bound),
    ) &&
    physical_equal(
      @strategy.captured_effect_run_owner(captured),
      @strategy.checked_effect_run_owner(graph),
    ) &&
    check_installed_effect_managed_run_binding(owner, prepared, request)
    is Ok(_) &&
    owner.source_free_captured is Some(admitted) &&
    physical_equal(admitted, dag) else {
    return Err(ForeignOwner)
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  guard require_installed_managed_run(owner) is Ok(ledger) &&
    !owner.effect_operation_closing &&
    owner.effect_debug_map is Some(current) &&
    physical_equal(current, selected) &&
    owner.source_free_captured is Some(original) &&
    physical_equal(original, dag) else {
    return Err(ForeignOwner)
  }
  Ok((selected, dag, ledger))
}

///|
fn authorize_installed_effect_debug_control(
  captured : @strategy.CapturedEffectRunDAG,
  account : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
) -> Result[
  @authorization.DispatchAuthorization,
  @strategy.CapturedTaskControlIssue,
] {
  let original = @strategy.captured_effect_run_owner(captured)
  let subject = @publication.publication_contract_identity(
    @effect_binding.effect_program_run_definition(original),
  )
  let context = @publication.run_publication_execution_context(
    @effect_binding.effect_program_run_admission(original),
  )
  @authorization.bind_dispatch_authorization(
    account,
    tuple,
    Activation,
    subject,
    context,
  ).map_err(_ => @strategy.AuthorizationMismatch)
}

///|
fn installed_effect_debug_readiness_work(dag : @strategy.CapturedDAG) -> Int64 {
  let graph = @strategy.captured_dag_graph(dag)
  // The existing readiness selector can examine the full predecessor set
  // for each incomplete task before it finds the next one.
  @strategy.graph_task_count(graph).to_int64() *
  (
    1L +
    @strategy.graph_data_count(graph).to_int64() +
    @strategy.graph_control_count(graph).to_int64()
  )
}

///|
/// Mount the existing controller on the actual Compute DAG of the admitted
/// Effect Run. The caller still owns the original Journal entry and start CAS.
pub fn prepare_installed_effect_debug_control(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  let (_, dag, _) = match
    installed_effect_debug_control_original(owner, bound, request, captured) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let tuple = installed_debug_control_tuple(principal, connection, true)
  let authorization = match
    authorize_installed_effect_debug_control(captured, account, tuple) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  guard @strategy.prepare_captured_task_boundary_hooks(
      dag,
      @strategy.captured_dag_graph(dag),
      @strategy.captured_dag_strategy_revision(dag),
    )
    is Ok(hooks) else {
    return Err(NotPrepared)
  }
  @strategy.prepare_captured_effect_task_control(
    captured, hooks, authorization, account, tuple,
  )
}

///|
/// The installed dispatcher reads this phase after each wait. Only a current
/// controller that consumed the same physical-start revision can select work.
pub fn installed_effect_debug_control_runnable(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  start_revision : Int,
) -> Result[Bool, @strategy.CapturedTaskControlIssue] {
  let (_, dag, _) = match
    installed_effect_debug_control_original(owner, bound, request, captured) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @strategy.captured_task_boundary_hooks(dag) is Some(hooks) else {
    return Err(NotPrepared)
  }
  if !@strategy.captured_effect_task_control_started(
      captured, hooks, start_revision,
    ) {
    return Err(StaleRevision)
  }
  match @strategy.captured_task_control_state(dag, hooks) {
    Ok((_, Running | Stepping(_) | RunningToBreakpoint(_))) => Ok(true)
    Ok((_, Paused)) => Ok(false)
    Ok(_) => Err(InvalidTransition)
    Err(issue) => Err(issue)
  }
}

///|
/// Project completed and next Step separately from the sealed original Map.
/// This is a bounded operation on a park, using one forward pass under the
/// original Run's Work budget. It does not read a cell or acquire a carrier.
pub fn installed_effect_debug_task_pause(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  start_revision : Int,
  max_work : Int,
) -> Result[(Int, String, String, Int), @strategy.CapturedTaskControlIssue] {
  let (selected, dag, ledger) = match
    installed_effect_debug_control_original(owner, bound, request, captured) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @strategy.captured_task_boundary_hooks(dag) is Some(hooks) else {
    return Err(NotPrepared)
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  project_installed_effect_debug_task_pause(
    owner, bound, captured, selected, dag, ledger, hooks, start_revision, max_work,
  )
}

///|
fn project_installed_effect_debug_task_pause(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  selected : ClientInstalledEffectDebugMap,
  dag : @strategy.CapturedDAG,
  ledger : @resources.Ledger,
  hooks : @strategy.CapturedTaskBoundaryHooks,
  start_revision : Int,
  max_work : Int,
) -> Result[(Int, String, String, Int), @strategy.CapturedTaskControlIssue] {
  if !@strategy.captured_effect_task_control_started(
      captured, hooks, start_revision,
    ) ||
    !(@strategy.captured_task_control_state(dag, hooks) is Ok((_, Paused))) {
    return Err(StaleRevision)
  }
  let readiness_work = installed_effect_debug_readiness_work(dag)
  if readiness_work > max_work.to_int64() {
    return Err(Resource(@resources.PlanningLimit))
  }
  match @resources.charge_planning(ledger, readiness_work.to_int()) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let (revision, task, next, generation) = match
    @strategy.captured_task_control_paused_task(dag, hooks) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let completed_step = Ref(None)
  let next_step = Ref(None)
  match
    @publication_host.preflight_client_effect_compute_steps(
      bound,
      ledger,
      selected.map,
      @publication.run_evidence_value_identity(selected.map),
      max_work - readiness_work.to_int(),
      observe_step=Some((index, step_id) => {
        if index == task {
          completed_step.val = Some(step_id)
        }
        if next == Some(index) {
          next_step.val = Some(step_id)
        }
      }),
    ) {
    Err(issue) => return Err(issue)
    Ok(None) => return Err(ForeignOwner)
    Ok(Some(_)) => ()
  }
  guard owner.effect_debug_map is Some(current) &&
    physical_equal(current, selected) &&
    @strategy.captured_task_control_state(dag, hooks) == Ok((revision, Paused)) &&
    @strategy.captured_dag_generation(dag) == generation else {
    return Err(StaleRevision)
  }
  guard completed_step.val is Some(completed) else {
    return Err(BoundaryUnavailable(task))
  }
  let following = match next {
    Some(index) => {
      guard next_step.val is Some(id) else {
        return Err(BoundaryUnavailable(index))
      }
      id
    }
    None => ""
  }
  Ok((revision, completed, following, generation))
}

///|
/// Apply the original installed receiver's accepted entry or later Step
/// command to this same controller. The caller verifies the Journal witness.
pub fn command_installed_effect_debug_control(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedEffectRunDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  start_revision : Int,
  boundary : (Int, String, String, Int)?,
  step : Bool,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  let (selected, dag, ledger) = match
    installed_effect_debug_control_original(owner, bound, request, captured) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @strategy.captured_task_boundary_hooks(dag) is Some(hooks) else {
    return Err(NotPrepared)
  }
  let tuple = installed_debug_control_tuple(principal, connection, false)
  let authorization = match
    authorize_installed_effect_debug_control(captured, account, tuple) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let command_work = if step {
    installed_effect_debug_readiness_work(dag)
  } else {
    0L
  }
  if command_work > max_work.to_int64() {
    return Err(Resource(@resources.PlanningLimit))
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  let revision = match boundary {
    None => {
      guard @strategy.captured_task_control_entry_task(dag, hooks) == Some(0) else {
        return Err(StaleRevision)
      }
      0
    }
    Some(expected) => {
      let current = match
        project_installed_effect_debug_task_pause(
          owner,
          bound,
          captured,
          selected,
          dag,
          ledger,
          hooks,
          start_revision,
          max_work - command_work.to_int(),
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      if current != expected {
        return Err(StaleRevision)
      }
      expected.0
    }
  }
  if command_work > 0L {
    match @resources.charge_planning(ledger, command_work.to_int()) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
  }
  @strategy.command_captured_effect_task_control(
    captured,
    hooks,
    start_revision,
    revision,
    if step {
      @strategy.ResumeStep
    } else {
      @strategy.ResumeTerminal
    },
    authorization,
    account,
    tuple,
  )
}

///|
/// Open the admitted bound Effect Run on its original managed parent. The
/// retained plan supplies both the generated originals and their configured
/// Local limits. Bound Run admission, physical Source custody and permission
/// remain their existing independent obligations.
pub fn open_installed_effect_managed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  if owner.effect_operation_closing ||
    owner.source_free_opening ||
    owner.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  let opened = select_installed_effect_managed_host(
    owner,
    bound,
    sources.copy(),
  )
  owner.source_free_opening = false
  opened
}

///|
/// The serialized Wasm Host calls this after the original synchronous open
/// has unwound, before returning any of its caller-owned Source Reads. An
/// interrupted opening latch is not a stop acknowledgment. The original
/// Core DAG must settle its actual tasks, ports and borrows before they close.
pub fn stop_installed_effect_managed_host_after_unwind(
  owner : ClientInstalledManagedRun,
  stop_tasks : () -> Bool,
) -> Bool {
  guard owner.original is Some(original) &&
    physical_equal(owner, original) &&
    owner.preparation is Some(PlannedEffectManaged(_, plan)) &&
    physical_equal(owner.request, plan.request) &&
    plan.model is None &&
    !plan.whole_sources.is_empty() &&
    owner.ledger is Some(ledger) else {
    return false
  }
  if owner.source_free_captured is Some(run) &&
    (
      !physical_equal(plan.graph, @strategy.captured_dag_graph(run)) ||
      !physical_equal(ledger, @strategy.captured_dag_ledger(run))
    ) {
    return false
  }
  owner.effect_operation_closing = true
  owner.source_free_opening = false
  // The same trusted call also fences an interrupted Source evidence issuer.
  // The held controls still require quiesce after real Source acknowledgments.
  owner.effect_operation_opening = false
  if owner.effect_operation_controls is Some(control) &&
    !retire_installed_effect_dependency_inputs(control) {
    return false
  }
  if !stop_tasks() {
    return false
  }
  match owner.source_free_captured {
    None => true
    Some(run) =>
      close_local_values_tasks(run, []) &&
      !@strategy.captured_task_retirement_pending(run) &&
      !@strategy.captured_task_boundary_cleanup_pending(run)
  }
}

///|
pub fn open_installed_effect_managed_keyed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  keyed : @publication_host.ClientKeyedLookupInput,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  if owner.source_free_opening || owner.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  let opened = select_installed_effect_managed_host(
    owner,
    bound,
    sources.copy(),
    keyed=Some(keyed),
  )
  owner.source_free_opening = false
  opened
}

///|
fn select_installed_effect_managed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  keyed? : @publication_host.ClientKeyedLookupInput? = None,
  deferred_keyed? : Bool = false,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(
      owner,
      @publication_host.prepared_client_effect_run_computation(bound),
      owner.request,
    ) {
    Err(issue) => return Err(issue)
    Ok(plan) => plan
  }
  if !physical_equal(
      plan.prepared,
      @publication_host.prepared_client_effect_run_computation(bound),
    ) {
    return Err(ForeignOriginal)
  }
  // The plan already prepared its Source requirements and sequences with this
  // admitted invocation original. Equal wire/CIDs or another restored context
  // cannot replace its actual Run admission/definition during the handoff.
  if plan.query_time is Some(original) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound,
      original,
      plan.request,
    ) {
    return Err(ForeignOriginal)
  }
  let graph = plan.graph
  let first = @strategy.graph_captured_prefix(graph)
  if sources.length() !=
    (if plan.whole_sources.any(value => value is Some(_)) {
      plan.whole_sources.length()
    } else {
      first
    }) ||
    plan.sequences.length() != @strategy.graph_task_count(graph) ||
    !client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ) {
    return Err(ForeignOriginal)
  }
  let ledger = match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  // Reentrant current/provider callbacks cannot replace this owner's one DAG
  // or retire the parent while its original configuration is in progress.
  open_installed_effect_managed_host_original(
    owner,
    bound,
    sources,
    plan,
    ledger,
    keyed~,
    deferred_keyed~,
  )
}

///|
fn open_installed_effect_managed_host_original(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  keyed? : @publication_host.ClientKeyedLookupInput? = None,
  deferred_keyed? : Bool = false,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let original_graph = installed_managed_owner_graph(Effect(plan.prepared))
  let graph = plan.graph
  let whole = plan.whole_sources.any(value => value is Some(_))
  let first = @strategy.graph_captured_prefix(graph)
  let checked = @publication_host.prepared_client_effect_run_graph(bound)
  if !physical_equal(
      @strategy.checked_effect_run_graph(checked),
      original_graph,
    ) ||
    !installed_effect_managed_limits_fit(owner, plan, ledger) {
    return Err(ForeignOriginal)
  }
  let opened = if plan.model is None && keyed is Some(lookup) {
    guard !whole &&
      plan.keyed_original is Some(original) &&
      @publication_host.client_effect_keyed_lookup_matches_parent(
        lookup, original, ledger,
      ) &&
      @publication_host.client_effect_keyed_lookup_sources_match(
        lookup, original, sources,
      ) &&
      @publication_host.client_keyed_acquisition_coordinates(
        @publication_host.client_keyed_lookup_acquisition(lookup),
      )
      is Some((_, task, _)) &&
      @publication_host.finish_client_keyed_lookup_input(lookup) is Ok(read) else {
      return Err(ForeignOriginal)
    }
    @strategy.open_captured_effect_keyed_source_run_dag(
      checked,
      Array::makei(first, index => (index, sources[index])),
      ledger,
      task,
      read,
    )
  } else if whole {
    if sources.length() != plan.whole_sources.length() {
      return Err(ForeignOriginal)
    }
    for occurrence, source in sources {
      guard plan.whole_sources[occurrence] is Some((_, selected)) &&
        @query.captured_source_matches_input_acquisition(
          source,
          selected.original,
        ) else {
        return Err(ForeignOriginal)
      }
    }
    let source_results = match keyed {
      None => []
      Some(lookup) => {
        guard plan.model is Some(model) &&
          @publication_host.client_composed_keyed_lookup_source_results(
            lookup,
            model._occurrence,
          )
          is Some(results) else {
          return Err(ForeignOriginal)
        }
        results
      }
    }
    let completed_keyed = match keyed {
      None => None
      Some(lookup) => {
        guard plan.model is Some(model) &&
          @publication_host.client_composed_keyed_lookup_matches_model_parent(
            lookup,
            model.compiled,
            model.definition,
            model.graph,
            ledger,
          ) &&
          @publication_host.client_composed_keyed_lookup_sources_match(
            lookup,
            model._occurrence,
            sources,
          ) &&
          @publication_host.finish_client_keyed_lookup_input(lookup) is Ok(read) else {
          return Err(ForeignOriginal)
        }
        let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
          model._occurrence,
        )
        Some((task, step, read))
      }
    }
    @strategy.open_source_inputs_effect_run_dag(
      checked,
      graph,
      sources,
      ledger,
      keyed=completed_keyed,
      source_results~,
      deferred_keyed=if deferred_keyed {
        guard plan.model is Some(model) else { return Err(ForeignOriginal) }
        let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
          model._occurrence,
        )
        Some((task, step))
      } else {
        None
      },
    )
  } else if keyed is Some(lookup) {
    guard plan.model is Some(model) &&
      @publication_host.client_composed_keyed_lookup_matches_model_parent(
        lookup,
        model.compiled,
        model.definition,
        model.graph,
        ledger,
      ) &&
      @publication_host.client_composed_keyed_lookup_sources_match(
        lookup,
        model._occurrence,
        sources,
      ) else {
      return Err(ForeignOriginal)
    }
    let read = match
      @publication_host.finish_client_keyed_lookup_input(lookup) {
      Ok(value) => value
      Err(_) => return Err(ForeignOriginal)
    }
    let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
      model._occurrence,
    )
    @strategy.open_multi_captured_effect_run_keyed_dag(
      checked,
      Array::makei(first, index => (index, sources[index])),
      ledger,
      task,
      step,
      read,
    )
  } else if first == 0 {
    @strategy.open_source_free_effect_run_dag(checked, ledger)
  } else if first == 1 {
    @strategy.open_captured_effect_run_dag(checked, sources[0], ledger)
  } else {
    @strategy.open_multi_captured_effect_run_dag(
      checked,
      Array::makei(first, index => (index, sources[index])),
      ledger,
    )
  }
  let captured = match opened {
    Err(_) => return Err(Unsupported)
    Ok(value) => value
  }
  let run = @strategy.captured_effect_run_dag(captured)
  // Retain immediately, before provider/configuration callbacks can fail.
  // None/error does not certify release; the original parent keeps cleanup.
  owner.source_free_captured = Some(run)
  let host = bind_client_local_configuration(
    run,
    plan.configuration,
    1L,
    0L,
    0L,
    0L,
    captured_effect=if keyed is Some(_) || deferred_keyed {
      Some(captured)
    } else {
      None
    },
  )
  match require_installed_managed_run(owner) {
    Err(issue) => {
      ignore(reject_client_local_run(run))
      return Err(issue)
    }
    Ok(original) =>
      if !physical_equal(original, ledger) {
        ignore(reject_client_local_run(run))
        return Err(ForeignOriginal)
      }
  }
  Ok(host.map(value => (value, captured, plan.sequences)))
}

///|
/// Open the same checked Source-input DAG with its original keyed consumer
/// pending. Only upstream tasks can execute until the actual lookup is bound.
pub fn open_installed_effect_managed_deferred_keyed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  if owner.source_free_opening || owner.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      select_installed_effect_managed_host(
        owner,
        bound,
        sources.copy(),
        deferred_keyed=true,
      )
    },
    () => owner.source_free_opening = false,
  )
}

///|
pub fn bind_installed_effect_managed_keyed_host(
  owner : ClientInstalledManagedRun,
  host : @strategy.CapturedEffectRunDAG,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard !owner.source_free_opening &&
    owner.preparation is Some(PlannedEffectManaged(_, plan)) &&
    plan.model is Some(model) &&
    owner.source_free_captured is Some(run) &&
    physical_equal(run, @strategy.captured_effect_run_dag(host)) &&
    require_installed_managed_run(owner) is Ok(ledger) &&
    @publication_host.client_composed_keyed_lookup_matches_host(lookup, host) &&
    @publication_host.client_composed_keyed_lookup_matches_model_parent(
      lookup,
      model.compiled,
      model.definition,
      model.graph,
      ledger,
    ) &&
    @publication_host.finish_client_keyed_lookup_input(lookup) is Ok(read) else {
    return Err(ForeignOriginal)
  }
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    model._occurrence,
  )
  @strategy.bind_captured_effect_completed_keyed_input(host, task, step, read).map_err(_ => {
      ForeignOriginal
    },
  )
}
