///|
test "prepared Local inputs retain raw admission requirements without assuming primary key validity" {
  for first_by_order in [false, true] {
    let (identity, _, _) = prepared_identity_fixture(first_by_order~)
    let requirements = collect_program_operation_requirements(
      close_program_expressions(identity, 10000000, 0).unwrap(),
      10000000,
      0,
    ).unwrap()
    let profiles = resolution_profiles(requirements)
    let caps : IncomingLimits = {
      max_work: 10000000,
      max_name_units: 10000,
      max_requirements: 3,
    }
    let incoming = collect_program_incoming(identity, caps).unwrap()
    let linked = link_program_incoming(profiles, incoming, caps).unwrap()
    assert_eq(incoming_links_local_input_count(linked), 1)
    let input = incoming_links_local_input_at(linked, 0).unwrap()
    assert_eq(input.stage, 0)
    assert_eq(input.declaration_index, 0)
    assert_eq(input.name, "rows")
    assert_eq(input.target, @pipeline.Input(0))
    assert_true(
      physical_equal(
        input.pipeline,
        @parameter_slots.pipeline(
          @stages.collection(@local_inputs.reconciled_stage(input.attachment)),
        ),
      ),
    )
    let prepared = @local_inputs.snapshot_inputs(
      @local_inputs.environment_assertions(
        @local_inputs.reconciled_inputs(input.attachment),
      ),
    )
    assert_true(
      physical_equal(
        input.declaration,
        @local_inputs.entry_at(prepared, 0).unwrap().1,
      ),
    )
    guard input.registration is @pipeline.KeyedInput(key) else {
      abort("declared key")
    }
    assert_true(
      physical_equal(key, @local_input.primary_key(input.declaration).unwrap()),
    )
    assert_eq(
      @local_input.has_first_by_order(input.declaration),
      first_by_order,
    )
    assert_eq(
      input.disposition,
      if first_by_order {
        DuplicateOrderUnresolved
      } else {
        RejectDuplicatesAdmission
      },
    )
    // Repeating the key as the ordering term cannot supply an independent total
    // order proof. It remains unresolved, never a runtime permission to repair.
    for index in [-2147483648, -1, 1, 2147483647] {
      assert_true(incoming_links_local_input_at(linked, index) is None)
    }
    let used = incoming_links_work(linked)
    assert_true(
      link_program_incoming(profiles, incoming, { ..caps, max_work: used, })
      is Ok(_),
    )
    assert_true(
      link_program_incoming(profiles, incoming, { ..caps, max_work: used - 1, })
      is Err(BudgetExceeded),
    )
    let without_inputs = operation_resolution_work(
        incoming_links_resolutions(linked),
      ) +
      program_incoming_usage(incoming).0 -
      program_identity_usage(identity).0 +
      1
    assert_eq(used - without_inputs, 7) // two stages, one input, four name units
    assert_true(
      link_program_incoming(profiles, incoming, {
        ..caps,
        max_work: without_inputs,
      })
      is Err(BudgetExceeded),
    )
  }
}
