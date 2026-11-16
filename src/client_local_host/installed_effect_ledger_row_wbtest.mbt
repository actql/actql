///|
test "Ledger row classes retain finite policy bounds and price independent byte occurrences" {
  for kind in ["entry", "response", "receipt", "quantity"] {
    let base = installed_effect_ledger_row_workspace(kind, 1510, 64, 4, 65536).unwrap()
    assert_true(base > 0L)
    // Two current/new entry Strings (2 bytes per UTF16 unit) and one
    // original UTF8 conversion; no physical response is parsed as an Entry.
    assert_eq(
      installed_effect_ledger_row_workspace(kind, 1511, 64, 4, 65536).unwrap() -
      base,
      5L,
    )
    // Native row, materialized Buffer and collision-comparison Buffer are
    // three distinct receiver occurrences. The caller's body has its owner.
    assert_eq(
      installed_effect_ledger_row_workspace(kind, 1510, 64, 4, 65537).unwrap() -
      base,
      3L,
    )
    assert_true(
      installed_effect_ledger_row_workspace(kind, 1000000, 64, 4, 1000000)
      is Some(_),
    )
  }
  for kind in ["", "Entry", "history"] {
    assert_true(
      installed_effect_ledger_row_workspace(kind, 1510, 64, 4, 65536) is None,
    )
  }
  for
    (bytes, nodes, depth, response) in [
      (0, 64, 4, 65536),
      (1000001, 64, 4, 65536),
      (1510, 0, 4, 65536),
      (1510, 65, 4, 65536),
      (1510, 64, 0, 65536),
      (1510, 64, 5, 65536),
      (1510, 64, 4, 0),
      (1510, 64, 4, 1000001),
    ] {
    assert_true(
      installed_effect_ledger_row_workspace(
        "response", bytes, nodes, depth, response,
      )
      is None,
    )
  }
}

///|
test "Receipt quote distinguishes actual JSON nodes from punctuation inside immutable Strings" {
  let plain = "{\"result\":\"abcdef\",\"state\":\"applied\"}"
  let punctuation = "{\"result\":\"[,:{}]\",\"state\":\"applied\"}"
  let ascii = installed_effect_receipt_codec_capacity(plain, 512, 16, false).unwrap()
  let quoted = installed_effect_receipt_codec_capacity(
    punctuation, 512, 16, false,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(ascii),
    @execution.execution_capacity_retained_bytes(quoted),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(ascii),
    @execution.execution_capacity_execution_bytes(quoted),
  )
  // Same decoded shape, one additional UTF8 byte. The unchanged Receipt
  // family owns 3 decoded-text spans in R and another 6 wire spans in E.
  let unicode = installed_effect_receipt_codec_capacity(
    "{\"result\":\"ébcdef\",\"state\":\"applied\"}", 512, 16, false,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(unicode) -
    @execution.execution_capacity_retained_bytes(ascii),
    3L * 8L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(unicode) -
    @execution.execution_capacity_execution_bytes(ascii),
    (3L + 6L) * 8L,
  )
  // Equal wire lengths, but four more actual value nodes. This quotes DATA
  // construction only; neither input is being used as an admitted Receipt.
  let scalar = installed_effect_receipt_codec_capacity(
    "{\"result\":\"0000000\",\"state\":\"applied\"}", 512, 16, false,
  ).unwrap()
  let dense = installed_effect_receipt_codec_capacity(
    "{\"result\":[0,0,0,0],\"state\":\"applied\"}", 512, 16, false,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(dense) -
    @execution.execution_capacity_retained_bytes(scalar),
    4L * 4L * 256L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(dense) -
    @execution.execution_capacity_execution_bytes(scalar),
    4L * (4L + 6L) * 256L,
  )
}

///|
test "Receipt geometry remains a finite quote and does not admit malformed wire" {
  for receipt in [false, true] {
    let prefix = installed_effect_receipt_codec_capacity("{", 64, 4, receipt).unwrap()
    assert_true(@execution.execution_capacity_retained_bytes(prefix) > 0L)
    assert_true(
      @execution.execution_capacity_execution_bytes(prefix) >
      @execution.execution_capacity_retained_bytes(prefix),
    )
    // The existing preflight stops before grammar transitions. A geometry
    // result does not replace strict public Receipt parsing or its refusal.
    assert_true(
      @publication.admit_publication_contract(
        "effect_row_outcome_receipt", "{", 1000000, 64, 4,
      )
      is Err(@publication.InvalidWire),
    )
    for (nodes, depth) in [(0, 4), (4097, 4), (64, 0), (64, 33)] {
      assert_true(
        installed_effect_receipt_codec_capacity("{}", nodes, depth, receipt)
        is None,
      )
    }
    assert_true(
      installed_effect_receipt_codec_capacity("", 64, 4, receipt) is None,
    )
  }
}

