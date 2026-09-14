///|
test "pivot numeric templates retain exact owners and budget empty generated axes" {
  let profile = numeric_profile_fixture()
  for function in ["sum", "avg", "count", "min"] {
    for columns in ["[]", "[\"z\",\"a\",\"😀\"]"] {
      let text = "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"pivot\":{\"index\":[],\"column\":\"x\",\"values\":" +
        columns +
        ",\"value\":\"id\",\"aggregate\":\"" +
        function +
        "\",\"fill\":{\"$param\":\"n\"}}}]"
      let profiles = resolution_profiles(operation_order_fixture(text))
      let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
      let requirements = operation_resolution_requirements(index)
      let slots = prepare_program_pivot_numeric_slots(
        requirements, profile, 10000000, 3, 9,
      ).unwrap()
      let expected = if function == "sum" || function == "avg" { 3 } else { 0 }
      let identity = expression_closure_identity(
        operation_requirements_expressions(requirements),
      )
      let limits : CoreContractLimits = {
        max_work: 10000000,
        max_roots: 1000,
        max_bodies: 100,
        max_edges: 1000,
      }
      let base = collect_core_contracts(identity, limits).unwrap()
      let inventory = collect_core_contracts(
        identity,
        limits,
        pivot_numeric_slots=Some(slots),
      ).unwrap()
      assert_true(
        physical_equal(
          core_contract_pivot_numeric_slots(inventory).unwrap(),
          slots,
        ),
      )
      assert_eq(
        core_contract_body_count(inventory),
        core_contract_body_count(base) + (if expected == 0 { 0 } else { 6 }),
      )
      let mut profile_roots = 0
      let mut slot_roots = 0
      for i in 0..<core_contract_root_count(inventory) {
        let root = core_contract_root_at(inventory, i).unwrap()
        match root.site {
          NumericAggregateProfile(stage, visit, step, _) => {
            profile_roots += 1
            assert_eq(
              program_identity_producer_is_local(identity, stage, visit),
              Some(true),
            )
            assert_eq(step, 1)
            assert_eq(core_contract_cid(root.body), @numeric.cid(profile))
          }
          NumericAggregateSlotRules(stage, visit, step, _) => {
            slot_roots += 1
            assert_eq(
              program_identity_producer_is_local(identity, stage, visit),
              Some(true),
            )
            assert_eq(step, 1)
            assert_eq(
              core_contract_cid(root.body),
              "sha256:54c19c5dc586979bfd5cfa7afed23011e8394dd4a8623c32ba6ca0f83fb01858",
            )
          }
          _ => ()
        }
      }
      // The imported visit adds no direct dependency; width zero still selects
      // the profile and slot interpretation for both local occurrences.
      assert_eq(profile_roots, if expected == 0 { 0 } else { 2 })
      assert_eq(slot_roots, profile_roots)
      let (inventory_work, _) = core_contract_usage(inventory)
      assert_true(
        collect_core_contracts(
          identity,
          { ..limits, max_work: inventory_work, },
          pivot_numeric_slots=Some(slots),
        )
        is Ok(_),
      )
      assert_true(
        collect_core_contracts(
          identity,
          { ..limits, max_work: inventory_work - 1, },
          pivot_numeric_slots=Some(slots),
        )
        is Err(BudgetExceeded),
      )
      let width = if columns == "[]" { 0 } else { 3 }
      assert_eq(pivot_numeric_demand_count(slots), expected)
      assert_eq(pivot_numeric_total_slot_count(slots), expected * width)
      assert_true(
        physical_equal(pivot_numeric_slots_requirements(slots), requirements),
      )
      let work = pivot_numeric_slots_work(slots)
      assert_true(
        prepare_program_pivot_numeric_slots(
          requirements,
          profile,
          work,
          expected,
          expected * width,
        )
        is Ok(_),
      )
      assert_true(
        prepare_program_pivot_numeric_slots(
          requirements,
          profile,
          work - 1,
          expected,
          expected * width,
        )
        is Err(BudgetExceeded),
      )
      if expected > 0 {
        assert_true(
          prepare_program_pivot_numeric_slots(
            requirements,
            profile,
            work,
            expected - 1,
            9,
          )
          is Err(BudgetExceeded),
        )
        if width > 0 {
          assert_true(
            prepare_program_pivot_numeric_slots(
              requirements,
              profile,
              work,
              expected,
              expected * width - 1,
            )
            is Err(BudgetExceeded),
          )
        }
      }
      let linked = link_program_pivot_numeric_slots(
        index, slots, 10000000, expected,
      ).unwrap()
      assert_eq(
        operation_resolution_unresolved_count(linked),
        operation_resolution_unresolved_count(index) - expected,
      )
      assert_true(close_program_operations(linked, 10000000, 100) is Ok(_))
      for i in 0..<expected {
        let demand = pivot_numeric_demand_at(slots, i).unwrap()
        assert_true(
          physical_equal(demand, pivot_numeric_demand_at(slots, i).unwrap()),
        )
        assert_true(physical_equal(demand.profile, profile))
        assert_eq(demand.input, @pipeline.Step(0))
        assert_eq(pivot_numeric_slot_count(demand), width)
        if width > 0 {
          assert_eq(pivot_numeric_slot_name_at(demand, 0), Some("a"))
          assert_eq(pivot_numeric_slot_name_at(demand, 1), Some("z"))
          assert_eq(pivot_numeric_slot_name_at(demand, 2), Some("😀"))
          assert_eq(@relation.pivot_value_at(demand.pivot, 0), Some("z"))
        }
        assert_eq(pivot_numeric_slot_name_at(demand, -1), None)
        assert_eq(pivot_numeric_slot_name_at(demand, width), None)
        assert_true(
          operation_resolution_at(index, demand.requirement_index)
          is Some(Unresolved),
        )
        guard operation_resolution_at(linked, demand.requirement_index)
          is Some(Execution(PivotExecution(check))) &&
          check.rule is CaptureNumericObservations(retained) else {
          fail("numeric demand not retained")
        }
        assert_true(physical_equal(retained, demand))
        assert_true(physical_equal(check.site, demand.site))
        assert_eq(
          operation_execution_phase(PivotExecution(check)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(PivotExecution(check)),
          RejectOperationOutput,
        )
      }
      assert_true(pivot_numeric_demand_at(slots, -1) is None)
      assert_true(pivot_numeric_demand_at(slots, expected) is None)
      let used = operation_resolution_work(linked)
      assert_true(
        link_program_pivot_numeric_slots(index, slots, used, expected) is Ok(_),
      )
      assert_true(
        link_program_pivot_numeric_slots(index, slots, used - 1, expected)
        is Err(BudgetExceeded),
      )
      if expected > 0 {
        assert_true(
          link_program_pivot_numeric_slots(index, slots, used, expected - 1)
          is Err(BudgetExceeded),
        )
        assert_true(
          link_program_pivot_numeric_slots(linked, slots, 10000000, expected)
          is Err(ForeignOccurrence(_)),
        )
      }
      let other = resolution_profiles(operation_order_fixture(text))
      let foreign = index_program_operation_resolutions(other, 10000000, 100).unwrap()
      let foreign_identity = expression_closure_identity(
        operation_requirements_expressions(
          operation_resolution_requirements(foreign),
        ),
      )
      // Matching source semantics (including an empty demand inventory) cannot
      // substitute for the exact checked owner.
      assert_eq(
        program_identity_definition_cid(identity),
        program_identity_definition_cid(foreign_identity),
      )
      assert_true(
        collect_core_contracts(
          foreign_identity,
          limits,
          pivot_numeric_slots=Some(slots),
        )
        is Err(ForeignNumericSlots),
      )
      assert_true(
        link_program_pivot_numeric_slots(foreign, slots, 10000000, expected)
        is Err(ForeignOccurrence(-1)),
      )
      // The other numeric families neither consume nor misclassify pivot slots.
      assert_eq(
        numeric_slot_count(
          prepare_program_numeric_slots(requirements, profile, 10000000, 100).unwrap(),
        ),
        0,
      )
      assert_eq(
        analytic_numeric_slot_count(
          prepare_program_analytic_numeric_slots(
            requirements, profile, 10000000, 100,
          ).unwrap(),
        ),
        0,
      )
    }
  }
}
