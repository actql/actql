///|
/// Original completed-Model caller. Its consumer first claims the actual
/// completed Execution's one-use output pin. This helper preserves the same
/// installed Plan, bound Run, Source holdings and Effect dependency inventory.
pub fn open_installed_effect_retained_model_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  model_graph : @publication_host.ClientInferPlanGraph,
  output : @execution.CompletedOutput,
  completed_model : @model.ModelExecution,
  source_results? : Array[
    (
      Int,
      @execution.GeneratedSequence,
      Array[(Int, Int, @execution.ProducerRead)],
      @execution.CompletedSegmentInputs,
    ),
  ] = [],
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
  defer {
    owner.source_free_opening = false
  }
  select_installed_effect_retained_model_host(
    owner,
    bound,
    sources.copy(),
    compiled,
    definition,
    model_graph,
    output,
    completed_model,
    source_results~,
  )
}

///|
fn select_installed_effect_retained_model_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  model_graph : @publication_host.ClientInferPlanGraph,
  output : @execution.CompletedOutput,
  completed_model : @model.ModelExecution,
  source_results? : Array[
    (
      Int,
      @execution.GeneratedSequence,
      Array[(Int, Int, @execution.ProducerRead)],
      @execution.CompletedSegmentInputs,
    ),
  ] = [],
  models? : Array[
    (
      @publication_host.ClientInferPlanGraph,
      @execution.CompletedOutput,
      @model.ModelExecution,
    ),
  ] = [],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let (plan, ledger) = match
    require_installed_effect_operation_plan(
      owner,
      @publication_host.prepared_client_effect_run_computation(bound),
      owner.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original_graph = installed_managed_owner_graph(Effect(plan.prepared))
  let graph = plan.graph
  let whole = plan.whole_sources.any(value => value is Some(_))
  let checked = @publication_host.prepared_client_effect_run_graph(bound)
  guard plan.model is Some(model) &&
    physical_equal(model.compiled, compiled) &&
    physical_equal(model.definition, definition) &&
    (
      (models.is_empty() && physical_equal(model.graph, model_graph)) ||
      (!models.is_empty() && model.components is Some(_))
    ) &&
    @model.original_completed_model_matches_parent(completed_model, ledger) &&
    physical_equal(@strategy.checked_effect_run_graph(checked), original_graph) &&
    sources.length() ==
    (if whole {
      plan.whole_sources.length()
    } else {
      @strategy.graph_captured_prefix(graph)
    }) &&
    plan.sequences.length() == @strategy.graph_task_count(graph) &&
    client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ) &&
    installed_effect_managed_limits_fit(owner, plan, ledger) else {
    return Err(ForeignOriginal)
  }
  if !whole && !source_results.is_empty() {
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
  if whole {
    for occurrence, source in sources {
      guard plan.whole_sources[occurrence] is Some((_, selected)) &&
        @query.captured_source_matches_input_acquisition(
          source,
          selected.original,
        ) else {
        return Err(ForeignOriginal)
      }
    }
  }
  let captured = if models.is_empty() {
    let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
      model._occurrence,
    )
    let opened = if whole {
      @strategy.open_source_inputs_effect_run_dag(
        checked,
        graph,
        sources,
        ledger,
        models=[(task, step, output)],
        source_results~,
      )
    } else {
      @strategy.open_multi_captured_effect_run_retained_model_dag(
        checked,
        Array::makei(sources.length(), index => (index, sources[index])),
        ledger,
        task,
        step,
        output,
      )
    }
    let captured = match opened {
      Ok(value) => value
      Err(_) => return Err(ForeignOriginal)
    }
    captured
  } else {
    guard model.components is Some(components) &&
      installed_effect_model_demand_complete(model) &&
      models.length() <= components.length() else {
      return Err(ForeignOriginal)
    }
    let originals = []
    let mut previous = -1
    for (member_graph, member_output, member_execution) in models {
      let mut found = -1
      for index in 0..<components.length() {
        if physical_equal(components[index].graph, member_graph) {
          found = index
          break
        }
      }
      guard found > previous &&
        @model.original_completed_model_matches_parent(member_execution, ledger) else {
        return Err(ForeignOriginal)
      }
      previous = found
      let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
        components[found]._occurrence,
      )
      originals.push((task, step, member_output))
    }
    let opened = if whole {
      @strategy.open_source_inputs_effect_run_dag(
        checked,
        graph,
        sources,
        ledger,
        models=originals,
      )
    } else {
      @strategy.open_multi_captured_effect_run_retained_models_dag(
        checked,
        Array::makei(sources.length(), index => (index, sources[index])),
        ledger,
        originals,
      )
    }
    match opened {
      Ok(value) => value
      Err(_) => return Err(ForeignOriginal)
    }
  }
  let run = @strategy.captured_effect_run_dag(captured)
  // Retain before the original configuration/current callbacks. A failure
  // leaves cleanup on this same parent; it never returns a stop ACK.
  owner.source_free_captured = Some(run)
  let host = bind_client_local_configuration(
    run,
    plan.configuration,
    1L,
    0L,
    0L,
    0L,
    captured_effect=if whole { Some(captured) } else { None },
  )
  match require_installed_managed_run(owner) {
    Ok(original) if physical_equal(original, ledger) &&
      @model.original_completed_model_matches_parent(completed_model, original) &&
      models.all(original_model => {
        @model.original_completed_model_matches_parent(
          original_model.2,
          original,
        )
      }) => ()
    Ok(_) => {
      ignore(reject_client_local_run(run))
      return Err(ForeignOriginal)
    }
    Err(issue) => {
      ignore(reject_client_local_run(run))
      return Err(issue)
    }
  }
  if !@execution.completed_output_available(output) ||
    models.any(original_model => {
      !@execution.completed_output_available(original_model.1)
    }) {
    ignore(reject_client_local_run(run))
    return Err(ForeignOriginal)
  }
  Ok(host.map(value => (value, captured, plan.sequences)))
}

///|
/// Cleanup of this original parent's captured consumers also works when a
/// fallible Host constructor never returned its wrapper. Revocation forbids
/// new work, not retirement. Pending children retain the same parent for retry.
pub fn retire_installed_effect_captured_consumers(
  owner : ClientInstalledManagedRun,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(owner, original) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening || owner.effect_operation_opening {
    return Ok(false)
  }
  Ok(
    match owner.source_free_captured {
      Some(run) => @strategy.retire_captured_task_outputs(run)
      None => true
    },
  )
}

///|
/// A nonempty ordered subset of actual completed original members can be
/// restored; all remaining configured components retain their same live tasks.
pub fn open_installed_effect_retained_models_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  models : Array[
    (
      @publication_host.ClientInferPlanGraph,
      @execution.CompletedOutput,
      @model.ModelExecution,
    ),
  ],
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
  guard models.get(0) is Some((graph, output, execution)) else {
    return Err(ForeignOriginal)
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  select_installed_effect_retained_model_host(
    owner,
    bound,
    sources.copy(),
    compiled,
    definition,
    graph,
    output,
    execution,
    models~,
  )
}
