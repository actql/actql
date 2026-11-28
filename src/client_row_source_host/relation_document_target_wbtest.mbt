///|
fn relation_document_test_limits() -> RowPageLimits {
  { max_bytes: 65536, max_nodes: 8192, max_depth: 32, max_rows: 100, }
}

///|
fn relation_document_test_text() -> String {
  " \n{\"kept\":{\"huge\":9223372036854775807},\"collection\":{\"records\":[" +
  "{\"label\" : \"before🌱\", \"choices\":[\"a\",\"b\"],\"id\":\"first\",\"amount\":\"123.450\"}," +
  "{\"amount\":null,\"choices\":[],\"id\":\"second\",\"label\":null}]}}\n "
}

///|
fn relation_document_test_admit(
  declaration : RowDeclaration,
  text : String,
  writable? : Array[String] = ["choices", "amount", "label"],
) -> Result[RelationTargetDocument, RowSourceIssue] {
  admit_relation_target_document(
    declaration,
    "records",
    ["collection", "records"],
    None,
    "id",
    writable,
    @utf8.encode(text),
    relation_document_test_limits(),
    10000000,
  )
}

///|
test "relation insertion keeps original bytes in both empty and populated collections" {
  let declaration = relation_mapping_declaration()
  let prefix = " {\"padding\":\"" +
    "x".repeat(4096) +
    "\",\"control\":[9223372036854775807],\"keys\":[\"id\"],\"collection\":{\"records\":["
  let suffix = " \t]}}\n"
  let previous = " {\"label\":null,\"choices\":[],\"amount\":null,\"id\":\"previous\"}"
  let mapped = "{\"amount\":\"123.450\",\"choices\":[\"é\"],\"label\":\"🌱\"}"
  let inserted = "{\"amount\":\"123.450\",\"choices\":[\"é\"],\"id\":\"new\",\"label\":\"🌱\"}"
  for
    case_ in [("", inserted, 1, 0), (previous, previous + "," + inserted, 2, 1)] {
    let (existing, output, count, index) = case_
    let input = @utf8.encode(prefix + existing + suffix)
    let expected = @utf8.encode(prefix + output + suffix)
    let limits = {
      ..relation_document_test_limits(),
      max_bytes: expected.length(),
      max_rows: count,
    }
    let original = admit_relation_document(input, limits, 10000000).unwrap()
    let prepared = prepare_relation_document_contract(
      declaration, "records", "id", limits,
    ).unwrap()
    let replacement = prepare_relation_target_insert(
      original,
      prepared,
      ["collection", "records"],
      Some(["keys"]),
      "new",
      mapped,
    ).unwrap()
    assert_eq(replacement, expected)
    let reopened = admit_relation_document(replacement, limits, 10000000).unwrap()
    let selected = project_relation_target_document(
      reopened,
      declaration,
      "records",
      ["collection", "records"],
      Some(["keys"]),
      "id",
      [],
      prepared_contract=Some(prepared),
    ).unwrap()
    assert_eq(relation_target_row_count(selected), Some(count))
    assert_eq(relation_target_row_identity(selected, index), Some("new"))
    let required_work = 10000000 - original.work.val
    let short = admit_relation_document(input, limits, required_work - 1).unwrap()
    assert_true(
      prepare_relation_target_insert(
        short,
        prepared,
        ["collection", "records"],
        Some(["keys"]),
        "new",
        mapped,
      )
      is Err(InvalidPage),
    )
    let short_limits = { ..limits, max_bytes: limits.max_bytes - 1, }
    let short_prepared = prepare_relation_document_contract(
      declaration, "records", "id", short_limits,
    ).unwrap()
    let shorter = admit_relation_document(input, short_limits, 10000000).unwrap()
    assert_true(
      prepare_relation_target_insert(
        shorter,
        short_prepared,
        ["collection", "records"],
        Some(["keys"]),
        "new",
        mapped,
      )
      is Err(InvalidPage),
    )
  }
}

///|
test "relation insertion refuses malformed identity row limits and retired backing" {
  let declaration = relation_mapping_declaration()
  let limits = relation_document_test_limits()
  let input = @utf8.encode(relation_document_test_text())
  let original = admit_relation_document(input, limits, 10000000).unwrap()
  let prepared = prepare_relation_document_contract(
    declaration, "records", "id", limits,
  ).unwrap()
  let items_path = ["collection", "records"]
  let injected = "{\"id\":\"new\",\"label\":null,\"amount\":null,\"choices\":[]}"
  let missing = "{\"label\":null,\"choices\":[]}"
  let invalid = "{\"label\":null,\"amount\":true,\"choices\":[]}"
  let row = "{\"label\":null,\"amount\":null,\"choices\":[]}"
  assert_true(
    prepare_relation_target_insert(
      original,
      prepared,
      items_path,
      None,
      "first",
      row,
    )
    is Err(InvalidPage),
  )
  assert_true(
    prepare_relation_target_insert(
      original,
      prepared,
      items_path,
      None,
      "new",
      missing,
    )
    is Err(MissingField("amount")),
  )
  assert_true(
    prepare_relation_target_insert(
      original,
      prepared,
      items_path,
      None,
      "new",
      invalid,
    )
    is Err(Value("amount")),
  )
  assert_true(
    prepare_relation_target_insert(
      original,
      prepared,
      items_path,
      None,
      "new",
      injected,
    )
    is Err(ForeignSource),
  )
  let full_limits = { ..limits, max_rows: 2, }
  let full = admit_relation_document(input, full_limits, 10000000).unwrap()
  assert_true(
    prepare_relation_target_insert(full, prepared, items_path, None, "new", row)
    is Err(InvalidPage),
  )
  assert_true(discard_relation_document_original(original))
  assert_true(
    prepare_relation_target_insert(
      original,
      prepared,
      items_path,
      None,
      "new",
      row,
    )
    is Err(ForeignSource),
  )
}

