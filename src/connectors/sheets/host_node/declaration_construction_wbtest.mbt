///|
test "range and clear native constructor quote composes onto original Source without issuing a declaration" {
  let original = @execution.execution_capacity(11L, 13L).unwrap()
  let native = sheets_range_declaration_construction_capacity(
    100, 1, 90, 6, 2000,
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(native) > 0L)
  let combined = @client_host.compose_installed_source_construction_capacity(
    original,
    [native],
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(native)
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 11L + peak)
  assert_eq(@execution.execution_capacity_execution_bytes(combined), 13L + peak)
  assert_true(
    sheets_range_declaration_construction_capacity(100, 0, 90, 6, 2000) is None,
  )
  assert_true(
    sheets_range_declaration_construction_capacity(100, 1, 90, 6, 0) is None,
  )
}

///|
test "range Source Reference constructor keeps a distinct Source lifetime from its Reader alternatives" {
  let source = sheets_range_reference_construction_capacity(32, 4).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(source) > 0L)
  let grid = sheets_grid_read_construction_capacity(100, 1, 0, 0, 1, 0, 1).unwrap()
  let reader = sheets_range_read_construction_capacity(
    100, 1, 0, 0, 1, 0, 1, 200000, 32,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(reader) >=
    @execution.execution_capacity_execution_bytes(grid),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(reader) >=
    @execution.execution_capacity_retained_bytes(grid),
  )
  let original = @execution.execution_capacity(11L, 13L).unwrap()
  let joined = @client_host.compose_installed_source_construction_capacity(
    original,
    [source],
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(joined),
    11L + @execution.execution_capacity_execution_bytes(source),
  )
  assert_true(sheets_range_reference_construction_capacity(0, 4) is None)
  assert_true(
    sheets_range_read_construction_capacity(100, 1, 0, 0, 1, 0, 1, 0, 32)
    is None,
  )
}

