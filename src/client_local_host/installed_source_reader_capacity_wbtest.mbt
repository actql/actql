///|
test "portable cursor reader replaces only cursor storage and retains shared growth backing" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let legacy = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  let cursor = installed_json_cursor_source_reader_capacity(limits, 2, 3).unwrap()
  // Two pages need at most one retained cursor. Its shared Map growth Owner
  // declares11H/29R/34W; progress fields/cursor Some add1H/4R/8W, reusing
  // the fixed protocol-state header. The old cursor Set's4R/2W and one of
  // its two5-unit Strings disappear. Identity Set and physical frames stay.
  // Independent delta:12H+29R+40W-5UTF16 =734 logical bytes. One synchronous
  // Result adds1H/1R/2W=40 execution bytes, not another retained page.
  assert_eq(@execution.execution_capacity_retained_bytes(legacy), 3632L)
  assert_eq(@execution.execution_capacity_retained_bytes(cursor), 4366L)
  assert_eq(
    @execution.execution_capacity_execution_bytes(cursor) -
    @execution.execution_capacity_execution_bytes(legacy),
    774L,
  )
  assert_true(installed_json_cursor_source_reader_capacity([], 2, 3) is None)
  assert_true(installed_source_cursor_progress_inventory(0L) is None)
  assert_true(
    installed_source_cursor_progress_inventory(9223372036854775807L) is None,
  )
}

///|
test "portable cursor reader same recipe admits exact backing and refuses either one-short dimension" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let quote = installed_json_cursor_source_reader_capacity(limits, 2, 3).unwrap()
  let retention = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  for (r_short, e_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retention - r_short,
      execution_bytes: execution - e_short,
    }).unwrap()
    let result = @resources.reserve_attempt(ledger, 0L, retention, execution)
    if r_short == 0L && e_short == 0L {
      let original = result.unwrap()
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retention,
      )
      @resources.settle_reservation(ledger, original).unwrap()
    } else if r_short == 1L {
      assert_true(result is Err(@resources.RetentionLimit))
    } else {
      assert_true(result is Err(@resources.ExecutionLimit))
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "cursor request composition keeps the original request on both funded axes" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let reader = installed_json_cursor_source_reader_capacity(limits, 2, 3).unwrap()
  // Independent selected GET inventory: two dynamic query pairs, two header
  // pairs, /v1/users, unchanged4096 query ceiling. Source snapshot is separate.
  let request = installed_source_construction_capacity(
    38L, 8232L, 0L, 72L, 49212L, 0L,
  ).unwrap()
  let combined = installed_json_cursor_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  let retention = @execution.execution_capacity_retained_bytes(combined)
  let execution = @execution.execution_capacity_execution_bytes(combined)
  assert_eq(
    retention,
    @execution.execution_capacity_retained_bytes(reader) +
    @execution.execution_capacity_retained_bytes(request),
  )
  assert_eq(
    execution,
    @execution.execution_capacity_execution_bytes(reader) +
    @execution.execution_capacity_execution_bytes(request),
  )
  for (r_short, e_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retention - r_short,
      execution_bytes: execution - e_short,
    }).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, retention, execution)
    if r_short == 0L && e_short == 0L {
      @resources.settle_reservation(ledger, original.unwrap()).unwrap()
    } else if r_short == 1L {
      assert_true(original is Err(@resources.RetentionLimit))
    } else {
      assert_true(original is Err(@resources.ExecutionLimit))
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
  assert_true(
    installed_json_cursor_source_reader_capacity_with_request(
      limits,
      2,
      3,
      None,
    )
    is None,
  )
  let overflow = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    installed_json_cursor_source_reader_capacity_with_request(
      limits,
      2,
      3,
      Some(overflow),
    )
    is None,
  )
}

///|
test "codec identity reader funds complete map growth on the same original backing" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let request = installed_source_construction_capacity(
    38L, 8232L, 0L, 72L, 49212L, 0L,
  ).unwrap()
  let plain = installed_json_cursor_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  let selected = installed_json_identity_cursor_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  let retention = @execution.execution_capacity_retained_bytes(selected)
  let execution = @execution.execution_capacity_execution_bytes(selected)
  // Three IDs: map19H/51R/60W plus the new record fields and capture2H/8R/1W,
  // minus the replaced entries6R/3W. Existing UTF16 and request amounts stay.
  // The identity call adds2H/8R/2W to the concurrent execution inventory.
  assert_eq(
    retention - @execution.execution_capacity_retained_bytes(plain),
    1224L,
  )
  assert_eq(
    execution - @execution.execution_capacity_execution_bytes(plain),
    1336L,
  )
  for (r_short, e_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retention - r_short,
      execution_bytes: execution - e_short,
    }).unwrap()
    let result = @resources.reserve_attempt(ledger, 0L, retention, execution)
    if r_short == 1L {
      assert_true(result is Err(@resources.RetentionLimit))
    } else if e_short == 1L {
      assert_true(result is Err(@resources.ExecutionLimit))
    } else {
      @resources.settle_reservation(ledger, result.unwrap()).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
  assert_true(
    installed_json_identity_cursor_source_reader_capacity_with_request(
      limits,
      2,
      3,
      None,
    )
    is None,
  )
}

