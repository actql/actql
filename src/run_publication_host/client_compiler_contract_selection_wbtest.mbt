///|
test "installed ordered compilation uses the original contract without body readmission" {
  let value = ordered_client_program()
  let limits = run_materials_limits().sequence
  let physical : @execution.RegistryLimits = {
    max_body_bytes: 1000000,
    max_body_nodes: 100000,
    max_body_depth: 100,
  }
  let sequence = prepare_prepared_client_full_sequence(value, 0, limits).unwrap()
  let full_admissions = Ref(0)
  let admit = bounds => {
    full_admissions.val += 1
    // Count the actual complete three-body parse/admission, not the public
    // forwarding entry or an already-cached emission.
    client_compiler_ordered_contract(bounds)
  }
  let standalone = prepare_client_sequence_steps_owned(
    sequence,
    0,
    @lower.sequence_count(sequence),
    physical,
    None,
    admit~,
  )
  assert_eq(full_admissions.val, 1)
  assert_eq(standalone.ordered.length(), 1)
  let original = client_compiler_ordered_contract(physical).unwrap()
  bind_prepared_client_compiler_contracts(value, Some(original)).unwrap()
  let bound = prepare_client_sequence_steps_owned(
    sequence,
    0,
    @lower.sequence_count(sequence),
    physical,
    value.compiler_contracts,
    admit~,
  )
  assert_eq(full_admissions.val, 1)
  assert_eq(bound.ordered.length(), 1)
  guard @lower.sequence_step(sequence, bound.ordered[0].0)
    is Some(@lower.RowStep(kernel)) else {
    fail("the authored ordered step must remain a Row kernel")
  }
  let expected = @execution.prepare_ordered_params(
    original,
    @lower.prepare_ordered_references(kernel, {
      max_references: physical.max_body_nodes,
      max_pointer_bytes: physical.max_body_bytes,
      max_work: physical.max_body_bytes,
      max_frames: physical.max_body_depth,
    }).unwrap(),
  )
  let registry = @execution.ordered_params_registry(expected)
  assert_true(
    physical_equal(
      registry,
      @execution.ordered_params_registry(bound.ordered[0].1),
    ),
  )
  assert_false(
    physical_equal(
      registry,
      @execution.ordered_params_registry(standalone.ordered[0].1),
    ),
  )
  let bound_wire = emit_prepared_client_task_pipeline(
    value, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  let actual = value.task_pipeline_inputs[0].input.emission.unwrap().steps
  assert_true(
    physical_equal(
      registry,
      @execution.ordered_params_registry(actual.ordered[0].1),
    ),
  )
  let independent = ordered_client_program()
  let independent_wire = emit_prepared_client_task_pipeline(
    independent, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(bound_wire, independent_wire)
  assert_true(
    emit_prepared_client_task_pipeline(value, 0, limits, 1, 100000, 100)
    is Err(Encoding),
  )
  assert_eq(
    emit_prepared_client_task_pipeline(value, 0, limits, 1000000, 100000, 100).unwrap(),
    bound_wire,
  )
}

///|
test "explicit installed ordered absence refuses without standalone fallback" {
  let value = ordered_client_program()
  bind_prepared_client_compiler_contracts(value, None).unwrap()
  let sequence = prepare_prepared_client_full_sequence(
    value,
    0,
    run_materials_limits().sequence,
  ).unwrap()
  let calls = Ref(0)
  assert_true(
    try {
      prepare_client_sequence_steps_owned(
        sequence,
        0,
        @lower.sequence_count(sequence),
        {
          max_body_bytes: 1000000,
          max_body_nodes: 100000,
          max_body_depth: 100,
        },
        value.compiler_contracts,
        admit=bounds => {
          calls.val += 1
          client_compiler_ordered_contract(bounds)
        },
      )
      |> ignore
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
  )
  assert_eq(calls.val, 0)
  assert_true(
    emit_prepared_client_task_pipeline(
      value,
      0,
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
    )
    is Err(Encoding),
  )
  let present = client_compiler_ordered_contract({
    max_body_bytes: 1000000,
    max_body_nodes: 100000,
    max_body_depth: 100,
  }).unwrap()
  assert_true(
    bind_prepared_client_compiler_contracts(value, Some(present))
    is Err(Encoding),
  )
  bind_prepared_client_compiler_contracts(value, None).unwrap()
}

///|
test "compiler contract binding preserves original views and rejects foreign or late replacement" {
  let limits : @execution.RegistryLimits = {
    max_body_bytes: 1000000,
    max_body_nodes: 100000,
    max_body_depth: 100,
  }
  let original = client_compiler_ordered_contract(limits).unwrap()
  let foreign = client_compiler_ordered_contract(limits).unwrap()
  let value = ordered_client_program()
  bind_prepared_client_compiler_contracts(value, Some(original)).unwrap()
  bind_prepared_client_compiler_contracts(value, Some(original)).unwrap()
  assert_true(
    bind_prepared_client_compiler_contracts(value, Some(foreign))
    is Err(Encoding),
  )
  assert_true(
    bind_prepared_client_compiler_contracts(value, None) is Err(Encoding),
  )
  let view = with_prepared_client_values_row_limit(value, 1000).unwrap()
  assert_true(
    physical_equal(
      value.compiler_contracts.unwrap(),
      view.compiler_contracts.unwrap(),
    ),
  )
  bind_prepared_client_compiler_contracts(view, Some(original)).unwrap()
  let independent = ordered_client_program()
  bind_prepared_client_compiler_contracts(independent, Some(foreign)).unwrap()
  let late = ordered_client_program()
  let _ = emit_prepared_client_task_pipeline(
    late,
    0,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(
    bind_prepared_client_compiler_contracts(late, Some(original))
    is Err(Encoding),
  )
}
