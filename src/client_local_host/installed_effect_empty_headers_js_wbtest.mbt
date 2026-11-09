///|
fn empty_header_input_extent(
  full : @execution.ExecutionCapacity,
  header_limit : Int,
  discarded? : @execution.ExecutionCapacity? = None,
) -> ClientInstalledEffectOperationExtent {
  let original = prepare_installed_effect_operation_extent(
    "send", full, 7L, true,
  ).unwrap()
  let original = match discarded {
    None => original
    Some(remaining) =>
      prepare_installed_effect_discarded_projection_extent(original, remaining).unwrap()
  }
  prepare_installed_effect_empty_response_headers_extent(original, header_limit).unwrap()
}

///|
fn empty_header_test_capacity() -> @execution.ExecutionCapacity {
  @execution.add_execution_capacity(
    installed_effect_http_response_construction_capacity(
      64,
      32,
      response_read_quantum=16,
    ).unwrap(),
    @execution.execution_capacity(128L, 384L).unwrap(),
  ).unwrap()
}

///|
test "explicit empty headers keep full failed peak then SAME token retains body native output and pending cleanup" {
  let full = empty_header_test_capacity()
  let r = @execution.execution_capacity_retained_bytes(full)
  let e = @execution.execution_capacity_execution_bytes(full)
  // Independent existing collection/tariff units:32 possible pair Arrays,
  // their references/words and20H String units. The outer Array stays live.
  let returned = @execution.preparation_representation_cost({
    record_headers: 96L,
    reference_slots: 704L,
    scalar_words: 64L,
    owned_utf16_units: 640L,
    owned_wire_bytes: 0L,
  }).unwrap()
  for discard in [false, true] {
    let remaining = if discard {
      Some(@execution.execution_capacity(r - 64L, e - 64L).unwrap())
    } else {
      None
    }
    let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
      physical_initial=Some(full),
      projection_retained=remaining,
      empty_header_limit=Some(32),
      parent_limit=Some(536870912L),
    )
    let child = borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "send",
    ).unwrap()
    start_installed_effect_operation(child).unwrap()
    let before = @resources.ledger_usage(ledger)
    let input = empty_header_input_extent(full, 32, discarded=remaining)
    assert_true(
      begin_installed_effect_operation_input(child, input)
      is Err(ForeignOriginal),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(
      require_installed_effect_operation_response_headers(child, ["etag"], 32)
      is Err(ForeignOriginal),
    )
    assert_true(
      require_installed_effect_operation_response_headers(child, [], 33)
      is Err(ForeignOriginal),
    )
    require_installed_effect_operation_response_headers(child, [], 32).unwrap()
    begin_installed_effect_operation_input(child, input).unwrap()
    guard child.backing
      is Some(@resources.NodeManagedRunOperationBacking::Physical(token)) else {
      fail("missing same physical token")
    }
    @resources.charge_transfer(ledger, token, 2L).unwrap()
    @resources.mark_cleanup_pending(ledger, token).unwrap()
    let before = @resources.ledger_usage(ledger)
    assert_eq(
      @resources.reservation_capacity_amounts(ledger, token).unwrap(),
      (r, e),
    )
    // Failed/pending consumers never call completion; their full peak remains.
    assert_true(retire_installed_effect_operation(child, false) is Ok(false))
    assert_eq(@resources.ledger_usage(ledger), before)
    if discard {
      complete_installed_effect_discarded_response_projection(child).unwrap()
    } else {
      complete_installed_effect_operation_response_projection(child).unwrap()
    }
    let retained = r - returned - (if discard { 64L } else { 0L })
    assert_eq(
      @resources.reservation_capacity_amounts(ledger, token).unwrap(),
      (retained, retained),
    )
    let completed = @resources.ledger_usage(ledger)
    assert_eq(completed, {
      ..before,
      reserved_retention_bytes: before.reserved_retention_bytes - r + retained,
      reserved_execution_bytes: before.reserved_execution_bytes - e + retained,
    })
    assert_true(@resources.reservation_open(token))
    assert_true(@resources.reservation_pending(token))
    if discard {
      complete_installed_effect_discarded_response_projection(child).unwrap()
    } else {
      complete_installed_effect_operation_response_projection(child).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger), completed)
    assert_true(retire_installed_effect_operation(child, true).unwrap())
    retire_installed_managed_run(owner).unwrap()
  }
}