///|
test "range and clear driver profiles retain original binding constructor and independent capture peaks" {
  let configuration = "{\"origin\":\"https://sheets.example.test\",\"spreadsheetId\":\"book\",\"range\":{\"sheetId\":7,\"startRow\":2,\"endRow\":4,\"startColumn\":1,\"endColumn\":3},\"columns\":[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]}"
  let cid = "sha256:" + "b".repeat(64)
  let limits : @catalog.Limits = {
    max_bytes: 300000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let target = @catalog.range_reference(
      "https://sheets.example.test",
      "book",
      { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 3, },
      "sha256:" + "a".repeat(64),
      cid,
      limits,
    )
    .unwrap()
    .stringify()
  let binding = @catalog.admit_range_binding(
    configuration, "sha256:e3b7d39898d2037cffd055b1c51f24c66e616d2bb8ae3d4a34529515c26196ab",
    cid, target, limits,
  ).unwrap()
  let clear = @catalog.admit_clear_range_binding(
    configuration, "sha256:e3b7d39898d2037cffd055b1c51f24c66e616d2bb8ae3d4a34529515c26196ab",
    cid, target, limits,
  ).unwrap()
  let profiles = [
    sheets_range_construction_profile(
      binding, 100000, 10000, 16, 1000000, 200000, 32,
    ).unwrap(),
    sheets_clear_construction_profile(
      clear, 100000, 10000, 16, 1000000, 200000, 32,
    ).unwrap(),
  ]
  let captures = [
    sheets_range_capture_construction_profile(
      binding, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32,
    ).unwrap(),
    sheets_clear_capture_construction_profile(
      clear, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32,
    ).unwrap(),
  ]
  for index in 0..<2 {
    assert_eq(profiles[index].length(), 2)
    assert_eq(captures[index].length(), 3)
    assert_true(profiles[index][0].1 is None)
    assert_true(profiles[index][0].2 is Some(_))
    // This native output is the original closed request facts, not an
    // arbitrary forest at the unrelated incoming parser's node ceiling.
    assert_true(profiles[index][0].2.unwrap().max_nodes < limits.max_nodes)
    assert_true(
      @execution.execution_capacity_execution_bytes(profiles[index][0].0) > 0L,
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(captures[index][0]) > 0L,
    )
    // The actual Core composer adds Host projection once to the fresh row.
    // Direct recovery must cover that SAME complete constructor, plus its
    // retained outer/inner request array slots; never a physical send grant.
    let complete = @client_host.installed_standard_create_constructor_capacities(
        Some(profiles[index]),
      ).unwrap()[0]
    assert_eq(
      @execution.execution_capacity_execution_bytes(captures[index][1]),
      @execution.execution_capacity_execution_bytes(complete) + 96L,
    )
    assert_eq(
      @execution.execution_capacity_retained_bytes(captures[index][1]),
      @execution.execution_capacity_retained_bytes(complete) + 96L,
    )
  }
  // Validate actual native emitted bytes, including escaped/Unicode cells,
  // with the SAME output geometry supplied to the real Core Host composer.
  let value : Json = {
    "rows": [
      { "text": "é\n\"", "flag": true },
      { "text": "😀", "flag": false },
    ],
  }
  let rejected : Json = {
    "rows": [
      { "text": "original", "flag": true },
      { "text": "original", "flag": Json::null() },
    ],
  }
  assert_true(
    @catalog.prepare_range_request(binding, rejected.stringify(), target)
    is Err(_),
  )
  let request = @catalog.prepare_range_request(
    binding,
    value.stringify(),
    target,
  ).unwrap()
  let clear_request = @catalog.prepare_clear_range_request(
    clear, "{}", target, "00000000-0000-4000-8000-000000000000",
  ).unwrap()
  let wires = [
    @catalog.range_request_json(binding, request).unwrap(),
    @catalog.clear_range_request_json(clear, clear_request).unwrap(),
  ]
  for index, wire in wires {
    assert_true(
      @source.parse_json_bytes_preserving(
        @utf8.encode(wire),
        profiles[index][0].2.unwrap(),
      )
      is Ok(_),
    )
  }
  assert_true(
    sheets_range_construction_profile(
      binding, 0, 10000, 16, 1000000, 200000, 32,
    )
    is None,
  )
  assert_true(
    sheets_clear_capture_construction_profile(
      clear, 0, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32,
    )
    is None,
  )
  assert_true(
    sheets_range_installation_construction_capacity(
      configuration.length(),
      2,
      27,
      4,
    )
    is Some(_),
  )
  assert_true(
    sheets_range_installation_construction_capacity(
      configuration.length(),
      0,
      27,
      4,
    )
    is None,
  )
}

///|
test "two original Command declarations fit their unchanged observed Source quota without normalizing output as input" {
  let columns : Array[Json] = [
    { "name": "text", "type": "string", "nullable": false },
    { "name": "number", "type": "number", "nullable": true },
    { "name": "flag", "type": "boolean", "nullable": true },
  ]
  let range : Json = {
    "sheetId": 7,
    "startRow": 2,
    "endRow": 4,
    "startColumn": 0,
    "endColumn": 3,
  }
  let native = sheets_range_declaration_construction_capacity(
    @utf8.encode(columns.to_json().stringify()).length(),
    3,
    @utf8.encode(range.stringify()).length(),
    10,
    15870,
  ).unwrap()
  // Scalar quantity-only observation at the genuine 5bee before-call seam:
  // the original Source and Effect each retain their own Command constructor;
  // the common representation prefix and other original provider quantities
  // remain co-live. These counts issue no declaration, permission or ACK.
  let original = @execution.execution_capacity(
    134291688L + 668286L + 36792546L,
    134291688L + 668286L + 36792546L,
  ).unwrap()
  let quote = @client_host.compose_installed_source_construction_capacity(
    original,
    [native, native],
  ).unwrap()
  let quota = 536870912L
  assert_true(
    @execution.execution_capacity_retained_bytes(quote) <= quota,
    msg=@execution.execution_capacity_retained_bytes(quote).to_string(),
  )
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: quota,
    execution_bytes: quota,
  }).unwrap()
  let reservation = @resources.reserve_capacity(
    ledger,
    @execution.execution_capacity_retained_bytes(quote),
    @execution.execution_capacity_execution_bytes(quote),
  ).unwrap()
  @resources.settle_capacity(ledger, reservation).unwrap()
}

