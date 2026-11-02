///|
test "same range and clear builders bound original variable names and complete exported wire" {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let names = ["name", "e\u{0301}\r\n\"\\", "🍎/original-field"]
  for name in names {
    let columns : Array[Json] = [
      { "name": name, "type": "boolean", "nullable": false },
    ]
    let schema = columns.to_json().stringify()
    let connector = "sheets-\u{1f34e}-original-connector"
    let range : Json = {
      "sheetId": 7,
      "startRow": 0,
      "endRow": 100,
      "startColumn": 0,
      "endColumn": 1,
    }
    let bound = range_declaration_construction_bounds(
      @utf8.encode(schema).length(),
      1,
      @utf8.encode(connector).length(),
    ).unwrap()
    for clear in [false, true] {
      let wire = if clear {
        clear_command_json(connector, schema, range.stringify(), limits).unwrap()
      } else {
        range_command_json(connector, schema, range.stringify(), limits).unwrap()
      }
      let document = @json.parse(wire) catch {
        _ => abort("original Command output")
      }
      assert_true(wire.length() <= bound.bundle_bytes)
      assert_true(range_template_nodes(document) <= bound.bundle_nodes)
      assert_true(range_template_depth(document) <= bound.bundle_depth)
    }
  }
  for columns in [0, 65] {
    assert_true(range_declaration_construction_bounds(100, columns, 1) is None)
  }
  assert_true(
    range_declaration_construction_bounds(2147483647, 64, 2147483647) is None,
  )
}

///|
test "Command template bounds cover the existing full sixty-four column width without reducing limits" {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let columns : Array[Json] = []
  for index in 0..<64 {
    columns.push({
      "name": "e\u{0301}\r\n\"\\" + index.to_string(),
      "type": "boolean",
      "nullable": false,
    })
  }
  let schema = columns.to_json().stringify()
  let range : Json = {
    "sheetId": 7,
    "startRow": 0,
    "endRow": 100,
    "startColumn": 0,
    "endColumn": 64,
  }
  let bound = range_declaration_construction_bounds(
    @utf8.encode(schema).length(),
    64,
    5,
  ).unwrap()
  for clear in [false, true] {
    let output = if clear {
      clear_command_json("sheet", schema, range.stringify(), limits).unwrap()
    } else {
      range_command_json("sheet", schema, range.stringify(), limits).unwrap()
    }
    let document = @json.parse(output) catch {
      _ => abort("original maximum-width Command")
    }
    assert_true(output.length() <= bound.bundle_bytes)
    assert_true(range_template_nodes(document) <= bound.bundle_nodes)
    assert_true(range_template_depth(document) <= bound.bundle_depth)
  }
}

///|
test "original Reference templates bound all fixed CIDs and Unicode installation identity without hashing a quote" {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let range : GridRange = {
    sheet_id: 2147483647,
    start_row: 0,
    end_row: 1,
    start_column: 0,
    end_column: 1,
  }
  let cid = "sha256:" + "a".repeat(64)
  for
    origin in [
      "https://fixture.invalid", "https://fixture.invalid/e\u{0301}🍎",
    ] {
    let bounds = range_reference_construction_bounds(
      @utf8.encode(origin).length(),
      4,
    ).unwrap()
    let original = range_reference(origin, "book", range, cid, cid, limits).unwrap()
    assert_true(original.stringify().length() <= bounds.reference_bytes)
    assert_true(range_template_nodes(original) <= bounds.reference_nodes)
    let provider = range_provider_identity_document(origin, "book")
    let identity = range_identity_document(range)
    assert_true(
      provider.stringify().length() + identity.stringify().length() <=
      bounds.identity_bytes,
    )
    assert_true(
      range_template_nodes(provider) + range_template_nodes(identity) <=
      bounds.identity_nodes,
    )
  }
  assert_true(range_reference_construction_bounds(0, 4) is None)
  assert_true(
    range_reference_construction_bounds(2147483647, 2147483647) is None,
  )
}
