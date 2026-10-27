///|
let empty_family_module_containers : @execution.PreparationRepresentationUnits = @local.local_module_container_inventory(
  1, 0,
).unwrap()

///|
test "closed Values initial recipe has one owned control tariff and combined exact scanner boundary" {
  let policy = client_local_resource_policy()
  let (retained, execution) = client_closed_values_initial_control_capacity(
    policy,
    module_containers=empty_family_module_containers,
  ).unwrap()
  assert_eq(
    preparation_node_own_data_scan_cost().unwrap() +
    preparation_node_own_data_header_cost().unwrap(),
    416L,
  )
  assert_eq(
    execution,
    416L +
    @execution.preparation_representation_cost(
      closed_values_projection_scratch_units(),
    ).unwrap(),
  )
  assert_eq(
    retained,
    @execution.preparation_representation_cost(
      closed_values_initial_control_units(empty_family_module_containers),
    ).unwrap(),
  )
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  for allowance in [execution - 1L, execution] {
    let ledger = @resources.create_ledger({
      ..limits,
      retained_bytes: retained,
      execution_bytes: allowance,
    }).unwrap()
    let input = [1]
    let result : Result[
      @resources.PreparationCapacity[Array[Int], Array[Int]],
      @resources.PreparationCapacityIssue,
    ] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      retained,
      execution,
      max_borrowers=1,
    )
    if allowance == execution - 1L {
      assert_true(
        result
        is Err(
          @resources.PreparationCapacityIssue::Resource(
            @resources.LedgerIssue::ExecutionLimit
          )
        ),
      )
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    } else {
      assert_true(result is Ok(_))
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.reserved_retention_bytes, retained)
      assert_eq(usage.reserved_execution_bytes, execution)
      assert_eq(usage.peak_retention_bytes, retained)
      let owner = result.unwrap()
      let actual = @resources.preparation_capacity_accounting(owner)
      assert_eq(
        actual,
        (retained, execution, 0L, retained, retained, execution),
      )
      assert_eq(
        @resources.abort_preparation_capacity_after_cleanup(owner, input),
        Ok(true),
      )
      assert_eq(
        @resources.preparation_capacity_accounting(owner),
        (0L, 0L, 0L, retained, 0L, 0L),
      )
    }
  }
}

///|
test "closed preparation control inventory includes exactly one typed custody choice" {
  let units = closed_values_initial_control_units(
    empty_family_module_containers,
  )
  // Prior241H/446R/292W plus custody1H/1R/1W, Local packet1H/5R/1W,
  // four containers8H/11R/8W, one recipe reference and one construction latch.
  // Three shared phase-state return packets add3H0R3W=72B; text/wire unchanged.
  assert_eq(units.record_headers, 254L)
  assert_eq(units.reference_slots, 464L)
  assert_eq(units.scalar_words, 306L)
  assert_eq(units.owned_utf16_units, 80L)
  assert_eq(units.owned_wire_bytes, 0L)
  assert_eq(@execution.preparation_representation_cost(units), Some(10384L))
}

///|
test "initial original reservation funds all module containers with selected backend count" {
  let policy = client_local_resource_policy()
  assert_true(@local.local_module_container_inventory(-1, 0) is None)
  assert_true(@local.local_module_container_inventory(1, -1) is None)
  for
    (providers, expected_containers, required) in [
      (0, 280L, 10384L),
      (9, 352L, 10456L),
    ] {
    let containers = @local.local_module_container_inventory(1, providers).unwrap()
    assert_eq(
      @execution.preparation_representation_cost(containers),
      Some(expected_containers),
    )
    let (retained, execution) = client_closed_values_initial_control_capacity(
      policy,
      module_containers=containers,
    ).unwrap()
    // Independent fixed controls10096 +recipe link8 +four arrays280/352.
    assert_eq(retained, required)
    for available in [required - 1L, required] {
      let ledger = @resources.create_ledger({
        ..client_local_preparation_initial_limits(policy).unwrap(),
        retained_bytes: available,
        execution_bytes: execution,
      }).unwrap()
      let input = [1]
      let reserved : Result[
        @resources.PreparationCapacity[Array[Int], Array[Int]],
        @resources.PreparationCapacityIssue,
      ] = @resources.reserve_preparation_capacity(
        ledger,
        input,
        retained,
        execution,
        max_borrowers=1,
      )
      if available < required {
        assert_true(reserved is Err(Resource(RetentionLimit)))
        assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
        assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      } else {
        let original = reserved.unwrap()
        assert_eq(
          @resources.preparation_capacity_accounting(original).0,
          required,
        )
        assert_eq(
          @resources.abort_preparation_capacity_after_cleanup(original, input),
          Ok(true),
        )
      }
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    }
  }
}

///|
test "initial module recipe validates each shared component before composing its fields" {
  let invalid = { ..empty_family_module_containers, record_headers: -1L, }
  assert_true(
    client_closed_values_initial_control_capacity(
      client_local_resource_policy(),
      module_containers=invalid,
    )
    is None,
  )
  let invalid = {
    ..empty_family_module_containers,
    owned_wire_bytes: 9223372036854775807L,
  }
  assert_true(
    client_closed_values_initial_control_capacity(
      client_local_resource_policy(),
      module_containers=invalid,
    )
    is None,
  )
}
