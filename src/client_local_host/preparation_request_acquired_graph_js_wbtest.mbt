///|
// This fixture's existing keyed Plan/Resource setup is explicit. These cases
// qualify the new same-Request Graph boundary, not pre-Plan/provider/physical
// backing or ordinary Content acceptance.
test "same Request acquired Graph reserves its provenance and keeps original component through keyed compiler" {
  let (parent, input, prepared, selected, _) = request_content_fixture()
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let contracts = selected.installed_contracts
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let policy = @publication_host.prepared_client_serialization_policy_construction(
    prepared,
    selected.serialization_task,
  ).unwrap()
  assert_true(
    policy.bodies > 1 &&
    policy.response_total is Some(_) &&
    policy.response_max is Some(_),
  )
  let graph = prepare_request_acquired_serialization_graph(
    parent,
    input,
    selected.serialization_task,
    selected.serialization_step,
    3,
    4096,
    true,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let actual_wire = @publication.captured_effect_dependency_body_json(
    graph.policy,
  )
  assert_true(actual_wire.length() <= policy.effective.0)
  assert_true(physical_equal(graph.owner, prepared))
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  let compiled = prepare_request_keyed_serialization_compilation(
    parent,
    input,
    selected,
    graph,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  assert_true(
    parent.program_invocation_quote is Some((r, e)) &&
    @resources.preparation_capacity_working_extents(capacity, input) ==
    Ok((r, e)),
  )
  assert_true(
    @publication_host.client_task_compilation_serialization(compiled)
    is Some(original) &&
    physical_equal(original, graph),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "acquired Graph original-current refusal enters no policy issuer and leaves same parent cleanup" {
  let armed = Ref(false)
  let calls = Ref(0)
  let (parent, input, _, selected, _) = request_content_fixture(current=() => {
    if armed.val {
      calls.val += 1
      false
    } else {
      true
    }
  })
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let before = request_preparation_accounting(parent)
  armed.val = true
  assert_true(
    prepare_request_acquired_serialization_graph(
      parent,
      input,
      selected.serialization_task,
      selected.serialization_step,
      3,
      4096,
      true,
      selected.installed_contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(
    calls.val > 0 &&
    parent.phase == ProgramBodyFailed &&
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