///|
test "closed Command output retains its Host forests separately from native temporary work" {
  let quantity = sheets_range_declaration_construction_capacity(
    147, 3, 79, 10, 15870,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quantity)
  let peak = @execution.execution_capacity_execution_bytes(quantity)
  assert_true(retained > 0L)
  assert_true(retained < peak)
  let selected = @client_host.retained_installed_source_construction_capacity(
    quantity,
  )
  assert_eq(@execution.execution_capacity_retained_bytes(selected), retained)
  assert_eq(@execution.execution_capacity_execution_bytes(selected), retained)
  let before = @client_host.compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [quantity],
  ).unwrap()
  let after = @client_host.compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [selected],
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(before), 11L + peak)
  assert_eq(@execution.execution_capacity_retained_bytes(after), 11L + retained)
}

///|
test "two original range request constructors do not reserve a nonexistent payload normalization" {
  // SAME existing installer body limits and original range schema. The two
  // native request occurrences alone must fit the unchanged Local ceiling;
  // this necessary condition is not full Plan or HTTP/Store admission.
  let metadata : @catalog.RangeConstructionMetadata = {
    columns: 3,
    rows: 2,
    name_units: 14L,
    schema_bytes: 147L,
    identity_units: 142L,
    origin_units: 32,
    spreadsheet_units: 4,
    target_units: 500,
    range: {
      sheet_id: 7,
      start_row: 2,
      end_row: 4,
      start_column: 0,
      end_column: 3,
    },
    limits: {
      max_bytes: 300000,
      max_nodes: 200000,
      max_depth: 32,
      max_cells: 6400,
    },
  }
  for clear in [false, true] {
    let original = sheets_range_request_capacity(
      metadata, 100000, 10000, 16, clear,
    ).unwrap()
    let pair = @execution.add_execution_capacity(original, original).unwrap()
    let admitted = @client_host.client_local_preparation_initial_limits(
      @client_host.client_local_resource_policy(),
    ).unwrap()
    assert_true(
      @execution.execution_capacity_retained_bytes(pair) <=
      admitted.retained_bytes,
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(pair) <=
      admitted.execution_bytes,
    )
  }
}

///|
test "range recovery does not normalize the whole encoded Preview forest" {
  let metadata : @catalog.RangeConstructionMetadata = {
    columns: 3,
    rows: 2,
    name_units: 14L,
    schema_bytes: 147L,
    identity_units: 142L,
    origin_units: 32,
    spreadsheet_units: 4,
    target_units: 500,
    range: {
      sheet_id: 7,
      start_row: 2,
      end_row: 4,
      start_column: 0,
      end_column: 3,
    },
    limits: {
      max_bytes: 100000,
      max_nodes: 200000,
      max_depth: 32,
      max_cells: 6400,
    },
  }
  let capture = sheets_range_capture_profile(
      metadata, 1000000, 100000, 64, 100000, 10000, 16, 100000, 200000, 32, false,
    ).unwrap()[0]
  // The whole encoded forest includes payload and JSON String escaping.
  // The original recovery entry is bounded before configuration NFC; only
  // that material enters normalization. Keep every other forest inventory.
  let forest = @canonical.nfc_lf_construction_extent(7004171).unwrap()
  let unrelated = sheets_constructor_capacity([
    {
      record_headers: forest.record_headers,
      reference_slots: forest.reference_slots,
      scalar_words: forest.scalar_words,
      owned_utf16_units: forest.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
  ]).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(capture) <
    @execution.execution_capacity_retained_bytes(unrelated),
    msg=@execution.execution_capacity_retained_bytes(capture).to_string(),
  )
}

///|
fn recovery_guard_test_metadata(
  bytes : Int,
) -> @catalog.RangeConstructionMetadata {
  {
    columns: 3,
    rows: 2,
    name_units: 14L,
    schema_bytes: 147L,
    identity_units: 142L,
    origin_units: 32,
    spreadsheet_units: 4,
    target_units: 500,
    range: {
      sheet_id: 7,
      start_row: 2,
      end_row: 4,
      start_column: 0,
      end_column: 3,
    },
    limits: {
      max_bytes: bytes,
      max_nodes: 200000,
      max_depth: 32,
      max_cells: 6400,
    },
  }
}