///|
fn relation_document_test_short_key_declaration() -> RowDeclaration {
  let schema =
    #|{"id":{"max_utf8_bytes":4,"nullable":false,"type":"string"},"value":{"nullable":true,"type":"string"}}
  generate_relation_row_declaration(
    "bounded-key",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        schema_wire: schema,
        schema_cid: "sha256:2cc0f64c724fff26994e950fd55362a8d478f0d0fdf2ad4dba6fc74402edc954",
        request_schema_wire: None,
        facts_wire: None,
        acquisition_wire: None,
      },
    ],
    delete_mapping_limits(),
  ).unwrap()
}

///|
test "relation insertion checks the supplied storage key against the original Text bound" {
  let declaration = relation_document_test_short_key_declaration()
  let limits = relation_document_test_limits()
  let prepared = prepare_relation_document_contract(
    declaration, "records", "id", limits,
  ).unwrap()
  let original = admit_relation_document(@utf8.encode("[]"), limits, 10000000).unwrap()
  let value = "{\"value\":null}"
  let bytes = prepare_relation_target_insert(
    original,
    prepared,
    [],
    None,
    "éé",
    value,
  ).unwrap()
  assert_eq(@utf8.decode(bytes), "[{\"id\":\"éé\",\"value\":null}]")
  assert_true(
    prepare_relation_target_insert(original, prepared, [], None, "ééa", value)
    is Err(Value("id")),
  )
}

///|
test "relation insertion workspace includes decoded input row output and full replacement" {
  let limits = relation_document_test_limits()
  let source = @utf8.encode("{\"collection\":{\"records\":[]}}")
  let wire = "{\"label\":\"é\",\"amount\":\"1.000\",\"choices\":[]}"
  let prepared = prepare_relation_document_contract(
    relation_mapping_declaration(),
    "records",
    "id",
    limits,
  ).unwrap()
  let workspace = relation_target_insert_workspace_inventory(
    prepared,
    2,
    source.length(),
    wire.length(),
  ).unwrap()
  // Borrowed input file backing is separate. Encoded input at 3B per UTF-16
  // unit, encoded output row with all remaining room, and full replacement
  // coexist. None of the three can be netted against a previously held input.
  assert_eq(
    workspace.owned_wire_bytes,
    (3 * wire.length() + 2 * limits.max_bytes - source.length()).to_int64(),
  )
  assert_true(workspace.owned_utf16_units > 0L)
  assert_true(@execution.preparation_representation_cost(workspace) is Some(_))
  let original = admit_relation_document(source, limits, 10000000).unwrap()
  let bytes = prepare_relation_target_insert(
    original,
    prepared,
    ["collection", "records"],
    None,
    "new🌱",
    wire,
  ).unwrap()
  assert_eq(
    @utf8.decode(bytes),
    "{\"collection\":{\"records\":[{\"amount\":\"1.000\",\"choices\":[],\"id\":\"new🌱\",\"label\":\"é\"}]}}",
  )
  assert_true(
    relation_target_insert_workspace_inventory(
      prepared,
      limits.max_depth - 1,
      source.length(),
      wire.length(),
    )
    is None,
  )
  assert_true(
    relation_target_insert_workspace_inventory(
      prepared,
      2,
      limits.max_bytes,
      wire.length(),
    )
    is None,
  )
  assert_true(
    relation_target_insert_workspace_inventory(
      prepared,
      2,
      source.length(),
      limits.max_bytes + 1,
    )
    is None,
  )
}

