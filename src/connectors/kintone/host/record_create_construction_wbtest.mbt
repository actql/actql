///|
fn create_construction_write(fields : Int) -> @catalog.RecordWriteLimits {
  {
    max_fields: fields,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }
}

///|
fn create_construction_request() -> @catalog.RecordMutationLimits {
  {
    max_records: 1,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 8192,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }
}

///|
test "mapped CREATE inventory covers real native constructor and unmapped-field refusal prefix" {
  let original = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    original,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let write = create_construction_write(16)
  let request_limits = create_construction_request()
  let inventory = record_create_mapped_request_construction_inventory(
    mapping, 8192, write, request_limits,
  ).unwrap()
  let smaller = record_create_mapped_request_construction_inventory(
    mapping,
    8192,
    create_construction_write(2),
    request_limits,
  ).unwrap()
  // Identical Mapping; the native constructor may reach additional admitted
  // fields before its final Mapping comparison refuses. Never price just the
  // Mapping's two intended fields as the whole constructor's field ceiling.
  assert_true(
    inventory.representation.record_headers >
    smaller.representation.record_headers,
  )
  assert_true(
    inventory.representation.reference_slots >
    smaller.representation.reference_slots,
  )
  assert_true(
    inventory.representation.scalar_words > smaller.representation.scalar_words,
  )
  assert_true(inventory.owned_utf16_units > 0L)
  let request = prepare_record_create_execution_request(
    mapping, b"[{\"Subject\":\"requested 東京\",\"Tags\":[\"red\",\"red\"]}]",
    8192, write, request_limits,
  ).unwrap()
  assert_true(record_create_mapping_matches_request(mapping, request))
  assert_eq(
    @catalog.record_create_request_values_json(request, 8192, 1000, 16).unwrap(),
    "[{\"Subject\":\"requested 東京\",\"Tags\":[\"red\",\"red\"]}]",
  )
  assert_true(
    prepare_record_create_execution_request(
      mapping, b"[{\"Subject\":\"requested 東京\",\"Tags\":[\"red\"],\"Optional\":\"unmapped\"}]",
      8192, write, request_limits,
    )
    is Err(MappingMismatch),
  )
  assert_eq(@catalog.form_field_count(original.catalog), 4)
  assert_true(
    @catalog.record_write_field_contract_at(original.catalog, -1) is None,
  )
  assert_true(
    @catalog.record_write_field_contract_at(original.catalog, 4) is None,
  )
  assert_true(
    @catalog.record_write_field_contract_at(original.catalog, 3) is None,
  )
}

///|
test "CREATE constructor inventory refuses foreign Mapping invalid bounds and batch substitution" {
  let original = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    original,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let copied : RecordCreateMapping = { ..mapping, }
  let write = create_construction_write(16)
  let request = create_construction_request()
  assert_true(
    record_create_mapped_request_construction_inventory(
      copied, 8192, write, request,
    )
    is None,
  )
  assert_true(
    record_create_mapped_request_construction_inventory(
      mapping, 0, write, request,
    )
    is None,
  )
  assert_true(
    record_create_mapped_request_construction_inventory(
      mapping,
      8192,
      create_construction_write(1),
      request,
    )
    is None,
  )
  assert_true(
    record_create_mapped_request_construction_inventory(
      mapping,
      8192,
      { ..write, max_nodes: 2147483647, },
      request,
    )
    is None,
  )
  assert_true(
    record_create_mapped_request_construction_inventory(mapping, 8192, write, {
      ..request,
      max_records: 100,
    })
    is None,
  )
}
