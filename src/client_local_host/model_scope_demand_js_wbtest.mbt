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