///|
fn recovery_guard_test_nfc(bytes : Int) -> @execution.ExecutionCapacity {
  let original = @canonical.nfc_lf_construction_extent(bytes).unwrap()
  sheets_constructor_capacity([
    {
      record_headers: original.record_headers,
      reference_slots: original.reference_slots,
      scalar_words: original.scalar_words,
      owned_utf16_units: original.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
  ]).unwrap()
}

///|
test "range recovery retains the independent saved-entry normalization floor" {
  assert_eq(
    sheets_range_capture_normalization_inputs(100000, 2000000, false),
    (100000, 100000),
  )
  assert_eq(
    sheets_range_capture_normalization_inputs(50000, 2000000, false),
    (50000, 100000),
  )
}

///|
test "range recovery keeps the larger original binding normalization guard" {
  assert_eq(
    sheets_range_capture_normalization_inputs(300000, 2000000, false),
    (300000, 100000),
  )
}

///|
test "clear recovery keeps its distinct original normalization envelope" {
  // The unchanged canonical(expected) guard precedes content NFC. Unlike
  // range's saved100000 guard, it uses the actual incoming recovery limits.
  assert_eq(
    sheets_range_capture_normalization_inputs(100000, 2000000, true),
    (100000, 2000000),
  )
}

///|
test "range native input decoders do not retain impossible container populations" {
  // Necessary lower slice of the actual range fixed quote: binding300000,
  // at least100000 nodes and depth32. No policy ceiling is changed here.
  let one = sheets_range_parsed_construction(300000, 100000, 32).unwrap()
  let normalized = recovery_guard_test_nfc(300000)
  let inputs = sheets_constructor_capacity([one, one]).unwrap()
  let slice = @execution.add_execution_capacity(inputs, normalized).unwrap()
  let original = @client_host.client_local_preparation_initial_limits(
    @client_host.client_local_resource_policy(),
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(slice) <=
    original.retained_bytes,
    msg=@execution.execution_capacity_retained_bytes(slice).to_string(),
  )
}

///|
test "range capture quotes the actual incoming recovery limits independently from outgoing binding" {
  let metadata = recovery_guard_test_metadata(300000)
  let narrow = sheets_range_capture_profile(
      metadata, 1000000, 100000, 64, 100000, 10000, 16, 100000, 100000, 32, false,
    ).unwrap()[0]
  let actual = sheets_range_capture_profile(
      metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, false,
    ).unwrap()[0]
  // Returned material is independent of the incoming decoder bound. The
  // constructor peak is a maximum of phases, not the previous sum of both
  // complete parser workspaces, so an additive delta is no longer its oracle.
  assert_eq(
    @execution.execution_capacity_retained_bytes(actual),
    @execution.execution_capacity_retained_bytes(narrow),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(actual) >
    @execution.execution_capacity_execution_bytes(narrow),
  )
  for
    (bytes, nodes, depth) in [
      (0, 200000, 32),
      (2000000, 0, 32),
      (2000000, 200000, 0),
    ] {
    assert_true(
      sheets_range_capture_profile(
        metadata, 1000000, 100000, 64, 100000, 10000, 16, bytes, nodes, depth, false,
      )
      is None,
    )
  }
}

///|
test "range acknowledgement does not construct a target metadata map for every response node" {
  let actual = sheets_range_response_capacity(2000000, 200000, 32).unwrap()
  let input = sheets_decoded_construction(2000000, 200000, 32).unwrap()
  let target = sheets_target_projection_construction(200000, 32).unwrap()
  let writer = sheets_writer_units(64, 3, 1).unwrap()
  let distinct_target = sheets_constructor_capacity([input, target, writer]).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(actual) <
    @execution.execution_capacity_execution_bytes(distinct_target),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(actual) <
    @execution.execution_capacity_execution_bytes(actual),
  )
}

///|
test "range capture keeps sequential parser and writer peaks out of its returned holding" {
  let actual = sheets_range_capture_profile(
      recovery_guard_test_metadata(300000),
      1000000,
      100000,
      64,
      100000,
      10000,
      16,
      2000000,
      200000,
      32,
      false,
    ).unwrap()[0]
  let retained = @execution.execution_capacity_retained_bytes(actual)
  let execution = @execution.execution_capacity_execution_bytes(actual)
  println("RANGE_CAPTURE retained=\{retained} execution=\{execution}")
  assert_true(retained < execution)
  let original = @client_host.client_local_preparation_initial_limits(
    @client_host.client_local_resource_policy(),
  ).unwrap()
  // A necessary native member slice, not the complete Compute/HTTP/Store Plan.
  assert_true(execution <= original.execution_bytes, msg=execution.to_string())
}

