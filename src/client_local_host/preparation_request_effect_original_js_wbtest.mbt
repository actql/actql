///|
test "Effect original envelope reserves actual escaped DATA on the same checked Request and retires normally" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let material = "\"".repeat(60000)
  let reads = Ref(0)
  let at = fn(index : Int) {
    reads.val += 1
    if index == 0 {
      material
    } else {
      "{\"installation\":\"fixture\"}"
    }
  }
  let expected = @publication_host.client_effect_target_original_envelope_capacity(
    2, at,
  ).unwrap()
  reads.val = 0
  reserve_request_effect_original_material(parent, input, prepared, 2, at).unwrap()
  assert_eq(reads.val, 2)
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(
    after.0 - before.0,
    @execution.execution_capacity_retained_bytes(expected),
  )
  assert_eq(
    after.1,
    Int64::max(
      before.1,
      before.0 + @execution.execution_capacity_execution_bytes(expected),
    ),
  )
  assert_true(after.0 - before.0 > material.length().to_int64())
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect original envelope refuses one-byte-short retained backing without spending prepaid execution twice" {
  for short in [false, true] {
    let (parent, input, prepared) = request_effect_compile_fixture()
    let holder = borrow_request_effect_plan_input(parent, input).unwrap()
    let capacity = parent.effect_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let at = fn(index : Int) {
      if index == 0 {
        "\"".repeat(60000)
      } else {
        "installation"
      }
    }
    let quote = @publication_host.client_effect_target_original_envelope_capacity(
      2, at,
    ).unwrap()
    let retained = @execution.execution_capacity_retained_bytes(quote)
    let execution = before.0 +
      @execution.execution_capacity_execution_bytes(quote)
    assert_true(execution > before.1)
    // Prepay the exact execution extent on the same Request reservation.
    @resources.reserve_working_preparation_phase(
      capacity,
      input,
      before.0,
      execution,
    ).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      (before.0, execution),
    )
    let limits = @resources.ledger_limits(parent.ledger)
    let prepaid = @resources.ledger_usage(parent.ledger)
    let block = @resources.reserve_capacity(
      parent.ledger,
      limits.retained_bytes -
      prepaid.held_bytes -
      prepaid.reserved_retention_bytes -
      retained +
      (if short { 1L } else { 0L }),
      limits.execution_bytes - prepaid.reserved_execution_bytes,
    ).unwrap()
    let funded = @resources.ledger_usage(parent.ledger)
    assert_eq(funded.reserved_execution_bytes, limits.execution_bytes)
    let result = reserve_request_effect_original_material(
      parent, input, prepared, 2, at,
    )
    let expected_retained = if short {
      assert_true(result is Err(Capacity(Resource(RetentionLimit))))
      before.0
    } else {
      result.unwrap()
      before.0 + retained
    }
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      (expected_retained, execution),
    )
    let after = @resources.ledger_usage(parent.ledger)
    assert_eq(after.reserved_execution_bytes, funded.reserved_execution_bytes)
    assert_eq(after.planning_work, funded.planning_work)
    assert_true(
      physical_equal(
        @resources.preparation_body_borrow_value(holder).unwrap(),
        prepared,
      ),
    )
    @resources.settle_capacity(parent.ledger, block).unwrap()
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Effect original envelope keeps current original reentry and policy refusals before conversion" {
  let live = Ref(true)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    live.val
  })
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let reads = Ref(0)
  let at = fn(_index : Int) {
    reads.val += 1
    "original"
  }
  assert_true(
    reserve_request_effect_original_material(parent, [1], prepared, 2, at)
    is Err(ForeignOriginal),
  )
  let (foreign_parent, _, foreign) = request_effect_compile_fixture()
  assert_true(
    reserve_request_effect_original_material(parent, input, foreign, 2, at)
    is Err(ForeignOriginal),
  )
  live.val = false
  assert_true(
    reserve_request_effect_original_material(parent, input, prepared, 2, at)
    is Err(Capacity(_)),
  )
  assert_eq(reads.val, 0)
  // A failed current observation fences this original; never revive it.
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  abort_request_preparation_after_cleanup(foreign_parent).unwrap()
  let (parent, input, prepared) = request_effect_compile_fixture()
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(
    reserve_request_effect_original_material(parent, input, prepared, 2, index => {
      if index == 0 {
        "a".repeat(262145)
      } else {
        "original"
      }
    })
    is Err(Policy),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  reserve_request_effect_original_material(parent, input, prepared, 2, index => {
    assert_true(
      reserve_request_effect_original_material(parent, input, prepared, 2, at)
      is Err(ForeignOriginal),
    ) catch {
      _ => abort("reentrant original was admitted")
    }
    if index == 0 {
      "original"
    } else {
      "installation"
    }
  }).unwrap()
  assert_eq(reads.val, 0)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
}
