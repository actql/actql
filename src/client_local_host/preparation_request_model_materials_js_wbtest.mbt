///|
// Complete only the real Effect checker/compiler and retain its same Plan
// input. No Model execution/dependency reader, Graph, binding or Scope enters.
fn request_effect_model_material_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) raise {
  let (environment, text) = effect_model_plan_source()
  let initial = @resources.add_ledger_limits(
    client_local_preparation_initial_limits(client_local_resource_policy()).unwrap(),
    effect_model_plan_limits,
  ).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text~,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
    initial_limits=Some(initial),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  compile_effect_program_check_preparation(child).unwrap() |> ignore
  continue_request_effect_preparation(parent, input).unwrap() |> ignore
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  (parent, input, holder)
}

///|
test "Effect Model material reserves original containers before its only body callback" {
  let (parent, input, holder) = request_effect_model_material_fixture()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let observed = Ref(true)
  prepare_request_model_contract_materials(
    parent,
    input,
    2,
    index => {
      calls.val += 1
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = observed.val &&
        parent.phase == Selecting &&
        during.0 > before.0 &&
        during.1 > before.1 &&
        prepare_request_model_contract_materials(parent, input, 0, _ => "", 0)
        is Err(Preparation(ForeignOriginal))
      ["{\"execution\":1}", "{\"dependency\":2}"][index]
    },
    3,
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_true(observed.val)
  assert_true(
    parent.phase == EffectPlanReserved && parent.program_capacity is None,
  )
  assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
}

///|
test "Effect Model material binding reserves its same input and sealed output before issuer" {
  let (parent, input, holder) = request_effect_model_material_fixture()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let binding = prepare_request_model_provider_binding(
    parent, input, "mock", "{\"installation\":1}", "{\"contract\":2}", "{\"configuration\":3}",
  ).unwrap()
  let expected = @publication_host.issue_client_model_provider_binding(
    "mock", "{\"installation\":1}", "{\"contract\":2}", "{\"configuration\":3}",
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(binding),
    @publication.run_evidence_value_json(expected),
  )
  assert_true(
    parent.phase == EffectPlanReserved && parent.program_capacity is None,
  )
  assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect Model material current refusal retains the original family before or after body observation" {
  for denied in [1, 2] {
    let armed = Ref(false)
    let currents = Ref(0)
    let reads = Ref(0)
    let (parent, input, holder) = request_effect_model_material_fixture(current=() => {
      if !armed.val {
        return true
      }
      currents.val += 1
      currents.val != denied
    })
    armed.val = true
    assert_true(
      prepare_request_model_contract_materials(
        parent,
        input,
        1,
        _ => {
          reads.val += 1
          "{\"original\":true}"
        },
        1,
      )
      is Err(Preparation(Capacity(_))),
    )
    assert_eq(reads.val, if denied == 1 { 0 } else { 1 })
    assert_true(
      parent.phase == EffectBodyFailed && parent.program_capacity is None,
    )
    assert_true(
      parent.effect_capacity is Some(_) &&
      parent.program_domain_quote is Some(_),
    )
    armed.val = false
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
  }
}

///|
test "Effect Model material invalid binding keeps the same failed parent and no replacement issuer" {
  let (parent, input, holder) = request_effect_model_material_fixture()
  assert_true(
    prepare_request_model_provider_binding(
      parent, input, "mock", "{invalid", "{\"contract\":2}", "{\"configuration\":3}",
    )
    is Err(ModelBinding(_)),
  )
  assert_true(
    parent.phase == EffectBodyFailed && parent.program_capacity is None,
  )
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_model_provider_binding(
      parent, input, "mock", "{\"installation\":1}", "{\"contract\":2}", "{\"configuration\":3}",
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

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

///|
test "single captured Model materials use the original occurrence before Graph construction" {
  let (parent, input, prepared) = request_model_input_fixture(
    single_capture=true,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  assert_false(installed_managed_run_shape_supported(prepared, true))
  assert_true(
    installed_managed_owner_shape_supported(
      Pure(prepared),
      true,
      model_occurrence=Some(occurrence),
    ),
  )
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let observed = Ref(false)
  prepare_request_model_contract_materials(
    parent,
    input,
    1,
    _ => {
      calls.val += 1
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = parent.phase == Selecting &&
        during.0 > before.0 &&
        during.1 > before.1
      "{\"execution\":\"original\"}"
    },
    1,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(observed.val)
  assert_true(parent.phase == ModelPlanReserved)
  assert_true(
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "single captured Model materials retain original current refusal before reader entry" {
  let armed = Ref(false)
  let (parent, input, _) = request_model_input_fixture(single_capture=true, current=() => {
    !armed.val
  })
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
  assert_true(
    parent.phase == ProgramBodyFailed && parent.program_capacity is Some(_),
  )
  assert_true(
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  armed.val = false
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