///|
test "clear capture normalization follows closed original metadata rather than unrelated incoming values" {
  let selected = sheets_range_capture_profile(
      recovery_guard_test_metadata(300000),
      1000000,
      100000,
      64,
      100000,
      10000,
      16,
      2000000,
      200000,
      32,
      true,
    ).unwrap()[0]
  let original = @client_host.client_local_preparation_initial_limits(
    @client_host.client_local_resource_policy(),
  ).unwrap()
  let execution = @execution.execution_capacity_execution_bytes(selected)
  println("CLEAR_CAPTURE_BASE execution=\{execution}")
  // Necessary native member slice; no full Plan/ordinary acceptance implied.
  assert_true(execution <= original.execution_bytes, msg=execution.to_string())
}

///|
test "range request retains its nominal request and Host facts without keeping parser and writer scratch" {
  let metadata = recovery_guard_test_metadata(300000)
  for clear in [false, true] {
    let original = sheets_range_request_capacity(
      metadata, 100000, 10000, 16, clear,
    ).unwrap()
    let retained = @execution.execution_capacity_retained_bytes(original)
    let execution = @execution.execution_capacity_execution_bytes(original)
    println(
      "REQUEST_RETURNED clear=\{clear} retained=\{retained} execution=\{execution}",
    )
    assert_true(retained > 0L)
    assert_true(retained < execution)
  }
}

///|
test "range returned holding follows the original closed rectangle while arbitrary failed input still grows the peak" {
  let metadata = recovery_guard_test_metadata(300000)
  for clear in [false, true] {
    let narrow = sheets_range_request_capacity(
      metadata, 100000, 10000, 16, clear,
    ).unwrap()
    let wide = sheets_range_request_capacity(metadata, 100000, 20000, 16, clear).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(wide),
      @execution.execution_capacity_retained_bytes(narrow),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(wide) >
      @execution.execution_capacity_execution_bytes(narrow),
    )
    let text = sheets_range_request_capacity(metadata, 200000, 10000, 16, clear).unwrap()
    if clear {
      // Only the empty value is admitted; arbitrary text grows failed-input
      // construction, not successful clear output or its retained request.
      assert_eq(
        @execution.execution_capacity_retained_bytes(text),
        @execution.execution_capacity_retained_bytes(narrow),
      )
    } else {
      // Both large inputs already meet the unchanged outgoing byte ceiling.
      // Successful output stays capped while failed-input construction grows.
      assert_eq(
        @execution.execution_capacity_retained_bytes(text),
        @execution.execution_capacity_retained_bytes(narrow),
      )
      let short = sheets_range_request_capacity(
        metadata, 1000, 10000, 16, false,
      ).unwrap()
      let longer = sheets_range_request_capacity(
        metadata, 2000, 10000, 16, false,
      ).unwrap()
      assert_true(
        @execution.execution_capacity_retained_bytes(longer) >
        @execution.execution_capacity_retained_bytes(short),
      )
    }
    assert_true(
      @execution.execution_capacity_execution_bytes(text) >
      @execution.execution_capacity_execution_bytes(narrow),
    )
  }
}

///|
test "range Source reader keeps native metadata scratch out of its returned material" {
  let narrow = sheets_range_read_construction_capacity(
    147, 3, 7, 2, 4, 0, 3, 1000, 32,
  ).unwrap()
  let wide = sheets_range_read_construction_capacity(
    147, 3, 7, 2, 4, 0, 3, 200000, 32,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(wide)
  let execution = @execution.execution_capacity_execution_bytes(wide)
  println("READER_NATIVE retained=\{retained} execution=\{execution}")
  assert_true(retained < execution)
  assert_eq(retained, @execution.execution_capacity_retained_bytes(narrow))
  assert_true(execution > @execution.execution_capacity_execution_bytes(narrow))
}

///|
test "range retained metadata bounds only its original expected tree before NFC" {
  let metadata = recovery_guard_test_metadata(300000)
  let range = sheets_range_capture_profile(
      metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, false,
    ).unwrap()[0]
  let clear = sheets_range_capture_profile(
      metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, true,
    ).unwrap()[0]
  let required = @execution.execution_capacity_execution_bytes(range)
  let wider = @execution.execution_capacity_execution_bytes(clear)
  println("ORIGINAL_RANGE_METADATA range=\{required} clear=\{wider}")
  // Clear retains the additionally supplied marker tree; range retains none.
  // Both normalize only the same original binding metadata after equality.
  assert_true(required <= wider)
}