///|
test "relation target deletion preserves rows whitespace and another collection" {
  let declaration = relation_mapping_declaration()
  let first = "{\"id\":\"first\",\"label\":\"before🌱\",\"choices\":[\",\"],\"amount\":null}"
  let middle = "{\"id\":\"middle\",\"label\":null,\"choices\":[],\"amount\":\"123.450\"}"
  let last = "{\"id\":\"last\",\"label\":null,\"choices\":[],\"amount\":null}"
  let prefix = " \n{\"control\":[\{middle}],\"collection\":{\"records\":[ "
  let suffix = " ]}}\n "
  let input = prefix + first + " \t,\n" + middle + "  ,\r\n" + last + suffix
  let document = relation_document_test_admit(declaration, input).unwrap()
  for
    item in [
      ("first", " \t\n" + middle + "  ,\r\n" + last, 4, ["middle", "last"]),
      ("middle", first + " \t,\n  \r\n" + last, 5, ["first", "last"]),
      ("last", first + " \t,\n" + middle + "  \r\n", 5, ["first", "middle"]),
    ] {
    let (id, records, gap, kept) = item
    let row = observe_relation_target(document, declaration, id).unwrap()
    let version = relation_target_version(row).unwrap()
    let expected = @utf8.encode(prefix + records + suffix)
    let max_work = expected.length() + gap
    let output = prepare_relation_target_delete(
      document, row, version, max_work,
    ).unwrap()
    assert_eq(output, expected)
    assert_true(
      prepare_relation_target_delete(document, row, version, max_work - 1)
      is Err(InvalidPage),
    )
    let next = relation_document_test_admit(declaration, @utf8.decode(output)).unwrap()
    assert_eq(relation_target_row_count(next), Some(2))
    for index, identity in kept {
      assert_eq(relation_target_row_identity(next, index), Some(identity))
    }
  }
  let singleton = relation_document_test_admit(
    declaration,
    prefix + middle + suffix,
  ).unwrap()
  let row = observe_relation_target(singleton, declaration, "middle").unwrap()
  let expected = @utf8.encode(prefix + suffix)
  assert_eq(
    prepare_relation_target_delete(
      singleton,
      row,
      relation_target_version(row).unwrap(),
      expected.length(),
    ).unwrap(),
    expected,
  )
}

///|
test "relation target deletion requires the same observed original and version" {
  let declaration = relation_mapping_declaration()
  let input = relation_document_test_text()
  let document = relation_document_test_admit(declaration, input).unwrap()
  let other = relation_document_test_admit(declaration, input).unwrap()
  let row = observe_relation_target(document, declaration, "first").unwrap()
  let version = relation_target_version(row).unwrap()
  assert_true(
    prepare_relation_target_delete(document, row, "stale", 10000000)
    is Err(ForeignSource),
  )
  assert_true(
    prepare_relation_target_delete(other, row, version, 10000000)
    is Err(ForeignSource),
  )
  assert_true(
    prepare_relation_target_delete(document, { ..row, }, version, 10000000)
    is Err(ForeignSource),
  )
  assert_true(discard_relation_target_document_original(document))
  assert_true(
    prepare_relation_target_delete(document, row, version, 10000000)
    is Err(ForeignSource),
  )
}

///|
test "generic relation target applies arbitrary typed fields and preserves every untouched byte" {
  let declaration = relation_mapping_declaration()
  let original = relation_document_test_text()
  let document = relation_document_test_admit(declaration, original).unwrap()
  let row = observe_relation_target(document, declaration, "first").unwrap()
  let output = prepare_relation_target_update(
    document,
    row,
    relation_target_version(row).unwrap(),
    "{\"choices\":[\"new\",\"会社\"],\"amount\":null,\"label\":\"after\\n🌱\"}",
    10000000,
  ).unwrap()
  assert_eq(
    @utf8.decode(output),
    original
    .replace(old="\"before🌱\"", new="\"after\\n🌱\"")
    .replace(old="[\"a\",\"b\"]", new="[\"new\",\"会社\"]")
    .replace(old="\"123.450\"", new="null"),
  )
  relation_document_test_admit(declaration, @utf8.decode(output)).unwrap()
  |> ignore
  assert_eq(relation_target_row_count(document), Some(2))
  assert_eq(relation_target_row_identity(document, 0), Some("first"))
  assert_eq(relation_target_row_identity(document, 2), None)
  assert_eq(relation_target_text(row, "label"), Some("before🌱"))
  assert_eq(
    relation_target_text_bytes(row, "label"),
    Some(@utf8.encode("before🌱")),
  )
  assert_eq(relation_target_text(row, "choices"), None)
}

///|
test "generic relation target owns originals and versions across independent row updates" {
  let declaration = relation_mapping_declaration()
  let original = relation_document_test_text()
  let document = relation_document_test_admit(declaration, original).unwrap()
  let row = observe_relation_target(document, declaration, "first").unwrap()
  let unchanged = observe_relation_target(document, declaration, "second").unwrap()
  assert_true(
    observe_relation_target({ ..document, }, declaration, "first")
    is Err(ForeignSource),
  )
  assert_eq(relation_target_before({ ..row, }), None)
  assert_eq(relation_target_text({ ..row, }, "label"), None)
  assert_eq(relation_target_row_count({ ..document, }), None)
  assert_true(
    observe_relation_target(document, relation_mapping_declaration(), "first")
    is Err(ForeignSource),
  )
  let update = "{\"label\":\"changed\"}"
  assert_true(
    prepare_relation_target_update(document, row, "stale", update, 10000000)
    is Err(ForeignSource),
  )
  let other = relation_document_test_admit(declaration, original).unwrap()
  assert_true(
    prepare_relation_target_update(
      other,
      row,
      relation_target_version(row).unwrap(),
      update,
      10000000,
    )
    is Err(ForeignSource),
  )
  let bytes = prepare_relation_target_update(
    document,
    row,
    relation_target_version(row).unwrap(),
    update,
    10000000,
  ).unwrap()
  let next = relation_document_test_admit(declaration, @utf8.decode(bytes)).unwrap()
  assert_true(
    relation_target_version(row) !=
    relation_target_version(
      observe_relation_target(next, declaration, "first").unwrap(),
    ),
  )
  assert_eq(
    relation_target_version(unchanged),
    relation_target_version(
      observe_relation_target(next, declaration, "second").unwrap(),
    ),
  )
}

