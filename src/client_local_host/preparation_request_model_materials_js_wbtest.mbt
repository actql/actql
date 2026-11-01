///|
// Real Request capacity and original binding issuers. Resource installation
// remains this fixture's explicit admission, not normal Model/Provider IO.
test "Model material callback is fenced and backed before entry on the same Request" {
  let (parent, input, _) = request_model_input_fixture()
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let observed = Ref(true)
  prepare_request_model_contract_materials(
    parent,
    input,
    3,
    index => {
      observed.val = observed.val && parent.phase == Selecting
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = observed.val && during.0 > before.0 && during.1 > before.1
      observed.val = observed.val &&
        prepare_request_model_contract_materials(parent, input, 0, _ => "", 0)
        is Err(Preparation(ForeignOriginal))
      observed.val = observed.val && index == calls.val
      calls.val += 1
      ["{\"prompt\":\"original\"}", "{\"retry\":[]}", "{\"backoff\":1}"][index]
    },
    4,
  ).unwrap()
  assert_eq(calls.val, 3)
  assert_true(observed.val)
  assert_true(parent.phase == ModelPlanReserved)
  assert_true(parent.program_domain_quote is None)
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model material current refusal never enters body callback and retains original abort custody" {
  let armed = Ref(false)
  let (parent, input, _) = request_model_input_fixture(current=() => !armed.val)
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let calls = Ref(0)
  armed.val = true
  assert_true(
    prepare_request_model_contract_materials(
      parent,
      input,
      1,
      _ => {
        calls.val += 1
        "{}"
      },
      1,
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_eq(calls.val, 0)
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(
    parent.program_capacity is Some(_) && parent.program_compilation is None,
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model binding keeps original Graph and reserves input plus sealed output before old issuer" {
  for invalid in [false, true] {
    let (parent, input, prepared) = request_model_input_fixture()
    let holder = borrow_request_model_plan_input(parent, input).unwrap()
    let (occurrence, execution) = request_model_graph_inputs(prepared)
    let graph = prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    ).unwrap()
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let binding = prepare_request_model_provider_binding(
      parent,
      input,
      "mock",
      if invalid {
        "{invalid"
      } else {
        "{\"installation\":1}"
      },
      "{\"contract\":2}",
      "{\"configuration\":3}",
    )
    if invalid {
      assert_true(binding is Err(ModelBinding(_)))
      assert_true(parent.phase == ProgramBodyFailed)
    } else {
      let actual = binding.unwrap()
      let original = @publication_host.issue_client_model_provider_binding(
        "mock", "{\"installation\":1}", "{\"contract\":2}", "{\"configuration\":3}",
      ).unwrap()
      assert_eq(
        @publication.run_evidence_value_json(actual),
        @publication.run_evidence_value_json(original),
      )
      assert_true(parent.phase == ModelPlanReserved)
      assert_true(parent.program_domain_quote is None)
    }
    assert_true(
      parent.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, same)) &&
      physical_equal(same, graph),
    )
    let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    assert_true(after.0 > before.0 && after.1 > before.1)
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "serialized Model material originals grow on the same Request before Graph and provider readers" {
  let (parent, input, _) = request_model_input_fixture(with_serialization=true)
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let observed = Ref(true)
  prepare_request_model_contract_materials(
    parent,
    input,
    2,
    index => {
      observed.val = observed.val &&
        parent.phase == Selecting &&
        parent.program_domain_compilation_inputs is None &&
        parent.program_compilation is None
      let current = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = observed.val &&
        current.0 > before.0 &&
        current.1 > before.1 &&
        index == calls.val
      calls.val += 1
      ["{\"execution\":\"original\"}", "{\"dependency\":\"original\"}"][index]
    },
    2,
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_true(observed.val)
  assert_true(parent.phase == ModelPlanReserved)
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "serialized Model material current refusal precedes original reader and keeps same parent abort" {
  let armed = Ref(false)
  let (parent, input, _) = request_model_input_fixture(
    with_serialization=true,
    current=() => !armed.val,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let calls = Ref(0)
  armed.val = true
  assert_true(
    prepare_request_model_contract_materials(
      parent,
      input,
      1,
      _ => {
        calls.val += 1
        "{}"
      },
      1,
    )
    is Err(Preparation(Capacity(_))),
  )
  assert_eq(calls.val, 0)
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(parent.program_capacity is Some(_))
  assert_true(parent.program_compilation is None)
  armed.val = false
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