///|
test "JSON Source reader inventory uses shared tariff and separate retained workspace" {
  // Independent authored inventory vector; no returned quote supplies any
  // expected amount, Ledger limit, admission or physical cleanup receipt.
  assert_eq(installed_source_reader_policy(), [65536, 100000, 100])
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  // The reader retains its original sequence retirement method/state plus
  // two native callbacks (2H/4R=64B). The complete simultaneous native
  // handoff/typed-call controls are 7H/14R/11W=312B, never another payload.
  // The one selected-native flag adds one retained word. Captured credential
  // current pairs + bound Site methods + factory/reader slots add 2H/13R=136B;
  // private borrow handoff adds three workspace references=24B. The same
  // response-growth closure now captures its pre-allocation method (1R=8B).
  let capacity = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 3632L)
  // Independent Host vector: 27 headers, 102 references, 23 words,
  // 51 UTF16 units and 14 wire bytes. The 20 checked-value slots are
  // separate from the original Source parser/key workspace. Consume that
  // owner's quote instead of keeping a second frozen NFC/Source aggregate.
  let host = @execution.preparation_representation_cost({
    record_headers: 27L,
    reference_slots: 102L,
    scalar_words: 23L,
    owned_utf16_units: 51L,
    owned_wire_bytes: 14L,
  }).unwrap()
  assert_eq(host, 1548L)
  let response = @execution.preparation_representation_cost(
    installed_source_response_workspace(4, 3, 4).unwrap(),
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity),
    3632L + host + 20L * @execution.execution_capacity_node_bytes() + response,
  )
  assert_true(installed_json_source_reader_capacity([], 2, 3) is None)
  assert_true(installed_json_source_reader_capacity(limits, 0, 3) is None)
  assert_true(installed_json_source_reader_capacity(limits, 2, 0) is None)
  let invalid = limits.copy()
  invalid[3] = 0
  assert_true(installed_json_source_reader_capacity(invalid, 2, 3) is None)
  let overflow = Array::make(16, 2147483647)
  assert_true(
    installed_json_source_reader_capacity(overflow, 2147483647, 2147483647)
    is None,
  )
}

///|
test "Slack original prefix composes retained scalar composite and protocol inventories" {
  let limits = [4, 6, 3, 4, 2, 3, 3, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let capacity = installed_slack_source_reader_capacity(limits, 11, 3, 2).unwrap()
  let json = installed_json_source_reader_capacity(limits, 11, 3).unwrap()
  // Independent vector: 183 headers, 700 refs, 258 words, 1122 UTF16 units,
  // 45 checked nodes. Workspace: 21 headers, 163 refs, 28 words, 370 UTF16.
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity) -
    @execution.execution_capacity_retained_bytes(json),
    24356L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity) -
    @execution.execution_capacity_execution_bytes(json),
    26962L,
  )
  assert_true(installed_slack_source_reader_capacity(limits, 8, 3, 2) is None)
  assert_true(installed_slack_source_reader_capacity(limits, 11, 3, 1) is None)
  assert_true(installed_slack_source_reader_capacity(limits, 11, 0, 2) is None)
  assert_true(
    installed_slack_source_reader_capacity(
      Array::make(16, 2147483647),
      11,
      2147483647,
      2147483646,
    )
    is None,
  )
}

///|
test "Gmail sequence retains the complete original list get prefix alongside JSON workspace" {
  let limits = [4, 6, 3, 4, 1, 3, 5, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let capacity = installed_gmail_thread_reader_capacity(limits, 5, 3, 2, 12).unwrap()
  // Independently authored tariff totals for this fixed inventory, including
  // all six retained checked-value nodes and the one original request DTO.
  let json = installed_json_source_reader_capacity(limits, 5, 3).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity) -
    @execution.execution_capacity_retained_bytes(json),
    4468L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity) -
    @execution.execution_capacity_execution_bytes(json),
    5556L,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 4, 3, 2, 12) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 5, 3, 3, 12) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(limits, 5, 3, 2, 0) is None,
  )
  assert_true(
    installed_gmail_thread_reader_capacity(
      Array::make(16, 2147483647),
      5,
      3,
      2,
      12,
    )
    is None,
  )
}

