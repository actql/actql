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
test "generic relation document nested physical values keep exact int64 and literal JSON wrappers" {
  // Independent schema bytes and SHA-256; no product-generated expectation.
  let wire =
    #|{"id":{"nullable":false,"type":"string"},"nested":{"additional_properties":false,"fields":{"counts":{"items":{"nullable":false,"type":"int64"},"nullable":false,"type":"array"},"payload":{"nullable":false,"type":"json"}},"nullable":false,"type":"object"}}
  let declaration = generate_relation_row_declaration(
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
  let salesforce = mock_update_declaration()
  let warehouse = mock_document_warehouse()
  let accounts = relation_document_test_project_account(original, salesforce).unwrap()
  let usage = relation_document_test_project_warehouse(original, warehouse).unwrap()
  assert_true(physical_equal(accounts.backing, original))
  assert_true(physical_equal(usage.backing, original))
  assert_true(physical_equal(accounts.bytes, usage.bytes))
  assert_true(physical_equal(accounts.bytes, original.bytes))
  assert_true(
    @decode.tree_index(original.root, accounts.row_cursors[0]) is Some(_),
  )
  assert_true(
    @decode.tree_index(original.root, usage.row_cursors[0]) is Some(_),
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
    relation_document_test_project_account(original, mock_update_declaration())
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
    relation_document_test_project_account(original, mock_update_declaration()).unwrap()
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
