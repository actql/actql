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
    if first_by_order {
      assert_true(local_input_execution_count(input) is None)
      assert_true(local_input_execution_at(input, 0) is None)
    } else {
      assert_eq(local_input_execution_count(input), Some(3))
      let kinds : Array[LocalInputExecutionKind] = [
        RawBinding,
        PrimaryKeyComponents,
        PrimaryKeyUniqueness,
      ]
      for i in 0..<3 {
        let check = local_input_execution_at(input, i).unwrap()
        assert_eq(check.kind, kinds[i])
        assert_true(physical_equal(check.subject, input))
        assert_eq(local_input_execution_phase(check), BeforeLocalInputUse)
        assert_eq(local_input_execution_failure(check), RejectLocalInput)
        let prior = local_input_execution_predecessor(check)
        if i == 0 {
          assert_true(prior is None)
        } else {
          let prior = prior.unwrap()
          assert_eq(prior.kind, kinds[i - 1])
          assert_true(physical_equal(prior.subject, input))
        }
      }
    }
    for index in [-2147483648, -1, 3, 2147483647] {
      assert_true(local_input_execution_at(input, index) is None)
    }
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
