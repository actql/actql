///|
test "closed Values initial recipe has one owned control tariff and combined exact scanner boundary" {
  let policy = client_local_resource_policy()
  let (retained, execution) = client_closed_values_initial_control_capacity(
    policy,
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
      closed_values_initial_control_units(),
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
  let units = closed_values_initial_control_units()
  // Independent constructor inventory: prior 241H/446R/292W plus the one
  // retained closed custody wrapper 1H/1R/1W and prepared Local packet
  // 1H/5R/1W. The two exact one-slot selection containers and their module
  // references add4H/6R/4W. Text and wire are unchanged.
  assert_eq(units.record_headers, 247L)
  assert_eq(units.reference_slots, 458L)
  assert_eq(units.scalar_words, 298L)
  assert_eq(units.owned_utf16_units, 80L)
  assert_eq(units.owned_wire_bytes, 0L)
  assert_eq(@execution.preparation_representation_cost(units), Some(10160L))
}

///|
test "initial original reservation funds retained slot containers before any module allocation" {
  let policy = client_local_resource_policy()
  let (retained, execution) = client_closed_values_initial_control_capacity(
    policy,
  ).unwrap()
  // Independent representation inventory: four headers, six references and
  // four scalar length/capacity words for two exact one-slot arrays.
  let slots = @local.local_module_selection_container_inventory(1).unwrap()
  assert_eq(
    (slots.record_headers, slots.reference_slots, slots.scalar_words),
    (4L, 6L, 4L),
  )
  assert_eq(@execution.preparation_representation_cost(slots), Some(144L))
  assert_true(@local.local_module_selection_container_inventory(-1) is None)
  let two = @local.local_module_selection_container_inventory(2).unwrap()
  assert_eq(@execution.preparation_representation_cost(two), Some(160L))
  // This is independently fixed by the constructor inventory above:
  // prior10016 + two arrays144; it must not derive from the product quote.
  let required = 10160L
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
        retained,
      )
      assert_eq(
        @resources.abort_preparation_capacity_after_cleanup(original, input),
        Ok(true),
      )
    }
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  }
}