///|
test "preserving decoder owner retains the installed original structural inventory" {
  for (bytes, nodes, depth) in [(1, 1, 1), (256, 16, 4), (300000, 100000, 32)] {
    let original = installed_source_response_preserving_workspace(
      bytes, nodes, depth,
    ).unwrap()
    let literal = @source.json_literal_construction_extent(bytes, nodes, depth).unwrap()
    // Source already owns the active key-map peak. The preserving parser adds
    // only its decoded input String/wrapper; indexed admission adds the three
    // separately retained endpoint families below, without replacing that map.
    let endpoints = [true, false].map(fn(objects) {
      let inventory = closed_values_source_inventories({
        input_bytes: bytes,
        node_upper: nodes,
        fields_upper: nodes,
        objects: if objects {
          nodes
        } else {
          0
        },
        arrays: if objects {
          0
        } else {
          nodes
        },
        quoted_tokens: 0,
        quoted_utf16_units: 0,
        longest_quoted_utf16: 0,
        longest_atom_utf16: 0,
        depth_upper: Int::min(nodes, depth),
      })
      @execution.compose_preparation_representation([
        inventory.indexed_additional,
        inventory.decoder_ancestry_peak,
        inventory.decoder_controls_peak,
      ]).unwrap()
    })
    assert_eq(
      original.record_headers,
      literal.record_headers +
      Int64::max(endpoints[0].record_headers, endpoints[1].record_headers) +
      1L,
    )
    assert_eq(
      original.reference_slots,
      literal.reference_slots +
      Int64::max(endpoints[0].reference_slots, endpoints[1].reference_slots),
    )
    assert_eq(
      original.scalar_words,
      literal.scalar_words +
      Int64::max(endpoints[0].scalar_words, endpoints[1].scalar_words),
    )
    assert_eq(
      original.owned_utf16_units,
      literal.owned_utf16_units + bytes.to_int64(),
    )
    assert_eq(original.owned_wire_bytes, 0L)
  }
  for
    (bytes, nodes, depth) in [(0, 16, 4), (256, 0, 4), (256, 16, 0), (-1, 1, 1)] {
    assert_true(
      installed_source_response_preserving_workspace(bytes, nodes, depth)
      is None,
    )
  }
}

///|
test "native typed Source composes only shared Reader controls with its original codec" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let codec = @execution.execution_capacity(17L, 23L).unwrap()
  let capacity = installed_native_source_reader_capacity(
    limits,
    2,
    3,
    Some(codec),
  ).unwrap()
  // The independent generic retained vector3632 includes row-id/cursor
  // tracking: (3+2)*(2R+1W) + (3*7+2*5)U = 182B. This native Reader
  // never constructs that generic tracking state; its codec owns its cursor.
  // The remaining shared retained vector is3450. Native shared controls are
  // 27H/101R/23W=1424B, target8U=16B and one physical response4B.
  // The codec alone owns its actual parser/typed projection; no row wire or
  // generic raw JSON decoder is allocated or priced by this alternative.
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 3467L)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 4925L)
  let spelling = limits.copy()
  spelling[8] = 5000
  spelling[9] = 7000
  let same = installed_native_source_reader_capacity(
    spelling,
    2,
    3,
    Some(codec),
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(same),
    @execution.execution_capacity_retained_bytes(capacity),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(same),
    @execution.execution_capacity_execution_bytes(capacity),
  )
  // The JSON reader still owns its actual row-id/cursor tracking, and both
  // alternatives retain every charged raw response, including a failed body.
  assert_true(
    @execution.execution_capacity_retained_bytes(
      installed_json_source_reader_capacity(spelling, 2, 3).unwrap(),
    ) >
    @execution.execution_capacity_retained_bytes(
      installed_json_source_reader_capacity(limits, 2, 3).unwrap(),
    ),
  )
  let body = limits.copy()
  body[1] = 7
  assert_eq(
    @execution.execution_capacity_retained_bytes(
      installed_native_source_reader_capacity(body, 2, 3, Some(codec)).unwrap(),
    ),
    3468L,
  )
  assert_true(
    installed_native_source_reader_capacity(limits, 2, 3, None) is None,
  )
  assert_true(
    installed_native_source_reader_capacity([], 2, 3, Some(codec)) is None,
  )
}