///|
test "generic relation target validates all rows identity writable set types and bounds" {
  let declaration = relation_mapping_declaration()
  let original = relation_document_test_text()
  for
    text in [
      original.replace(old="\"second\"", new="\"first\""),
      original.replace(old="\"choices\":[]", new="\"choices\":[1]"),
      original.replace(old="\"id\":\"second\"", new="\"id\":null"),
      original.replace(
        old="\"id\":\"second\"",
        new="\"id\":\"second\",\"extra\":1",
      ),
      original.replace(old="\"amount\":null,", new=""),
    ] {
    assert_true(relation_document_test_admit(declaration, text) is Err(_))
  }
  for writable in [["id"], ["missing"], ["label", "label"]] {
    assert_true(
      relation_document_test_admit(declaration, original, writable~) is Err(_),
    )
  }
  let document = relation_document_test_admit(declaration, original, writable=[
    "label", "choices", "amount",
  ]).unwrap()
  let row = observe_relation_target(document, declaration, "first").unwrap()
  for
    update in [
      "{}", "{\"id\":\"changed\"}", "{\"label\":5}", "{\"choices\":[null]}", "{\"amount\":\"1.2345\"}",
      "{\"label\":\"a\",\"label\":\"b\"}",
    ] {
    assert_true(
      prepare_relation_target_update(
        document,
        row,
        relation_target_version(row).unwrap(),
        update,
        10000000,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_relation_target_update(
      document,
      row,
      relation_target_version(row).unwrap(),
      "{\"label\":null}",
      0,
    )
    is Err(_),
  )
  let read_only = relation_document_test_admit(declaration, original, writable=[]).unwrap()
  let read = observe_relation_target(read_only, declaration, "first").unwrap()
  assert_true(
    prepare_relation_target_update(
      read_only,
      read,
      relation_target_version(read).unwrap(),
      "{\"label\":null}",
      10000000,
    )
    is Err(_),
  )
  assert_true(
    admit_relation_target_document(
      declaration,
      "records",
      ["collection", "records"],
      None,
      "id",
      [],
      @utf8.encode(original),
      relation_document_test_limits(),
      0,
    )
    is Err(_),
  )
}

///|
fn mock_document_declaration_limits() -> RowDeclarationLimits {
  {
    max_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
    max_views: 4,
    max_fields: 16,
  }
}

///|
fn mock_document_account() -> RowDeclaration {
  generate_relation_row_declaration(
    "salesforce",
    "mock_salesforce",
    "mock_salesforce/0.1",
    [
      {
        resource: "Account",
        resource_kind: "record",
        schema_wire: "{\"Churn_Risk__c\":{\"nullable\":false,\"type\":\"string\"},\"Risk_Reason__c\":{\"nullable\":true,\"type\":\"string\"},\"description\":{\"nullable\":false,\"type\":\"string\"},\"id\":{\"nullable\":false,\"type\":\"string\"},\"name\":{\"nullable\":false,\"type\":\"string\"}}",
        schema_cid: "sha256:2bb86ad0dae4e6ab1cde7bb339f74cd3959dc572f6ad54f6da5487765709307d",
        request_schema_wire: None,
        facts_wire: Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
        acquisition_wire: None,
      },
    ],
    mock_document_declaration_limits(),
  ).unwrap()
}

///|
fn mock_document_warehouse() -> RowDeclaration {
  generate_relation_row_declaration(
    "snowflake",
    "mock_snowflake",
    "mock_snowflake/0.1",
    [
      {
        resource: "usage_30d",
        resource_kind: "table",
        schema_wire: "{\"account_id\":{\"nullable\":false,\"type\":\"string\"},\"active_users\":{\"nullable\":false,\"type\":\"int64\"},\"trend\":{\"nullable\":false,\"type\":\"string\"}}",
        schema_cid: "sha256:fd038c1aa8fe013d4838819a6011e18aee81a04a179f1994a548ff292dfae424",
        request_schema_wire: None,
        facts_wire: Some(
          "{\"relation_keys\":{\"candidate_keys\":[[\"account_id\"]]}}",
        ),
        acquisition_wire: None,
      },
    ],
    mock_document_declaration_limits(),
  ).unwrap()
}

///|
fn mock_document_text(count? : String = "4") -> String {
  "{\"salesforce\":{\"Account\":{\"key\":[\"id\"],\"rows\":[" +
  "{\"id\":\"001Acme\",\"name\":\"Acme Corp\",\"description\":\"Evaluating a competitor; usage down since June.\",\"Churn_Risk__c\":\"low\",\"Risk_Reason__c\":null}," +
  "{\"id\":\"001Globex\",\"name\":\"Globex Inc\",\"description\":\"Several support tickets about the new pricing.\",\"Churn_Risk__c\":\"medium\",\"Risk_Reason__c\":null}]}}," +
  "\"snowflake\":{\"usage_30d\":{\"key\":[\"account_id\"],\"rows\":[" +
  "{\"account_id\":\"001Acme\",\"active_users\":" +
  count +
  ",\"trend\":\"down\"}," +
  "{\"account_id\":\"001Globex\",\"active_users\":12,\"trend\":\"flat\"}]}}}"
}

///|
test "generic relation document physical int64 codec preserves exact tokens under original schema" {
  let declaration = mock_document_warehouse()
  for
    token in [
      "4", "-9223372036854775808", "9007199254740993", "9223372036854775807",
    ] {
    let document = admit_relation_target_document(
      declaration,
      "usage_30d",
      ["snowflake", "usage_30d", "rows"],
      Some(["snowflake", "usage_30d", "key"]),
      "account_id",
      [],
      @utf8.encode(mock_document_text(count=token)),
      relation_document_test_limits(),
      10000000,
    ).unwrap()
    let row = observe_relation_target(document, declaration, "001Acme").unwrap()
    assert_true(
      relation_target_before(row)
      .unwrap()
      .contains("\"active_users\":\"" + token + "\""),
    )
  }
  for token in ["4.0", "4e0", "9223372036854775808", "-9223372036854775809"] {
    assert_true(
      admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(["snowflake", "usage_30d", "key"]),
        "account_id",
        [],
        @utf8.encode(mock_document_text(count=token)),
        relation_document_test_limits(),
        10000000,
      )
      is Err(_),
    )
  }
}

///|
fn relation_document_test_nested_declaration() -> RowDeclaration {
  // Independent schema bytes and SHA-256; no product-generated expectation.
  let wire =
    #|{"id":{"nullable":false,"type":"string"},"nested":{"additional_properties":false,"fields":{"counts":{"items":{"nullable":false,"type":"int64"},"nullable":false,"type":"array"},"payload":{"nullable":false,"type":"json"}},"nullable":false,"type":"object"}}
  generate_relation_row_declaration(
    "nested",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        schema_wire: wire,
        schema_cid: "sha256:848a28d634fcb1c4f65e827a6a93e1caa4a1f1c66e9ff8eddd2220e35b871544",
        request_schema_wire: None,
        facts_wire: None,
        acquisition_wire: None,
      },
    ],
    delete_mapping_limits(),
  ).unwrap()
}

