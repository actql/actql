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
    let all_keys = @shape.key_admission_construction_extent(nodes, nodes).unwrap()
    let active_keys = @shape.key_admission_construction_extent(
      Int::min(nodes, depth),
      nodes,
    ).unwrap()
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
      literal.record_headers -
      all_keys.record_headers +
      Int64::max(endpoints[0].record_headers, endpoints[1].record_headers) +
      active_keys.record_headers +
      1L,
    )
    assert_eq(
      original.reference_slots,
      literal.reference_slots -
      all_keys.reference_slots +
      Int64::max(endpoints[0].reference_slots, endpoints[1].reference_slots) +
      active_keys.reference_slots,
    )
    assert_eq(
      original.scalar_words,
      literal.scalar_words -
      all_keys.scalar_words +
      Int64::max(endpoints[0].scalar_words, endpoints[1].scalar_words) +
      active_keys.scalar_words,
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
