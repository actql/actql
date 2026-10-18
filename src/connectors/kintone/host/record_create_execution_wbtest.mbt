///|
test "mapped CREATE execution retains same Form required fields and omitted optionals" {
  let catalog = create_mapping_catalog()
  let mapping = prepare_record_create_mapping(
    create_mapping_declaration(catalog),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let request = prepare_record_create_execution_request(
    mapping,
    b"[{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]},{\"Subject\":\"second\"}]",
    8192,
    {
      max_fields: 16,
      max_name_bytes: 512,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
      max_output_bytes: 8192,
    },
    {
      max_records: 100,
      max_identity_bytes: 1000,
      max_comparison_work: 10000,
      max_output_bytes: 8192,
      max_output_nodes: 1000,
      max_output_depth: 16,
    },
  ).unwrap()
  assert_true(record_create_mapping_matches_request(mapping, request))
  assert_true(
    @catalog.record_write_values_match_catalog(
      @catalog.record_create_request_values(request)[0],
      catalog,
    ),
  )
}

///|
test "mapped CREATE missing required or extra intended fields refuses before exposing a request" {
  let mapping = prepare_record_create_mapping(
    create_mapping_declaration(create_mapping_catalog()),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  for
    wire in ["[{\"Tags\":[]}]", "[{\"Subject\":\"x\",\"Optional\":\"extra\"}]"] {
    assert_true(
      prepare_record_create_execution_request(
        mapping,
        @utf8.encode(wire),
        8192,
        {
          max_fields: 16,
          max_name_bytes: 512,
          max_nodes: 1000,
          max_depth: 16,
          max_text_bytes: 8192,
          max_output_bytes: 8192,
        },
        {
          max_records: 100,
          max_identity_bytes: 1000,
          max_comparison_work: 10000,
          max_output_bytes: 8192,
          max_output_nodes: 1000,
          max_output_depth: 16,
        },
      )
      is Err(MappingMismatch),
    )
  }
}

///|
test "copied CREATE Mapping retaining every original field is not the original" {
  let original = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    original,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let copied : RecordCreateMapping = { ..mapping, }
  let request = create_mapping_request(original.catalog, ["Subject", "Tags"])
  assert_true(record_create_mapping_is_original(mapping))
  assert_false(record_create_mapping_is_original(copied))
  assert_false(record_create_mapping_matches_declaration(copied, original))
  assert_false(record_create_mapping_matches_request(copied, request))
  assert_true(
    prepare_record_create_execution_request(
      copied,
      b"[{\"Subject\":\"x\"}]",
      8192,
      {
        max_fields: 16,
        max_name_bytes: 512,
        max_nodes: 1000,
        max_depth: 16,
        max_text_bytes: 8192,
        max_output_bytes: 8192,
      },
      {
        max_records: 100,
        max_identity_bytes: 1000,
        max_comparison_work: 10000,
        max_output_bytes: 8192,
        max_output_nodes: 1000,
        max_output_depth: 16,
      },
    )
    is Err(MappingMismatch),
  )
}