///|
test "relation insertion fits physical depth after removing the typed JSON wrapper" {
  let declaration = relation_document_test_nested_declaration()
  let path = Array::make(27, "inner")
  let prefix = "{\"inner\":".repeat(path.length())
  let suffix = "}".repeat(path.length())
  let input = @utf8.encode(prefix + "[]" + suffix)
  let row =
    #|{"nested":{"counts":[],"payload":{"$json":{"$json":"literal"}}}}
  let physical =
    #|[{"id":"new","nested":{"counts":[],"payload":{"$json":"literal"}}}]
  let expected = @utf8.encode(prefix + physical + suffix)
  for depth in [31, 30] {
    let limits = { ..relation_document_test_limits(), max_depth: depth, }
    let backing = admit_relation_document(input, limits, 10000000).unwrap()
    let prepared = prepare_relation_document_contract(
      declaration, "records", "id", limits,
    ).unwrap()
    let result = prepare_relation_target_insert(
      backing,
      prepared,
      path,
      None,
      "new",
      row,
    )
    if depth == 31 {
      assert_eq(result.unwrap(), expected)
      assert_true(admit_relation_document(expected, limits, 10000000) is Ok(_))
    } else {
      assert_true(result is Err(InvalidPage))
      assert_true(
        admit_relation_document(expected, limits, 10000000) is Err(InvalidPage),
      )
    }
  }
}

