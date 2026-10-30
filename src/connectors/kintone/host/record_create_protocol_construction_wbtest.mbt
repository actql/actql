///|
fn create_protocol_form_limits() -> @catalog.FormFieldLimits {
  {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_fields: 16,
    max_name_units: 512,
  }
}

///|
test "original CREATE Form recheck inventory covers nested options lookup and narrower foreign response" {
  let wire = "{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true},\"Tags\":{\"code\":\"Tags\",\"type\":\"MULTI_SELECT\",\"options\":{\"red\":{\"label\":\"red\"}}},\"Optional\":{\"code\":\"Optional\",\"type\":\"MULTI_LINE_TEXT\"},\"Computed\":{\"code\":\"Computed\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"server\"},\"nested\":{\"code\":\"nested\",\"type\":\"SUBTABLE\",\"fields\":{\"lookup\":{\"code\":\"lookup\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"lookup\":{\"fieldMappings\":[{\"field\":\"Optional\",\"relatedField\":\"source\"}]}}}}}}"
  let limits = create_protocol_form_limits()
  let catalog = @catalog.project_form_fields(@utf8.encode(wire), "12", limits).unwrap()
  let mapping = prepare_record_create_mapping(
    create_mapping_declaration(catalog),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let request = prepare_record_create_execution_request(
    mapping,
    b"[{\"Subject\":\"intended\",\"Tags\":[\"red\"]}]",
    8192,
    create_construction_write(16),
    create_construction_request(),
  ).unwrap()
  let q = record_create_mapped_form_recheck_construction_inventory(
    mapping, limits,
  ).unwrap()
  assert_true(q.representation.record_headers > 0L)
  assert_true(q.representation.reference_slots > 0L)
  assert_true(q.owned_wire_bytes > 0L)
  assert_true(
    record_create_mapped_form_recheck_construction_capacity(mapping, limits)
    is Some(_),
  )
  assert_true(
    @catalog.recheck_record_create_form(request, @utf8.encode(wire), limits)
    is Ok(_),
  )
  assert_true(
    @catalog.recheck_record_create_form(
      request,
      @utf8.encode(wire.replace(old="source", new="changed")),
      limits,
    )
    is Err(@catalog.ForeignCatalog),
  )
  // No original path snapshots are made. A narrow observed Form is decoded
  // under its own limits, then refused against ALL original metadata.
  let narrow = { ..limits, max_fields: 1, }
  assert_true(
    record_create_mapped_form_recheck_construction_inventory(mapping, narrow)
    is Some(_),
  )
  assert_true(
    @catalog.recheck_record_create_form(
      request, b"{\"revision\":\"7\",\"properties\":{}}", narrow,
    )
    is Err(@catalog.ForeignCatalog),
  )
  assert_true(
    record_create_mapped_form_recheck_construction_inventory(mapping, {
      ..limits,
      max_nodes: 2147483647,
      max_fields: 2147483647,
      max_depth: 2147483647,
    })
    is None,
  )
}

///|
test "original one-row CREATE response inventory keeps wide refusal prefix and exact acknowledgement outcome" {
  let mapping = prepare_record_create_mapping(
    create_mapping_declaration(create_mapping_catalog()),
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let limits = create_construction_request()
  let q = record_create_mapped_response_construction_inventory(mapping, limits).unwrap()
  let small = record_create_mapped_response_construction_inventory(mapping, {
    ..limits,
    max_output_nodes: 2,
  }).unwrap()
  assert_true(
    q.representation.reference_slots > small.representation.reference_slots,
  )
  assert_true(q.owned_utf16_units > 0L)
  assert_true(
    record_create_mapped_response_construction_capacity(mapping, limits)
    is Some(_),
  )
  let request = prepare_record_create_execution_request(
    mapping,
    b"[{\"Subject\":\"intended\",\"Tags\":[\"red\"]}]",
    8192,
    create_construction_write(16),
    limits,
  ).unwrap()
  let response = @catalog.project_record_create_acknowledgement(
    request, 200, b"{\"ids\":[\"9007199254740993\"],\"revisions\":[\"0009007199254740994\"]}",
    limits,
  ).unwrap()
  let outcome = @catalog.project_record_create_effect_outcome(
    request, response, limits,
  ).unwrap()
  assert_eq(
    @catalog.record_create_effect_outcome_wire(outcome),
    "{\"result\":{\"created\":true,\"record_id\":\"9007199254740993\",\"revision\":\"0009007199254740994\"},\"state\":\"applied\"}",
  )
  assert_true(
    @catalog.project_record_create_acknowledgement(
      request, 200, b"{\"ids\":[\"1\"],\"revisions\":[\"2\"],\"a\":1,\"b\":2,\"c\":3,\"d\":4}",
      limits,
    )
    is Err(@catalog.UncorrelatedResult),
  )
  let copied : RecordCreateMapping = { ..mapping, }
  assert_true(
    record_create_mapped_response_construction_inventory(copied, limits) is None,
  )
  assert_true(
    record_create_mapped_response_construction_inventory(mapping, {
      ..limits,
      max_records: 100,
    })
    is None,
  )
}
