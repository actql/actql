///|
fn create_mapping_catalog() -> @catalog.FormFieldCatalog {
  @catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true,\"defaultValue\":\"server\"},\"Tags\":{\"code\":\"Tags\",\"type\":\"MULTI_SELECT\",\"required\":false,\"defaultValue\":[\"server\"]},\"Optional\":{\"code\":\"Optional\",\"type\":\"MULTI_LINE_TEXT\",\"required\":false,\"defaultValue\":\"server\"},\"Computed\":{\"code\":\"Computed\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\\\"server\\\"\",\"required\":true}}}",
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
fn create_mapping_declaration(
  catalog : @catalog.FormFieldCatalog,
) -> RecordDeclaration {
  declare_records(
    catalog,
    None,
    ["Subject", "Tags", "Optional", "Computed"],
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
fn create_mapping_sources() -> Array[@rows.RowMappingSource] {
  [
    { target: "Subject", field: "originalSubject", null_behavior: "reject", },
    { target: "Tags", field: "originalTags", null_behavior: "omit", },
  ]
}

///|
fn create_mapping_request(
  catalog : @catalog.FormFieldCatalog,
  fields : Array[String],
) -> @catalog.RecordCreateRequest {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let cells = fields.map(name => {
    let value = if name == "Tags" {
      @admitted.recheck_runtime_value(
        @admitted.array_value([
          @admitted.checked_text_value("東京", text).unwrap().value,
          @admitted.checked_text_value("東京", text).unwrap().value,
        ]),
        @contract.array_contract(text, nullable=false).unwrap(),
        { max_nodes: 1000, max_depth: 16, max_text_bytes: 8192, },
      ).unwrap()
    } else {
      @admitted.checked_text_value("requested", text).unwrap()
    }
    (name, value)
  })
  let values = @catalog.prepare_record_write_values(catalog, cells, {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }).unwrap()
  @catalog.prepare_record_create_request(catalog, [values], {
    max_records: 100,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 8192,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }).unwrap()
}

///|
test "kintone CREATE Mapping retains original required evidence Array Contract and request" {
  let catalog = create_mapping_catalog()
  let original = create_mapping_declaration(catalog)
  let owned = prepare_record_create_mapping(
    original,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let mapping = record_create_mapping(owned)
  assert_true(mapping.body.contains("\"required_fields\":[\"Subject\"]"))
  assert_true(mapping.body.contains("\"effect_kind\":\"create\""))
  assert_true(mapping.body.contains("\"selector_class\":\"none\""))
  assert_true(mapping.body.contains("\"type\":\"array\""))
  assert_true(record_create_mapping_matches_declaration(owned, original))
  assert_true(
    !record_create_mapping_matches_declaration(
      owned,
      create_mapping_declaration(catalog),
    ),
  )
  let request = create_mapping_request(catalog, ["Subject", "Tags"])
  assert_true(record_create_mapping_matches_request(owned, request))
  assert_eq(
    @catalog.record_create_request_body(request),
    "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"requested\"},\"Tags\":{\"value\":[\"東京\",\"東京\"]}}]}",
  )
}

///|
test "kintone CREATE does not use provider defaults to replace required sources" {
  let original = create_mapping_declaration(create_mapping_catalog())
  assert_true(
    prepare_record_create_mapping(
      original,
      "inquiries",
      [{ target: "Tags", field: "tags", null_behavior: "reject", }],
      "required",
      delete_declaration_limits(),
    )
    is Err(MissingRequiredField("Subject")),
  )
  assert_true(
    prepare_record_create_mapping(
      original,
      "inquiries",
      [{ target: "Subject", field: "subject", null_behavior: "omit", }],
      "required",
      delete_declaration_limits(),
    )
    is Err(InvalidNullBehavior("Subject")),
  )
}

///|
test "kintone CREATE omission is explicit and foreign or extra writes do not correspond" {
  let catalog = create_mapping_catalog()
  let owned = prepare_record_create_mapping(
    create_mapping_declaration(catalog),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let omitted = create_mapping_request(catalog, ["Subject"])
  assert_true(record_create_mapping_matches_request(owned, omitted))
  assert_eq(
    @catalog.record_create_request_body(omitted),
    "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"requested\"}}]}",
  )
  assert_true(
    !record_create_mapping_matches_request(
      owned,
      create_mapping_request(catalog, ["Tags"]),
    ),
  )
  assert_true(
    !record_create_mapping_matches_request(
      owned,
      create_mapping_request(catalog, ["Subject", "Optional"]),
    ),
  )
  assert_true(
    !record_create_mapping_matches_request(
      owned,
      create_mapping_request(create_mapping_catalog(), ["Subject"]),
    ),
  )
}

///|
test "escaped CREATE Mapping metadata cannot weaken original required or intended fields" {
  let catalog = create_mapping_catalog()
  let owned = prepare_record_create_mapping(
    create_mapping_declaration(catalog),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let mapping = record_create_mapping(owned)
  mapping.write_fields.clear()
  mapping.omittable.push("Subject")
  assert_true(
    !record_create_mapping_matches_request(
      owned,
      create_mapping_request(catalog, ["Tags"]),
    ),
  )
  assert_true(
    record_create_mapping_matches_request(
      owned,
      create_mapping_request(catalog, ["Subject"]),
    ),
  )
}