///|
test "generic relation document nested physical values keep exact int64 and literal JSON wrappers" {
  let declaration = relation_document_test_nested_declaration()
  let original = "[{\"id\":\"row\", \"nested\" : {\"counts\":[9007199254740993,-9223372036854775808],\"payload\":{\"$json\":\"literal\",\"é\":1,\"é\":2}}}]"
  let document = admit_relation_target_document(
    declaration,
    "records",
    [],
    None,
    "id",
    ["nested"],
    @utf8.encode(original),
    relation_document_test_limits(),
    10000000,
  ).unwrap()
  let row = observe_relation_target(document, declaration, "row").unwrap()
  assert_true(
    relation_target_before(row)
    .unwrap()
    .contains("\"counts\":[\"9007199254740993\",\"-9223372036854775808\"]"),
  )
  let output = prepare_relation_target_update(
    document,
    row,
    relation_target_version(row).unwrap(),
    "{\"nested\":{\"counts\":[\"9223372036854775807\"],\"payload\":{\"$json\":{\"$json\":\"next\",\"é\":\"会社🌱\"}}}}",
    10000000,
  ).unwrap()
  assert_eq(
    @utf8.decode(output),
    "[{\"id\":\"row\", \"nested\" : {\"counts\":[\"9223372036854775807\"],\"payload\":{\"$json\":\"next\",\"é\":\"会社🌱\"}}}]",
  )
  admit_relation_target_document(
    declaration,
    "records",
    [],
    None,
    "id",
    ["nested"],
    output,
    relation_document_test_limits(),
    10000000,
  ).unwrap()
  |> ignore
}

///|
test "generic relation document explicitly accepts canonical int64 text and exact physical integer tokens" {
  let declaration = mock_document_warehouse()
  for
    token in [
      "4", "-9223372036854775808", "9007199254740993", "9223372036854775807",
    ] {
    let versions = []
    for physical in [token, "\"" + token + "\""] {
      let document = admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(["snowflake", "usage_30d", "key"]),
        "account_id",
        [],
        @utf8.encode(mock_document_text(count=physical)),
        relation_document_test_limits(),
        10000000,
      ).unwrap()
      versions.push(
        relation_target_version(
          observe_relation_target(document, declaration, "001Acme").unwrap(),
        ).unwrap(),
      )
    }
    assert_eq(versions[0], versions[1])
  }
  for
    token in [
      "\"4.0\"", "\"4e0\"", "\"9223372036854775808\"", "\"-9223372036854775809\"",
      "\"04\"", "\"-0\"",
    ] {
    assert_true(
      admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(["snowflake", "usage_30d", "key"]),
        "account_id",
        [],
        @utf8.encode(mock_document_text(count=token)),
        relation_document_test_limits(),
        10000000,
      )
      is Err(_),
    )
  }
}

///|
test "generic relation document checks explicit key metadata on the original admitted cursor" {
  let declaration = mock_document_warehouse()
  let original = mock_document_text()
  for
    replacement in [
      "[]", "[\"id\"]", "[\"account_id\",\"account_id\"]", "[\"account_id\",\"trend\"]",
      "[1]", "null", "\"account_id\"",
    ] {
    let changed = original.replace(
      old="\"key\":[\"account_id\"]",
      new="\"key\":" + replacement,
    )
    assert_true(
      admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(["snowflake", "usage_30d", "key"]),
        "account_id",
        [],
        @utf8.encode(changed),
        relation_document_test_limits(),
        10000000,
      )
      is Err(_),
    )
  }
  for
    path in [
      ["missing"],
      ["snowflake", "usage_30d", "rows"],
      ["snowflake", "usage_30d", "key", "nested"],
    ] {
    assert_true(
      admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(path),
        "account_id",
        [],
        @utf8.encode(original),
        relation_document_test_limits(),
        10000000,
      )
      is Err(_),
    )
  }
  for
    changed in [
      original.replace(old="\"key\":[\"account_id\"],", new=""),
      original.replace(
        old="\"key\":[\"account_id\"]",
        new="\"key\":[\"account_id\"],\"key\":[\"account_id\"]",
      ),
    ] {
    assert_true(
      admit_relation_target_document(
        declaration,
        "usage_30d",
        ["snowflake", "usage_30d", "rows"],
        Some(["snowflake", "usage_30d", "key"]),
        "account_id",
        [],
        @utf8.encode(changed),
        relation_document_test_limits(),
        10000000,
      )
      is Err(_),
    )
  }
}

///|
fn relation_document_test_project_warehouse(
  original : RelationDocument,
  declaration : RowDeclaration,
) -> Result[RelationTargetDocument, RowSourceIssue] {
  project_relation_target_document(
    original,
    declaration,
    "usage_30d",
    ["snowflake", "usage_30d", "rows"],
    Some(["snowflake", "usage_30d", "key"]),
    "account_id",
    [],
  )
}

///|
fn relation_document_test_project_account(
  original : RelationDocument,
  declaration : RowDeclaration,
) -> Result[RelationTargetDocument, RowSourceIssue] {
  project_relation_target_document(
    original,
    declaration,
    "Account",
    ["salesforce", "Account", "rows"],
    Some(["salesforce", "Account", "key"]),
    "id",
    ["Churn_Risk__c", "Risk_Reason__c"],
  )
}

