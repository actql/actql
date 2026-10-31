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

///|
fn restore_create_mapping() -> RecordCreateMapping {
  prepare_record_create_mapping(
    create_mapping_declaration(create_mapping_catalog()),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
}

///|
test "cold CREATE retains complete original saved body and checked values under same Mapping" {
  let mapping = restore_create_mapping()
  let saved = "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"next 東京\"},\"Tags\":{\"value\":[\"red\",\"red\"]}}]}"
  let restored = restore_record_create_execution_request(
    mapping,
    b"[{\"Subject\":\"next 東京\",\"Tags\":[\"red\",\"red\"]}]",
    saved,
    8192,
    create_construction_write(16),
    create_construction_request(),
  ).unwrap()
  assert_true(record_create_mapping_matches_request(mapping, restored))
  assert_eq(@catalog.record_create_request_body(restored), saved)
  assert_eq(
    @catalog.record_create_request_values_json(restored, 8192, 1000, 16).unwrap(),
    "[{\"Subject\":\"next 東京\",\"Tags\":[\"red\",\"red\"]}]",
  )
  let acknowledgement = @catalog.project_record_create_acknowledgement(
    restored,
    200,
    b"{\"ids\":[\"9007199254740993\"],\"revisions\":[\"0007\"]}",
    create_construction_request(),
  ).unwrap()
  assert_true(
    physical_equal(
      @catalog.record_create_acknowledgement_request(acknowledgement),
      restored,
    ),
  )
}

///|
test "cold CREATE refuses changed spelling app rows and complete saved body" {
  let mapping = restore_create_mapping()
  let values = b"[{\"Subject\":\"x\",\"Tags\":[\"a\",\"b\"]}]"
  for
    body in [
      "{\"app\":\"13\",\"records\":[{\"Subject\":{\"value\":\"x\"},\"Tags\":{\"value\":[\"a\",\"b\"]}}]}",
      " {\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"x\"},\"Tags\":{\"value\":[\"a\",\"b\"]}}]}",
      "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"x\"},\"Tags\":{\"value\":[\"b\",\"a\"]}}]}",
      "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"x\"},\"Tags\":{\"value\":[\"a\",\"b\"]}}],\"extra\":true}",
      "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"x\"},\"Tags\":{\"value\":[\"a\",\"b\"]}},{\"Subject\":{\"value\":\"x\"}}]}",
      "{\"app\":\"12\",\"records\":[]}",
    ] {
    assert_true(
      restore_record_create_execution_request(
        mapping,
        values,
        body,
        8192,
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(Catalog(Request(InvalidRequest))),
    )
  }
}

///|
test "cold CREATE keeps Mapping typed value and independent comparison bounds refusals" {
  let mapping = restore_create_mapping()
  let body = "{\"app\":\"12\",\"records\":[{\"Subject\":{\"value\":\"x\"}}]}"
  let values = b"[{\"Subject\":\"x\"}]"
  let copied : RecordCreateMapping = { ..mapping, }
  assert_true(
    restore_record_create_execution_request(
      copied,
      values,
      body,
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(MappingMismatch),
  )
  assert_true(
    restore_record_create_execution_request(
      mapping,
      b"[{\"Subject\":123}]",
      body,
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(Catalog(Write(InvalidValue("Subject")))),
  )
  assert_true(
    restore_record_create_execution_request(
      mapping,
      b"[{\"Optional\":\"x\"}]",
      "{\"app\":\"12\",\"records\":[{\"Optional\":{\"value\":\"x\"}}]}",
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(MappingMismatch),
  )
  assert_true(
    restore_record_create_execution_request(
      mapping,
      values,
      body,
      values.length() - 1,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(Catalog(BudgetExceeded)),
  )
  assert_true(
    restore_record_create_execution_request(
      mapping,
      values,
      body,
      8192,
      create_construction_write(16),
      { ..create_construction_request(), max_output_bytes: body.length() - 1, },
    )
    is Err(Catalog(BudgetExceeded)),
  )
  assert_true(
    restore_record_create_execution_request(
      mapping,
      values,
      "mismatch",
      8192,
      create_construction_write(16),
      { ..create_construction_request(), max_output_nodes: 1, },
    )
    is Err(Catalog(Request(BudgetExceeded))),
  )
}

///|
test "original CREATE proposal ingress rejects foreign envelopes without an encoder fallback" {
  let mapping = restore_create_mapping()
  for
    wire in [
      "[]", "{\"value\":{\"Subject\":\"x\"}}", "{\"state\":\"absent\",\"value\":{\"Subject\":\"x\"}}",
      "{\"state\":\"present\",\"value\":{\"Subject\":\"x\"},\"extra\":true}", "{\"state\":\"present\",\"value\":[{\"Subject\":\"x\"}]}",
    ] {
    assert_true(
      prepare_record_create_execution_proposal(
        mapping,
        @utf8.encode(wire),
        8192,
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(Catalog(InvalidRecords)),
    )
  }
  assert_true(
    prepare_record_create_execution_proposal(
      mapping,
      b"{\"state\":\"present\",\"value\":{\"Subject\":42}}",
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(Catalog(Write(InvalidValue("Subject")))),
  )
}

///|
test "original CREATE proposal ingress checks independent input body and Mapping bounds" {
  let mapping = restore_create_mapping()
  let wire = b"{\"state\":\"present\",\"value\":{\"Subject\":\"東京\"}}"
  assert_true(
    prepare_record_create_execution_proposal(
      mapping,
      wire,
      wire.length() - 1,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(Catalog(BudgetExceeded)),
  )
  let copied : RecordCreateMapping = { ..mapping, }
  assert_true(
    prepare_record_create_execution_proposal(
      copied,
      wire,
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(MappingMismatch),
  )
  assert_true(record_create_mapping_resource(copied) is Err(MappingMismatch))
  assert_eq(record_create_mapping_resource(mapping), Ok("inquiries"))
  assert_true(
    restore_record_create_execution_proposal(
      mapping,
      wire,
      "{\"app\":\"12\",\"records\":[]}",
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(Catalog(Request(InvalidRequest))),
  )
  assert_true(
    prepare_record_create_execution_proposal(
      mapping,
      wire,
      8192,
      create_construction_write(16),
      { ..create_construction_request(), max_output_bytes: 5, },
    )
    is Err(Catalog(Request(BudgetExceeded))),
  )
}
