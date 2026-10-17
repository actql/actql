///|
fn update_mapping_form() -> @catalog.FormFieldCatalog {
  @catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true},\"Tags\":{\"code\":\"Tags\",\"type\":\"MULTI_SELECT\",\"required\":false},\"Computed\":{\"code\":\"Computed\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\\\"server\\\"\"}}}",
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
}

///|
fn update_mapping_declaration(
  catalog : @catalog.FormFieldCatalog,
) -> RecordDeclaration {
  declare_records(
    catalog,
    None,
    ["Subject", "Tags", "Computed"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    {
      max_columns: 8,
      max_name_bytes: 128,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
    },
    delete_declaration_limits(),
  ).unwrap()
}

///|
fn update_mapping_sources() -> Array[@rows.RowMappingSource] {
  [
    { target: "Subject", field: "originalSubject", null_behavior: "reject", },
    { target: "Tags", field: "originalTags", null_behavior: "reject", },
  ]
}

///|
fn update_mapping_request(
  catalog : @catalog.FormFieldCatalog,
  fields? : Array[String] = ["Subject", "Tags", "Computed"],
  write_tags? : Bool = true,
) -> @catalog.RecordUpdateRequest {
  let page = @catalog.project_record_page(
    b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"old\"]},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"}}],\"totalCount\":null}",
    catalog,
    fields,
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 4,
      max_columns: 8,
      max_cells: 32,
      max_table_rows: 16,
    },
  ).unwrap()
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let values = [
    ("Subject", @admitted.checked_text_value("next", text).unwrap()),
  ]
  if write_tags {
    let tags = @admitted.recheck_runtime_value(
      @admitted.array_value([
        @admitted.checked_text_value("東京", text).unwrap().value,
        @admitted.checked_text_value("red", text).unwrap().value,
        @admitted.checked_text_value("東京", text).unwrap().value,
      ]),
      @contract.array_contract(text, nullable=false).unwrap(),
      { max_nodes: 1000, max_depth: 16, max_text_bytes: 8192, },
    ).unwrap()
    values.push(("Tags", tags))
  }
  let write = @catalog.prepare_record_write_values(catalog, values, {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }).unwrap()
  @catalog.prepare_record_update_request(
    [(@catalog.prepare_original_record_target(page, 0, 1000).unwrap(), write)],
    {
      max_records: 100,
      max_identity_bytes: 1000,
      max_comparison_work: 10000,
      max_output_bytes: 8192,
      max_output_nodes: 1000,
      max_output_depth: 16,
    },
  ).unwrap()
}

///|
test "kintone typed UPDATE Mapping retains original Array schema and same request values" {
  let catalog = update_mapping_form()
  let original = update_mapping_declaration(catalog)
  let owned = prepare_record_update_mapping(
    original,
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let mapping = record_update_mapping(owned)
  assert_true(
    mapping.body.contains(
      "\"Tags\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":false,\"type\":\"array\"}",
    ),
  )
  assert_true(
    mapping.body.contains(
      "\"Computed\":{\"nullable\":false,\"type\":\"string\"}",
    ),
  )
  assert_true(mapping.body.contains("\"primary_identity\":\"$id\""))
  assert_true(
    mapping.body.contains(
      "\"effect_kind\":\"update\",\"permissions\":[\"kintone:records:update\"],\"selector_class\":\"id\"",
    ),
  )
  assert_eq(mapping.write_fields, ["Subject", "Tags"])
  assert_true(record_update_mapping_matches_declaration(owned, original))
  assert_false(
    record_update_mapping_matches_declaration(
      owned,
      update_mapping_declaration(catalog),
    ),
  )
  let request = update_mapping_request(catalog)
  assert_true(record_update_mapping_matches_request(owned, request))
  assert_eq(
    @catalog.record_update_request_body(request),
    "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"Subject\":{\"value\":\"next\"},\"Tags\":{\"value\":[\"東京\",\"red\",\"東京\"]}},\"revision\":\"9\"}],\"upsert\":false}",
  )
}

///|
test "kintone UPDATE Mapping refuses foreign Form incomplete original page and omitted mapped field" {
  let catalog = update_mapping_form()
  let owned = prepare_record_update_mapping(
    update_mapping_declaration(catalog),
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(update_mapping_form()),
    ),
  )
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, fields=["Subject", "Tags"]),
    ),
  )
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, write_tags=false),
    ),
  )
}

///|
test "kintone UPDATE Mapping uses original write evidence rather than readable computed or identity fields" {
  let original = update_mapping_declaration(update_mapping_form())
  for field in ["Computed", "$id", "RecordNumber", "unknown"] {
    assert_true(
      prepare_record_update_mapping(
        original,
        "inquiries",
        [{ target: field, field: "value", null_behavior: "reject", }],
        "required",
        delete_declaration_limits(),
      )
      is Err(FieldNotWritable(_)),
    )
  }
  assert_true(
    prepare_record_update_mapping(
      original,
      "other",
      update_mapping_sources(),
      "required",
      delete_declaration_limits(),
    )
    is Err(_),
  )
  assert_true(
    prepare_record_update_mapping(
      original,
      "inquiries",
      update_mapping_sources(),
      "default",
      delete_declaration_limits(),
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_record_update_mapping(
      original,
      "inquiries",
      [{ target: "Tags", field: "tags", null_behavior: "write_null", }],
      "required",
      delete_declaration_limits(),
    )
    is Err(InvalidNullBehavior("Tags")),
  )
}

///|
test "kintone UPDATE Mapping requires exact written fields with only explicit omission" {
  let catalog = update_mapping_form()
  let original = update_mapping_declaration(catalog)
  let subject = prepare_record_update_mapping(
    original,
    "inquiries",
    [update_mapping_sources()[0]],
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_false(
    record_update_mapping_matches_request(
      subject,
      update_mapping_request(catalog),
    ),
  )
  let omit = prepare_record_update_mapping(
    original,
    "inquiries",
    [
      update_mapping_sources()[0],
      { target: "Tags", field: "originalTags", null_behavior: "omit", },
    ],
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_true(
    record_update_mapping_matches_request(
      omit,
      update_mapping_request(catalog, write_tags=false),
    ),
  )
}