///|
test "relation projections share one admitted original and retain exact external data" {
  let bytes = @utf8.encode(mock_document_text(count="9007199254740993"))
  let original = admit_relation_document(
    bytes,
    relation_document_test_limits(),
    10000000,
  ).unwrap()
  let before = relation_document_usage(original).unwrap()
  assert_eq(before.raw_bytes, bytes.length())
  assert_eq(before.projection_attempts, 0)
  assert_eq(before.projected_cells, 0L)
  assert_false(physical_equal(original.bytes, bytes))
  let salesforce = mock_document_account()
  let warehouse = mock_document_warehouse()
  let accounts = relation_document_test_project_account(original, salesforce).unwrap()
  let usage = relation_document_test_project_warehouse(original, warehouse).unwrap()
  assert_true(physical_equal(accounts.backing, original))
  assert_true(physical_equal(usage.backing, original))
  assert_true(physical_equal(accounts.bytes, usage.bytes))
  assert_true(physical_equal(accounts.bytes, original.bytes))
  assert_true(
    @decode.tree_index(
      original.root,
      @decode.element_at(accounts.row_array, 0).unwrap(),
    )
    is Some(_),
  )
  assert_true(
    @decode.tree_index(
      original.root,
      @decode.element_at(usage.row_array, 0).unwrap(),
    )
    is Some(_),
  )
  let after = relation_document_usage(original).unwrap()
  assert_eq(after.raw_nodes, before.raw_nodes)
  assert_eq(after.raw_text_bytes, before.raw_text_bytes)
  assert_eq(after.projection_attempts, 2)
  assert_eq(after.projections, 2)
  assert_eq(after.projected_rows, 4L)
  assert_eq(after.projected_cells, 16L)
  assert_true(after.remaining_work < before.remaining_work)
  let row = observe_relation_target(usage, warehouse, "001Acme").unwrap()
  assert_true(
    relation_target_before(row)
    .unwrap()
    .contains("\"active_users\":\"9007199254740993\""),
  )
  let other = admit_relation_document(
    @utf8.encode(mock_document_text(count="4")),
    relation_document_test_limits(),
    10000000,
  ).unwrap()
  let changed = relation_document_test_project_warehouse(other, warehouse).unwrap()
  assert_true(
    relation_target_version(row) !=
    relation_target_version(
      observe_relation_target(changed, warehouse, "001Acme").unwrap(),
    ),
  )
  assert_eq(
    @utf8.decode(original.bytes),
    mock_document_text(count="9007199254740993"),
  )
  assert_true(
    relation_document_test_project_warehouse({ ..original, }, warehouse)
    is Err(ForeignSource),
  )
  assert_eq(relation_document_usage({ ..original, }), None)
}

///|
test "relation projections share cumulative work across successful and failed attempts" {
  let original = admit_relation_document(
    @utf8.encode(mock_document_text()),
    relation_document_test_limits(),
    100000,
  ).unwrap()
  let warehouse = mock_document_warehouse()
  relation_document_test_project_warehouse(original, warehouse).unwrap()
  |> ignore
  let after_first = relation_document_usage(original).unwrap()
  assert_eq(after_first.projections, 1)
  assert_true(after_first.remaining_work < 50000)
  assert_true(
    relation_document_test_project_account(original, mock_document_account())
    is Err(_),
  )
  let after_failure = relation_document_usage(original).unwrap()
  assert_eq(after_failure.projection_attempts, 2)
  assert_eq(after_failure.projections, 1)
  assert_eq(after_failure.projected_rows, 2L)
  assert_eq(after_failure.projected_cells, 6L)
  assert_true(after_failure.remaining_work < after_first.remaining_work)
  assert_true(
    relation_document_test_project_warehouse(original, warehouse) is Err(_),
  )
  assert_true(
    relation_document_usage(original).unwrap().remaining_work <=
    after_failure.remaining_work,
  )
  // No per-projection max_work argument can reset this original's budget.
  let fresh = admit_relation_document(
    @utf8.encode(mock_document_text()),
    relation_document_test_limits(),
    100000,
  ).unwrap()
  relation_document_test_project_warehouse(fresh, warehouse).unwrap() |> ignore
}

///|
test "shared relation original preserves key and typed failures without accepting siblings by implication" {
  let warehouse = mock_document_warehouse()
  for
    invalid in [
      mock_document_text().replace(
        old="\"key\":[\"account_id\"]",
        new="\"key\":[\"trend\"]",
      ),
      mock_document_text(count="4.0"),
      mock_document_text(count="4e0"),
      mock_document_text(count="9223372036854775808"),
      mock_document_text().replace(
        old="\"trend\":\"down\"",
        new="\"trend\":null",
      ),
    ] {
    let original = admit_relation_document(
      @utf8.encode(invalid),
      relation_document_test_limits(),
      10000000,
    ).unwrap()
    relation_document_test_project_account(original, mock_document_account()).unwrap()
    |> ignore
    let before = relation_document_usage(original).unwrap()
    assert_true(
      relation_document_test_project_warehouse(original, warehouse) is Err(_),
    )
    let after = relation_document_usage(original).unwrap()
    assert_eq(after.projection_attempts, 2)
    assert_eq(after.projections, 1)
    assert_true(after.remaining_work < before.remaining_work)
    assert_eq(@utf8.decode(original.bytes), invalid)
  }
}

