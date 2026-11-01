///|
fn key_before_catalog() -> @catalog.FormFieldCatalog {
  @catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"customer_code\",\"expression\":\"\",\"unique\":true,\"required\":true},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"code\":\"memo\",\"required\":false},\"Tags\":{\"type\":\"MULTI_SELECT\",\"code\":\"Tags\",\"required\":false},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"Computed\",\"expression\":\"\\\"server\\\"\"},\"Extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"Extra\",\"expression\":\"\",\"required\":false}}}",
    "12",
    {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 10,
      max_name_units: 1000,
    },
  ).unwrap()
}

///|
fn key_before_declaration(
  catalog : @catalog.FormFieldCatalog,
  names? : Array[String] = ["customer_code", "Computed", "Tags", "memo"],
) -> RecordDeclaration {
  declare_records(
    catalog,
    None,
    names,
    "crm",
    "kintone/0.1",
    "customers",
    delete_preview_values(),
    delete_declaration_limits(),
  ).unwrap()
}

///|
fn key_before_lookup(
  catalog : @catalog.FormFieldCatalog,
  present : Bool,
  names? : Array[String] = ["memo", "Tags", "Computed"],
) -> @catalog.RecordLookupObservation {
  let request = @catalog.prepare_record_text_key_lookup(
    catalog,
    "customer_code",
    "original-key",
    names,
    {
      max_key_bytes: 1000,
      max_columns: 10,
      max_comparison_work: 10000,
      max_request_bytes: 20000,
      max_request_nodes: 1000,
      max_request_depth: 16,
    },
  ).unwrap()
  @catalog.project_record_key_lookup(
    request,
    200,
    if present {
      b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original-key\"},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"value\":\"東京 é\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"red\",\"東京\",\"red\"]},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"},\"Extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"extra\"}}],\"totalCount\":\"1\"}"
    } else {
      b"{\"records\":[],\"totalCount\":\"0\"}"
    },
    {
      max_bytes: 20000,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 2,
      max_columns: 10,
      max_cells: 20,
      max_table_rows: 10,
    },
  ).unwrap()
}

///|
fn key_before_write_limits() -> @catalog.RecordWriteLimits {
  {
    max_fields: 10,
    max_name_bytes: 1000,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 20000,
    max_output_bytes: 20000,
  }
}

///|
test "keyed UPSERT before retains full present original and reuses exact target in native UPDATE" {
  let catalog = key_before_catalog()
  let original = key_before_declaration(catalog)
  let lookup = key_before_lookup(catalog, true)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_before_key(before), "customer_code")
  assert_eq(record_key_upsert_before_identity(before), "original-key")
  assert_eq(
    record_key_upsert_before_wire(before),
    Some(
      "{\"$id\":\"9007199254740993\",\"memo\":\"東京 é\",\"Tags\":[\"red\",\"東京\",\"red\"],\"Computed\":\"server\",\"customer_code\":\"original-key\"}",
    ),
  )
  assert_eq(
    record_key_upsert_before_version_cid(before),
    Some(
      "sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd",
    ),
  )
  let target = record_key_upsert_before_target(before).unwrap()
  assert_eq(@catalog.original_record_target_id(target), "9007199254740993")
  assert_true(
    physical_equal(
      @catalog.original_record_target_page(target),
      @catalog.record_key_lookup_page(lookup),
    ),
  )
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  let request = @catalog.prepare_record_key_upsert_request(
    lookup,
    values,
    key_before_write_limits(),
    delete_preview_limits(),
    target=Some(target),
  ).unwrap()
  let native = @catalog.record_key_upsert_update_request(request).unwrap()
  assert_true(
    physical_equal(@catalog.record_update_request_values(native)[0].0, target),
  )
  assert_eq(
    @catalog.record_update_request_body(native),
    "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"memo\":{\"value\":\"next\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
  )
  assert_true(record_key_upsert_before_matches(before, original, lookup))
}

///|
test "keyed UPSERT before complete absence never fabricates native target before or version" {
  let catalog = key_before_catalog()
  let original = key_before_declaration(catalog)
  let lookup = key_before_lookup(catalog, false)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_before_key(before), "customer_code")
  assert_eq(record_key_upsert_before_identity(before), "original-key")
  assert_true(record_key_upsert_before_target(before) is None)
  assert_true(record_key_upsert_before_wire(before) is None)
  assert_true(record_key_upsert_before_version_cid(before) is None)
  assert_true(record_key_upsert_before_matches(before, original, lookup))
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  let request = @catalog.prepare_record_key_upsert_request(
    lookup,
    values,
    key_before_write_limits(),
    delete_preview_limits(),
    target=record_key_upsert_before_target(before),
  ).unwrap()
  assert_eq(
    @catalog.record_create_request_body(
      @catalog.record_key_upsert_create_request(request).unwrap(),
    ),
    "{\"app\":\"12\",\"records\":[{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}]}",
  )
  let present = prepare_record_key_upsert_before(
    original,
    key_before_lookup(catalog, true),
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_true(
    @catalog.prepare_record_key_upsert_request(
      lookup,
      values,
      key_before_write_limits(),
      delete_preview_limits(),
      target=record_key_upsert_before_target(present),
    )
    is Err(InvalidLookup),
  )
}

///|
test "keyed UPSERT before preserves declaration snapshot and refuses foreign incomplete copied and bounded material" {
  let catalog = key_before_catalog()
  let names = ["customer_code", "Computed", "Tags", "memo"]
  let original = key_before_declaration(catalog, names~)
  names.clear()
  record_declaration(original).views[0].fields.clear()
  let lookup = key_before_lookup(catalog, true)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  let copied : RecordKeyUpsertBefore = { ..before, }
  assert_false(record_key_upsert_before_matches(copied, original, lookup))
  assert_false(
    record_key_upsert_before_matches(
      before,
      key_before_declaration(catalog),
      lookup,
    ),
  )
  assert_false(
    record_key_upsert_before_matches(
      before,
      original,
      key_before_lookup(catalog, true),
    ),
  )
  for
    wrong in [
      key_before_lookup(key_before_catalog(), true),
      key_before_lookup(catalog, true, names=["memo"]),
      key_before_lookup(catalog, true, names=["memo", "Tags", "Extra"]),
    ] {
    assert_true(
      prepare_record_key_upsert_before(
        original,
        wrong,
        delete_preview_values(),
        delete_preview_limits(),
      )
      is Err(ForeignDeclaration),
    )
  }
  for
    limits in [
      { ..delete_preview_limits(), max_records: 0, },
      { ..delete_preview_limits(), max_comparison_work: 1, },
      { ..delete_preview_limits(), max_identity_bytes: 1, },
      { ..delete_preview_limits(), max_output_bytes: 1, },
    ] {
    assert_true(
      prepare_record_key_upsert_before(
        original,
        lookup,
        delete_preview_values(),
        limits,
      )
      is Err(_),
    )
  }
  let foreign = prepare_record_key_upsert_before(
    original,
    key_before_lookup(catalog, true),
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  assert_true(
    @catalog.prepare_record_key_upsert_request(
      lookup,
      values,
      key_before_write_limits(),
      delete_preview_limits(),
      target=record_key_upsert_before_target(foreign),
    )
    is Err(InvalidLookup),
  )
}
