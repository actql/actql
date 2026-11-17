///|
test "Node Model demand retains distinct original bootstrap and complete read overlap" {
  let model = effect_model_plan_limits
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  // Explicit component DATA: a complete read can occupy half the unchanged
  // parent window while its independently retained bootstrap is small. This
  // does not declare a physical installation or supply Resource admission.
  let read = ordinary.execution_bytes / 2L
  let exact = installed_model_demand_limits(
    model,
    7000L,
    read,
    bootstrap=Some((31L, 37L)),
  ).unwrap()
  assert_eq(exact.retained_bytes, model.retained_bytes + 31L + 7000L)
  assert_eq(exact.execution_bytes, model.execution_bytes + 37L + read)
  assert_eq(exact.planning_work, model.planning_work)
  assert_eq(exact.attempts, model.attempts)
  assert_eq(exact.holdings, model.holdings)
  assert_eq(exact.transfer_bytes, model.transfer_bytes)
  assert_true(installed_effect_limits_fit(exact, ordinary))
  let legacy = installed_model_demand_limits(model, 7000L, read).unwrap()
  assert_eq(legacy.execution_bytes, model.execution_bytes + read + read)
  assert_false(installed_effect_limits_fit(legacy, ordinary))
  for pair in [(0L, 37L), (31L, -1L), (9223372036854775807L, 37L)] {
    assert_true(
      installed_model_demand_limits(model, 7000L, read, bootstrap=Some(pair))
      is None,
    )
  }
}

///|
test "same Request Model Scope uses configured planning demand and keeps original cleanup" {
  let (f, selected_module, prefix) = request_node_model_plan_inputs()
  let layout = request_node_model_layout_declaration(f.graph)
  let plan = prepare_request_node_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    Some(layout),
    request_node_model_layout_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    20,
    20,
    20,
    bootstrap=Some((31L, 37L)),
  ).unwrap()
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  assert_true(selected_module.limits.planning_work == ordinary.planning_work)
  assert_true(
    plan.limits.planning_work > effect_model_plan_limits.planning_work,
  )
  assert_true(plan.limits.planning_work < ordinary.planning_work)
  assert_true(physical_equal(plan.source_free.unwrap(), selected_module))
  assert_true(physical_equal(plan.content_prefix.unwrap(), prefix))
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Node Model Plan keeps the exact physical component limits on its same claimed Scope" {
  let (f, selected_module, prefix) = request_node_model_plan_inputs()
  let layout = request_node_model_layout_declaration(f.graph)
  let support = @environment.model_response_profile_limits(
    layout.response_profile,
  )
  let physical = @resources.add_ledger_limits(effect_model_plan_limits, {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: support.adapter_holding_bytes.to_int64(),
    execution_bytes: support.adapter_workspace_bytes.to_int64(),
  }).unwrap()
  let plan = prepare_request_node_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    physical,
    Some(layout),
    request_node_model_layout_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    20,
    20,
    20,
  ).unwrap()
  assert_true(physical_equal(plan.model_limits, physical))
  assert_true(plan.limits.retained_bytes > physical.retained_bytes)
  assert_eq(plan.model_limits.attempts, effect_model_plan_limits.attempts)
  assert_eq(
    plan.model_limits.transfer_bytes,
    effect_model_plan_limits.transfer_bytes,
  )
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  request_node_model_complete_prefix(run, f, prefix)
  let read = @publication_host.prepare_client_node_model_read_layout(
    scope,
    f.compiled,
    f.definition,
    f.graph,
    Some(layout),
    request_node_model_layout_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  let consumer = @publication_host.claim_client_node_model_preparation_layout(
    read,
    f.compiled,
    f.definition,
    f.graph,
    Some(layout),
    request_node_model_layout_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  let selected = @publication_host.client_model_read_consumer_model_limits(
      consumer,
      f.compiled,
      f.definition,
      f.graph,
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(selected, physical))
  assert_true(physical_equal(run.ledger.unwrap(), f.parent.ledger))
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @publication_host.stop_client_model_read(read).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Node Model physical layout exact minimum admits while one-short and foreign refuse before Plan" {
  let (f, selected_module, _) = request_node_model_plan_inputs()
  let original = request_node_model_layout_declaration(f.graph)
  let support = @environment.model_response_profile_limits(
    original.response_profile,
  )
  let exact = {
    ..original,
    retained_bytes: support.adapter_holding_bytes.to_int64(),
    execution_bytes: support.adapter_workspace_bytes.to_int64(),
  }
  let before = @resources.ledger_usage(f.parent.ledger)
  for
    layout in [
      { ..exact, retained_bytes: exact.retained_bytes - 1L, },
      { ..exact, execution_bytes: exact.execution_bytes - 1L, },
      { ..exact, parameter_values_cid: "sha256:" + "f".repeat(64), },
    ] {
    assert_true(
      prepare_request_node_model_source_free_plan(
        f.parent,
        f.input,
        selected_module,
        f.request,
        f.compiled,
        f.definition,
        f.occurrence,
        f.graph,
        effect_model_plan_limits,
        Some(layout),
        request_node_model_layout_installation(),
        original.runtime_artifact_cid,
        original.layout_artifact_cid,
        None,
        20,
        20,
        20,
      )
      is Err(ModelLayout(_)),
    )
    assert_true(f.parent.program_model is None)
    assert_eq(@resources.ledger_usage(f.parent.ledger), before)
  }
  assert_true(
    @resources.add_ledger_limits(effect_model_plan_limits, {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 9223372036854775807L,
      execution_bytes: 0L,
    })
    is None,
  )
  let plan = prepare_request_node_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    Some(exact),
    request_node_model_layout_installation(),
    exact.runtime_artifact_cid,
    exact.layout_artifact_cid,
    None,
    20,
    20,
    20,
  ).unwrap()
  assert_true(physical_equal(plan.model_limits, effect_model_plan_limits))
  // No Scope/Model/transport was started. The original Request owns and
  // retires its Plan, compilation, prefix and construction borrow unchanged.
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Model Plan borrowed limit field is funded before Plan retention on the original Request" {
  let (parent, input, _) = request_model_input_fixture()
  let ordinary = borrow_request_program_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(parent.program_model is None)
  let model = borrow_request_model_plan_input(parent, input).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let record = @execution.preparation_representation_cost(
    installed_model_plan_record,
  ).unwrap()
  assert_eq(after.0 - before.0, record)
  assert_eq(after.1 - before.1, record)
  // One borrowed immutable component ceiling adds one logical reference word;
  // it does not own/copy the LedgerLimits tree or alter the Request root layout.
  let prior = @execution.preparation_representation_cost({
    ..installed_model_plan_record,
    reference_slots: 11L,
  }).unwrap()
  assert_eq(record - prior, 8L)
  assert_true(parent.program_model is None)
  @resources.return_preparation_body_borrow(model).unwrap() |> ignore
  @resources.return_preparation_body_borrow(ordinary).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