///|
test "prepared relation metadata reuses original schema while preserving exact target rows" {
  let declaration = relation_mapping_declaration()
  let limits = relation_document_test_limits()
  let prepared = prepare_relation_document_contract(
    declaration, "records", "id", limits,
  ).unwrap()
  let bytes = @utf8.encode(relation_document_test_text())
  let original = admit_relation_document(bytes, limits, 10000000).unwrap()
  let projected = project_relation_target_document(
    original,
    declaration,
    "records",
    ["collection", "records"],
    None,
    "id",
    [],
    prepared_contract=Some(prepared),
  ).unwrap()
  assert_eq(relation_target_row_count(projected), Some(2))
  let first = observe_relation_target(projected, declaration, "first").unwrap()
  assert_eq(relation_target_text(first, "label"), Some("before🌱"))
  assert_eq(@utf8.decode(original.bytes), relation_document_test_text())
  let legacy_original = admit_relation_document(bytes, limits, 10000000).unwrap()
  let legacy = project_relation_target_document(
    legacy_original,
    declaration,
    "records",
    ["collection", "records"],
    None,
    "id",
    [],
  ).unwrap()
  assert_eq(relation_target_row_count(legacy), Some(2))
  assert_eq(
    relation_target_before(first),
    relation_target_before(
      observe_relation_target(legacy, declaration, "first").unwrap(),
    ),
  )
  let reused = relation_document_usage(original).unwrap()
  let checked_again = relation_document_usage(legacy_original).unwrap()
  assert_eq(reused.projection_attempts, 1)
  assert_eq(reused.projections, 1)
  // Same row/Value/path work, without the old mapping reconstruction debit.
  // This is work-counter evidence, not elapsed-time or physical backing proof.
  assert_true(reused.remaining_work > checked_again.remaining_work)
}

///|
test "prepared relation metadata rejects foreign originals bounds and invalid actual values" {
  let declaration = relation_mapping_declaration()
  let limits = relation_document_test_limits()
  let prepared = prepare_relation_document_contract(
    declaration, "records", "id", limits,
  ).unwrap()
  let bytes = @utf8.encode(relation_document_test_text())
  let foreign = relation_mapping_declaration()
  let original = admit_relation_document(bytes, limits, 10000000).unwrap()
  assert_true(
    project_relation_target_document(
      original,
      foreign,
      "records",
      ["collection", "records"],
      None,
      "id",
      [],
      prepared_contract=Some(prepared),
    )
    is Err(ForeignSource),
  )
  let smaller = admit_relation_document(
    bytes,
    { ..limits, max_bytes: 65535, },
    10000000,
  ).unwrap()
  assert_true(
    project_relation_target_document(
      smaller,
      declaration,
      "records",
      ["collection", "records"],
      None,
      "id",
      [],
      prepared_contract=Some(prepared),
    )
    is Err(ForeignSource),
  )
  let invalid = relation_document_test_text().replace(
    old="\"before🌱\"",
    new="123",
  )
  let invalid = admit_relation_document(@utf8.encode(invalid), limits, 10000000).unwrap()
  assert_true(
    project_relation_target_document(
      invalid,
      declaration,
      "records",
      ["collection", "records"],
      None,
      "id",
      [],
      prepared_contract=Some(prepared),
    )
    is Err(Value("label")),
  )
  assert_eq(relation_document_usage(invalid).unwrap().projections, 0)
}

///|
test "relation target indexes the original at the existing page row limit" {
  let declaration = relation_mapping_declaration()
  let print_row = index => {
    "{\"amount\":null,\"choices\":[],\"id\":\"row-\{index}\",\"label\":null}"
  }
  let rows = Array::makei(100, print_row)
  let document_wire = (items : Array[String]) => {
    "{\"collection\":{\"records\":[" + items.join(",") + "]}}"
  }
  let admitted = relation_document_test_admit(declaration, document_wire(rows)).unwrap()
  assert_eq(relation_target_row_count(admitted), Some(100))
  assert_eq(relation_target_row_identity(admitted, 0), Some("row-0"))
  assert_eq(relation_target_row_identity(admitted, 99), Some("row-99"))
  assert_eq(relation_target_row_identity(admitted, 100), None)
  let last = observe_relation_target(admitted, declaration, "row-99").unwrap()
  let updated = prepare_relation_target_update(
    admitted,
    last,
    relation_target_version(last).unwrap(),
    "{\"label\":\"updated\"}",
    10000000,
  ).unwrap()
  let previous = rows[99]
  rows[99] = previous.replace(old="\"label\":null", new="\"label\":\"updated\"")
  assert_eq(@utf8.decode(updated), document_wire(rows))
  rows.push(print_row(100))
  assert_true(
    relation_document_test_admit(declaration, document_wire(rows))
    is Err(InvalidPage),
  )
}