///|
test "unspecified header selections keep full legacy bound for empty and nonempty names" {
  let full = empty_header_test_capacity()
  for names in [[], ["etag"]] {
    let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
      physical_initial=Some(full),
    )
    let child = borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "send",
    ).unwrap()
    start_installed_effect_operation(child).unwrap()
    require_installed_effect_operation_response_headers(child, names, 32).unwrap()
    begin_installed_effect_operation_input(
      child,
      prepare_installed_effect_operation_extent("send", full, 7L, true).unwrap(),
    ).unwrap()
    complete_installed_effect_operation_response_projection(child).unwrap()
    guard child.backing
      is Some(@resources.NodeManagedRunOperationBacking::Physical(token)) else {
      fail("missing legacy original")
    }
    let r = @execution.execution_capacity_retained_bytes(full)
    assert_eq(
      @resources.reservation_capacity_amounts(ledger, token).unwrap(),
      (r, r),
    )
    assert_true(retire_installed_effect_operation(child, true).unwrap())
    retire_installed_managed_run(owner).unwrap()
  }
}

///|
test "empty header contract cannot change at staged input and full input growth still refuses one byte short" {
  let full = empty_header_test_capacity()
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(full),
    empty_header_limit=Some(32),
    parent_limit=Some(536870912L),
  )
  assert_true(
    prepare_installed_effect_staged_extent(
      empty_header_input_extent(full, 32),
      empty_header_input_extent(full, 31),
    )
    is Err(Unsupported),
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  require_installed_effect_operation_response_headers(child, [], 32).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_input(
      child,
      empty_header_input_extent(full, 31),
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let larger = @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(full) + 1L,
    @execution.execution_capacity_execution_bytes(full) + 100L,
  ).unwrap()
  let free = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, free - 99L).unwrap()
  let pressured = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_input(
      child,
      empty_header_input_extent(larger, 32),
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), pressured)
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_input(
    child,
    empty_header_input_extent(larger, 32),
  ).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "empty header binding and successful return preserve original current reentry and foreign failures" {
  let full = empty_header_test_capacity()
  for completing in [false, true] {
    for mode in [1, 2, 3] {
      let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
      let armed = Ref(0)
      let reentry = Ref(false)
      let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
        physical_initial=Some(full),
        empty_header_limit=Some(32),
        current=() => {
          if armed.val == 1 {
            capture_recovery_current_refusal()
          }
          if armed.val == 2 {
            selected.val.unwrap().retired = true
          }
          if armed.val == 3 {
            reentry.val = require_installed_effect_operation_response_headers(
                selected.val.unwrap(),
                [],
                32,
              )
              is Err(AlreadyBound)
          }
        },
      )
      let child = borrow_installed_effect_operation(
        owner, prepared, request, plan, 0, true, 0, 0, "send",
      ).unwrap()
      selected.val = Some(child)
      start_installed_effect_operation(child).unwrap()
      let foreign = { ..child, original: None, }
      assert_true(
        require_installed_effect_operation_response_headers(foreign, [], 32)
        is Err(ForeignOriginal),
      )
      if completing {
        require_installed_effect_operation_response_headers(child, [], 32).unwrap()
        begin_installed_effect_operation_input(
          child,
          empty_header_input_extent(full, 32),
        ).unwrap()
      }
      let before = @resources.ledger_usage(ledger)
      armed.val = mode
      let result = if completing {
        complete_installed_effect_operation_response_projection(child)
      } else {
        require_installed_effect_operation_response_headers(child, [], 32)
      }
      if mode == 3 {
        assert_true(result is Ok(_))
        assert_true(reentry.val)
      } else {
        assert_true(result is Err(_))
        assert_eq(@resources.ledger_usage(ledger), before)
      }
      armed.val = 0
      child.retired = false
      assert_true(retire_installed_effect_operation(child, true).unwrap())
      retire_installed_managed_run(owner).unwrap()
    }
  }
}
