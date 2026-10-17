///|
fn delete_mapping_form() -> @catalog.FormFieldCatalog {
  @catalog.project_form_fields(
    @utf8.encode(
      (
        #|{"revision":"7","properties":{"Subject":{"code":"Subject","type":"SINGLE_LINE_TEXT"}}}
      ),
    ),
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
fn delete_declaration_limits() -> @rows.RowDeclarationLimits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
    max_views: 1,
    max_fields: 8,
  }
}

///|
fn delete_original_declaration(
  catalog : @catalog.FormFieldCatalog,
) -> RecordDeclaration {
  declare_records(
    catalog,
    None,
    ["Subject"],
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
fn delete_original_request(
  catalog : @catalog.FormFieldCatalog,
  fields? : Array[String] = ["Subject"],
) -> @catalog.RecordDeleteRequest {
  let page = @catalog.project_record_page(
    @utf8.encode(
      (
        #|{"records":[{"$id":{"type":"__ID__","value":"9007199254740993"},"$revision":{"type":"__REVISION__","value":"9007199254740994"},"Subject":{"type":"SINGLE_LINE_TEXT","value":"original"}}],"totalCount":null}
      ),
    ),
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
  @catalog.prepare_record_delete_request(
    [@catalog.prepare_original_record_target(page, 0, 1000).unwrap()],
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
test "kintone delete Mapping and request retain the same original App Form and API ID" {
  let catalog = delete_mapping_form()
  let original = delete_original_declaration(catalog)
  let owned = prepare_record_delete_mapping(
    original,
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let mapping = record_delete_mapping(owned)
  assert_true(mapping.body.contains("\"primary_identity\":\"$id\""))
  assert_true(
    mapping.body.contains("\"permissions\":[\"kintone:records:delete\"]"),
  )
  assert_true(
    mapping.body.contains("\"target_ref\":\"connector://kintone/inquiries\""),
  )
  assert_true(mapping.body.contains("\"Subject\""))
  assert_true(record_delete_mapping_matches_declaration(owned, original))
  assert_true(
    record_delete_mapping_matches_request(
      owned,
      delete_original_request(catalog),
    ),
  )
  assert_true(
    !record_delete_mapping_matches_declaration(
      owned,
      delete_original_declaration(catalog),
    ),
  )
  assert_true(
    !record_delete_mapping_matches_request(
      owned,
      delete_original_request(delete_mapping_form()),
    ),
  )
  assert_eq(
    @catalog.record_delete_request_body(delete_original_request(catalog)),
    "{\"app\":\"12\",\"ids\":[\"9007199254740993\"],\"revisions\":[\"9007199254740994\"]}",
  )
}

///|
test "kintone delete Mapping refuses a foreign Resource and invalid approval before I O" {
  let original = delete_original_declaration(delete_mapping_form())
  assert_true(
    prepare_record_delete_mapping(
      original,
      "foreign",
      "required",
      delete_declaration_limits(),
    )
    is Err(_),
  )
  assert_true(
    prepare_record_delete_mapping(
      original,
      "inquiries",
      "allow",
      delete_declaration_limits(),
    )
    is Err(_),
  )
}

///|
test "kintone delete Mapping refuses an incomplete original page despite equal App and ID" {
  let catalog = delete_mapping_form()
  let original = delete_original_declaration(catalog)
  let owned = prepare_record_delete_mapping(
    original,
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_true(
    !record_delete_mapping_matches_request(
      owned,
      delete_original_request(catalog, fields=[]),
    ),
  )
}
