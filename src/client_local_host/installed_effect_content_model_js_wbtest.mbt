///|
// Real Check, compilation, Content provider and combined Plan. Model/physical
// ports do not execute here; this is not ordinary Host or cleanup acceptance.
fn installed_effect_content_model_fixture(
  ordinary_initial? : Bool = false,
) -> (
  ClientInstalledEffectContentPreparation,
  ClientInstalledEffectModelDemand,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) raise {
  let (environment, document) = effect_model_plan_source()
  let document = document
    .replace(
      old="{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"joined\"}",
      new="{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\",\"text\"],\"name\":\"out.jsonl\",\"preserve_order\":true,\"bounds\":{\"max_rows\":1,\"max_bytes\":128}},\"as\":\"attachment\"},{\"assert_rows\":{\"unique_by\":[\"name\"]},\"as\":\"joined\"}",
    )
    .replace(
      old="\"key\":\"id\",\"input\":{\"text\":{\"field\":\"text\"}}",
      new="\"key\":\"name\",\"input\":{\"text\":{\"field\":\"name\"}}",
    )
    .replace(
      old="\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"right.id\"}",
      new="\"on\":[{\"left\":\"name\",\"right\":\"name\"}],\"select\":{\"id\":\"right.row_count\"}",
    )
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let initial = if ordinary_initial {
    ordinary
  } else {
    @resources.add_ledger_limits(ordinary, effect_model_plan_limits).unwrap()
  }
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
    initial_limits=Some(initial),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let selected = @publication_host.prepared_client_effect_infer_occurrence(
    prepared,
  ).unwrap()
  let (occurrence, model_execution) = request_model_graph_inputs(selected.owner)
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  let component = prepare_request_serialization_graph(
    parent,
    input,
    0,
    1,
    request_graph_policy_cid,
    request_graph_policy_wire,
    1,
    128,
    false,
    contracts,
    manifests~,
    compilation_limits~,
    model_occurrence=Some(occurrence),
  ).unwrap()
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    model_execution,
    contracts,
    manifests~,
    compilation_limits~,
    serialization=Some(component),
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  assert_true(physical_equal(component.owner, graph.owner))
  let (_, request, _, model) = effect_model_plan_for_graph(prepared, graph)
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: source_capture_values(),
      output_values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  let content = prepare_installed_effect_content(
    prepared,
    model.compiled,
    model._compilation,
    model.definition,
    component,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    { max_work: 100000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    original_keyed_content_workspace(),
    {
      cancel: () => abort("no Content IO while preparing"),
      stopped: () => abort("no Content IO while preparing"),
      cleanup: () => abort("no Content IO while preparing"),
    },
    _ => abort("no Content execution while preparing"),
  ).unwrap()
  (content, model, request, contracts, parent, input, holder)
}

///|
test "Content Model Effect Plan retains one compiled original and simultaneous demand" {
  let (content, model, request, contracts, parent, input, holder) = installed_effect_content_model_fixture()
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    content.prepared,
    request,
    contracts,
    model,
    calls,
    content=Some(content),
  )
  assert_eq(calls.val, 1)
  assert_true(physical_equal(plan.content.unwrap(), content))
  assert_true(physical_equal(plan.model.unwrap(), model))
  assert_true(physical_equal(content.compiled, model.compiled))
  assert_true(plan.limits.retained_bytes >= model.limits.retained_bytes)
  assert_true(plan.limits.execution_bytes >= model.limits.execution_bytes)
  assert_true(
    @publication_host.client_infer_plan_graph_serialization(model.graph)
    is Some(component) &&
    physical_equal(component, content.component),
  )
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
}

///|
test "Content Model Effect ordinary startup preserves original policy and grows control before construction" {
  let (content, model, request, contracts, parent, input, holder) = installed_effect_content_model_fixture(
    ordinary_initial=true,
  )
  let plan = effect_model_plan_fixture(
    content.prepared,
    request,
    contracts,
    model,
    Ref(0),
    content=Some(content),
    host_input=true,
  )
  let ledger = parent.ledger
  let limits = @resources.ledger_limits(ledger)
  assert_false(installed_effect_limits_fit(plan.limits, limits))
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  assert_eq(@resources.ledger_limits(ledger), limits)
  retain_installed_effect_operation_controls_before_construction(
    run,
    content.prepared,
    request,
    plan,
  ).unwrap()
  |> ignore
  let control = run.effect_operation_controls.unwrap()
  let token = control.reservation
  let before = @resources.ledger_usage(ledger)
  let block = @resources.reserve_capacity(
    ledger,
    0L,
    limits.execution_bytes - before.reserved_execution_bytes,
  ).unwrap()
  let blocked = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_input(
      run,
      content.prepared,
      request,
      plan,
      "{}",
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), blocked)
  assert_true(physical_equal(control.reservation, token))
  @resources.settle_capacity(ledger, block).unwrap()
  begin_installed_effect_operation_control_input(
    run,
    content.prepared,
    request,
    plan,
    "{}",
  ).unwrap()
  let constructed = @resources.ledger_usage(ledger)
  assert_true(
    constructed.reserved_execution_bytes > before.reserved_execution_bytes,
  )
  assert_true(
    constructed.reserved_retention_bytes > before.reserved_retention_bytes,
  )
  complete_installed_effect_operation_control_construction(
    run,
    content.prepared,
    request,
    plan,
  ).unwrap()
  let completed = @resources.ledger_usage(ledger)
  assert_true(
    completed.reserved_execution_bytes < constructed.reserved_execution_bytes,
  )
  assert_eq(
    completed.reserved_retention_bytes,
    constructed.reserved_retention_bytes,
  )
  assert_true(physical_equal(run.effect_operation_controls.unwrap(), control))
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      false,
    ).unwrap(),
  )
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      true,
    ).unwrap(),
  )
  quiesce_installed_managed_run(run).unwrap()
  assert_true(run.effect_operation_closing)
  assert_true(run.effect_operation_controls is None)
  assert_true(
    retain_installed_effect_operation_controls_before_construction(
      run,
      content.prepared,
      request,
      plan,
    )
    is Err(Retired),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_limits(ledger), limits)
}

///|
test "Content Model Effect Plan rejects an equal but independently compiled Model before providers" {
  let (content, model, request, contracts, parent, _, holder) = installed_effect_content_model_fixture()
  let (_, _, _, other) = effect_model_plan_for_graph(
    content.prepared,
    model.graph,
  )
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let operation = prepare_installed_effect_operation_demand(
    content.prepared,
    0,
    "save",
    [extent],
    [extent],
  ).unwrap()
  assert_true(
    prepare_installed_effect_managed_plan(
      content.prepared,
      request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      [operation],
      model=Some(other),
      content=Some(content),
      provider_factory=_ => {
        abort("foreign compiled original cannot select providers")
      },
    )
    is Err(ForeignOriginal),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
}
