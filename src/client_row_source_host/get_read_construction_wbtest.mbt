///|
test "portable GET construction keeps same original reservation before parse and detached page" {
  let limits = { ..get_read_test_limits(), max_bytes: 512, max_nodes: 64, }
  let raw = row_source_get_read_construction_capacity(limits).unwrap()
  let raw_r = @execution.execution_capacity_retained_bytes(raw)
  let raw_e = @execution.execution_capacity_execution_bytes(raw)
  let wire =
    #|{"method":"GET","path":"/v1/users","query":[["fixed","é東京"]],"pageSize":{"parameter":"size","limit":2},"versionHeader":{"name":"api-version","value":"2026-03-11"}}
  // This detached DATA-only read determines the independent finite profile
  // for the three ledgers below; no Host or physical reader is constructed.
  let measured = admit_row_source_get_read(
    @utf8.encode(wire),
    Some("after"),
    limits,
  ).unwrap()
  let page_quantity = row_source_get_page_construction_capacity(measured).unwrap()
  let total = @execution.add_execution_capacity(raw, page_quantity).unwrap()
  let r = @execution.execution_capacity_retained_bytes(total)
  let e = @execution.execution_capacity_execution_bytes(total)
  assert_true(r > raw_r && e > raw_e)
  for (r_short, e_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: r - r_short,
      execution_bytes: e - e_short,
    }).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, raw_r, raw_e).unwrap()
    let read = admit_row_source_get_read(
      @utf8.encode(wire),
      Some("after"),
      limits,
    ).unwrap()
    let page = row_source_get_page_construction_capacity(read).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(page),
      @execution.execution_capacity_retained_bytes(page_quantity),
    )
    let grown = @resources.grow_execution_reservation_capacity(
      ledger, original, r, e,
    )
    if r_short == 0L && e_short == 0L {
      grown.unwrap()
      let frame = row_source_get_page_frame(
        row_source_get_read_page(read, 3, 2, Some("")).unwrap(),
      ).unwrap()
      assert_eq(frame.2, [["fixed", "é東京"], ["size", "2"], ["after", ""]])
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
    } else {
      if r_short == 1L {
        assert_true(grown is Err(@resources.RetentionLimit))
      } else {
        assert_true(grown is Err(@resources.ExecutionLimit))
      }
      // Refusal retains the exact original parse debit. No page/frame was
      // allocated and no empty/new reservation is substituted for it.
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, raw_r)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, raw_e)
    }
    @resources.settle_reservation(ledger, original).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
}

///|
test "portable GET construction retains raw byte and invalid-prefix backing under original bounds" {
  let limits = { ..get_read_test_limits(), max_bytes: 512, max_nodes: 64, }
  let units = row_source_get_read_construction_inventory(limits).unwrap()
  let parser = relation_document_raw_construction_inventory({
    max_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_rows: 0,
  }).unwrap()
  // Exact original input+copy Bytes coexist, not a reused parser buffer.
  assert_eq(units.owned_wire_bytes, 1024L)
  assert_true(units.record_headers > parser.record_headers)
  assert_true(units.reference_slots > parser.reference_slots)
  assert_true(units.scalar_words > parser.scalar_words)
  for
    invalid in [
      { ..limits, max_bytes: 0, },
      { ..limits, max_nodes: 0, },
      { ..limits, max_depth: 0, },
      { ..limits, max_query_pairs: -1, },
      { ..limits, max_header_value_bytes: 0, },
    ] {
    assert_true(row_source_get_read_construction_capacity(invalid) is None)
  }
  let read = admit_row_source_get_read(
    @utf8.encode("{\"method\":\"GET\",\"path\":\"/x\"}"),
    None,
    limits,
  ).unwrap()
  let foreign = { ..read, origin: Ref(()), }
  assert_true(row_source_get_page_construction_capacity(foreign) is None)
}

///|
test "portable GET Reader composes one active request peak with same transport quantity" {
  let transport = @execution.execution_capacity(17L, 23L).unwrap()
  let pages = [
    @execution.execution_capacity(41L, 43L).unwrap(),
    @execution.execution_capacity(11L, 47L).unwrap(),
  ]
  let total = row_source_get_request_construction_capacity(transport, pages).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(total), 58L)
  assert_eq(@execution.execution_capacity_execution_bytes(total), 70L)
  assert_true(
    row_source_get_request_construction_capacity(transport, []) is None,
  )
  assert_true(
    row_source_get_request_construction_capacity(
      @execution.execution_capacity(9223372036854775807L, 9223372036854775807L).unwrap(),
      pages,
    )
    is None,
  )
  for (r, e) in [(58L, 70L), (57L, 70L), (58L, 69L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: r,
      execution_bytes: e,
    }).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, 17L, 23L).unwrap()
    let grown = @resources.grow_execution_reservation_capacity(
      ledger, original, 58L, 70L,
    )
    if r == 58L && e == 70L {
      grown.unwrap()
    } else {
      assert_true(grown is Err(_))
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 17L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 23L)
    }
    @resources.settle_reservation(ledger, original).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}