///|
test "Ledger history quote covers each returned occurrence and rejects overflow" {
  let empty = installed_effect_ledger_history_workspace(0, 0L).unwrap()
  assert_true(empty > 0L) // The three Array owners exist even without rows.
  let one = installed_effect_ledger_history_workspace(1, 100L).unwrap()
  let two = installed_effect_ledger_history_workspace(2, 100L).unwrap()
  assert_true(two > one)
  // Three UTF16 backing occurrences and a worst-case 3-byte UTF8 encoding
  // coexist for every selected native String unit, including failed input.
  assert_eq(
    installed_effect_ledger_history_workspace(2, 101L).unwrap() - two,
    3L * 2L + 3L,
  )
  assert_true(
    installed_effect_ledger_history_workspace(100000, 1000000L) is Some(_),
  )
  for
    (count, units) in [
      (-1, 0L),
      (100001, 0L),
      (1, -1L),
      (1, 9223372036854775807L),
    ] {
    assert_true(installed_effect_ledger_history_workspace(count, units) is None)
  }
}

///|
#cfg(target="js")
test "Ledger row and nested Receipt keep same-original history peak until outer completion" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    wide_controls=true,
    current=() => calls.val += 1,
  )
  let control = owner.effect_operation_controls.unwrap()
  let token = control.reservation
  let idle = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_ledger_row(
      { ..owner, },
      prepared,
      request,
      plan,
      "receipt",
      1510,
      64,
      4,
      65536,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), idle)
  calls.val = 0
  begin_installed_effect_operation_ledger_row(
    owner, prepared, request, plan, "receipt", 1510, 64, 4, 65536,
  ).unwrap()
  assert_true(calls.val > 0)
  assert_true(physical_equal(token, control.reservation))
  let row = @resources.ledger_usage(ledger)
  assert_eq(row.reserved_retention_bytes, idle.reserved_retention_bytes)
  assert_true(
    begin_installed_effect_operation_ledger_row(
      owner, prepared, request, plan, "entry", 1510, 64, 4, 65536,
    )
    is Err(AlreadyBound),
  )
  grow_installed_effect_operation_ledger_history(
    owner, prepared, request, plan, 2, 1000000L,
  ).unwrap()
  let history = @resources.ledger_usage(ledger)
  assert_eq(history.reserved_retention_bytes, row.reserved_retention_bytes)
  assert_true(history.reserved_execution_bytes > row.reserved_execution_bytes)
  // Sequential private histories do not escape. Repeating a smaller/equal
  // read retains the same peak instead of cumulatively charging its bytes.
  grow_installed_effect_operation_ledger_history(
    owner, prepared, request, plan, 2, 1000000L,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), history)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    history.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
  let exhausted = @resources.ledger_usage(ledger)
  assert_true(
    grow_installed_effect_operation_ledger_history(
      owner, prepared, request, plan, 2, 2000000L,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), exhausted)
  assert_true(control.construction_active)
  assert_true(physical_equal(token, control.reservation))
  @resources.settle_capacity(ledger, pressure).unwrap()
  grow_installed_effect_operation_ledger_history(
    owner, prepared, request, plan, 2, 2000000L,
  ).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(grown.reserved_retention_bytes, history.reserved_retention_bytes)
  assert_true(grown.reserved_execution_bytes > history.reserved_execution_bytes)
  begin_installed_effect_operation_receipt_codec(
    owner, prepared, request, plan, "{\"result\":{},\"state\":\"applied\"}", 512,
    16, false,
  ).unwrap()
  let codec = @resources.ledger_usage(ledger)
  assert_true(codec.reserved_retention_bytes >= grown.reserved_retention_bytes)
  assert_true(codec.reserved_execution_bytes >= grown.reserved_execution_bytes)
  assert_true(
    complete_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(AlreadyBound),
  )
  check_installed_effect_managed_run(owner, prepared, request).unwrap()
  assert_eq(@resources.ledger_usage(ledger), codec)
  complete_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan,
  ).unwrap()
  let completed = @resources.ledger_usage(ledger)
  assert_eq(completed.reserved_retention_bytes, grown.reserved_retention_bytes)
  assert_eq(completed.reserved_execution_bytes, grown.reserved_execution_bytes)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let returned = @resources.ledger_usage(ledger)
  assert_eq(returned.reserved_retention_bytes, idle.reserved_retention_bytes)
  assert_eq(returned.reserved_execution_bytes, idle.reserved_execution_bytes)
  assert_eq(returned.attempts, idle.attempts)
  assert_eq(returned.transferred_bytes, idle.transferred_bytes)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
