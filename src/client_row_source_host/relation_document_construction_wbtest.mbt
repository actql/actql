///|
fn relation_document_construction_test_limits() -> RowPageLimits {
  { max_bytes: 512, max_nodes: 32, max_depth: 8, max_rows: 4, }
}

///|
fn relation_document_construction_test_projection(
  child : @contract.Contract,
) -> RelationDocumentProjectionConstruction {
  {
    original: @contract.object_contract(
      [
        ("id", @contract.primitive(@contract.StringType, nullable=false)),
        ("value", child),
      ],
      nullable=false,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap(),
    items_path_depth: 2,
    key_path_depth: Some(1),
    writable_fields: 1,
  }
}

///|
test "relation document inventory shares raw backing and sums every simultaneous projection" {
  let limits = relation_document_construction_test_limits()
  let text = relation_document_construction_test_projection(
    @contract.primitive(@contract.StringType, nullable=true),
  )
  let nested = relation_document_construction_test_projection(
    @contract.array_contract(
      @contract.primitive(@contract.Signed64Type, nullable=false),
      nullable=false,
    ).unwrap(),
  )
  let raw = relation_document_raw_construction_inventory(limits).unwrap()
  let mapping = relation_document_mapping_construction_inventory(limits).unwrap()
  let first = relation_document_projection_construction_inventory(text, limits).unwrap()
  let second = relation_document_projection_construction_inventory(
    nested, limits,
  ).unwrap()
  assert_true(
    relation_document_construction_inventory(limits, []).unwrap() == raw,
  )
  assert_true(
    relation_document_construction_inventory(limits, [text, nested]).unwrap() ==
    @execution.compose_preparation_representation([
      raw, mapping, first, mapping, second,
    ]).unwrap(),
  )
  assert_true(
    relation_document_construction_inventory(limits, [text, text]).unwrap() ==
    @execution.compose_preparation_representation([
      raw, mapping, first, mapping, first,
    ]).unwrap(),
  )
  let one = relation_document_construction_inventory(limits, [text]).unwrap()
  let both = relation_document_construction_inventory(limits, [text, nested]).unwrap()
  assert_true(both.record_headers > one.record_headers)
  assert_true(both.reference_slots > one.reference_slots)
  assert_true(both.scalar_words > one.scalar_words)
  // Copied original bytes counted once; mapping probes are independent copies.
  assert_true(raw.owned_wire_bytes == limits.max_bytes.to_int64())
  assert_true(
    both.owned_wire_bytes ==
    raw.owned_wire_bytes + 2L * mapping.owned_wire_bytes,
  )
}

///|
test "relation document inventory refuses unsupported fields even inside nested checked contracts" {
  let limits = relation_document_construction_test_limits()
  let json = @contract.primitive(@contract.JsonType, nullable=true)
  let vector = @contract.vector_contract(2.0, nullable=false).unwrap()
  let reference = @contract.content_reference_contract(
    Some("text/plain"),
    nullable=false,
    max_name_bytes=100,
  ).unwrap()
  for
    unsupported in [
      json,
      vector,
      reference,
      @contract.array_contract(json, nullable=false).unwrap(),
    ] {
    let projection = relation_document_construction_test_projection(unsupported)
    assert_true(
      relation_document_projection_construction_inventory(projection, limits) ==
      None,
    )
    assert_true(
      relation_document_construction_inventory(limits, [projection]) == None,
    )
    assert_true(
      relation_document_construction_inventory({ ..limits, max_rows: 0, }, [
        projection,
      ]) ==
      None,
    )
  }
}

///|
test "relation document inventory validates bounds paths and checked composition overflow" {
  let limits = relation_document_construction_test_limits()
  let projection = relation_document_construction_test_projection(
    @contract.primitive(@contract.BooleanType, nullable=false),
  )
  for
    invalid in [
      { ..limits, max_bytes: 0, },
      { ..limits, max_nodes: 0, },
      { ..limits, max_depth: 0, },
      { ..limits, max_rows: -1, },
    ] {
    assert_true(relation_document_raw_construction_inventory(invalid) == None)
    assert_true(
      relation_document_mapping_construction_inventory(invalid) == None,
    )
    assert_true(
      relation_document_construction_inventory(invalid, [projection]) == None,
    )
  }
  for
    invalid in [
      { ..projection, items_path_depth: -1, },
      { ..projection, items_path_depth: limits.max_depth + 1, },
      { ..projection, key_path_depth: Some(-1), },
      { ..projection, key_path_depth: Some(limits.max_depth + 1), },
      { ..projection, writable_fields: -1, },
      { ..projection, writable_fields: limits.max_nodes + 1, },
      {
        ..projection,
        original: @contract.primitive(@contract.StringType, nullable=false),
      },
    ] {
    assert_true(
      relation_document_projection_construction_inventory(invalid, limits) ==
      None,
    )
  }
  let raw = relation_document_raw_construction_inventory(limits).unwrap()
  assert_true(relation_document_construction_scale(raw, -1L) == None)
  assert_true(
    relation_document_construction_scale(raw, 9223372036854775807L) == None,
  )
  assert_true(
    relation_document_projection_construction_inventory(projection, {
      ..limits,
      max_rows: 0,
    })
    is Some(_),
  )
}

///|
test "relation document construction uses cumulative mapping payload and long integer refusal bounds" {
  let limits = relation_document_construction_test_limits()
  let larger = { ..limits, max_bytes: 1024, }
  let integer = relation_document_construction_test_projection(
    @contract.primitive(@contract.Signed64Type, nullable=false),
  )
  let before = relation_document_projection_construction_inventory(
    integer, limits,
  ).unwrap()
  let after = relation_document_projection_construction_inventory(
    integer, larger,
  ).unwrap()
  assert_true(after.owned_utf16_units > before.owned_utf16_units)
  let mapping = relation_document_mapping_construction_inventory(limits).unwrap()
  let doubled = relation_document_mapping_construction_inventory({
    max_bytes: 1024,
    max_nodes: 64,
    max_depth: 8,
    max_rows: 4,
  }).unwrap()
  // Affine cumulative payload + call controls, not N full copies of payload.
  assert_true(doubled.record_headers < 3L * mapping.record_headers)
  assert_true(doubled.reference_slots < 3L * mapping.reference_slots)
  assert_true(doubled.scalar_words < 3L * mapping.scalar_words)
  assert_true(doubled.owned_utf16_units < 3L * mapping.owned_utf16_units)
}

///|
test "relation document projection metadata uses original declared mapping and refuses foreign resource" {
  let declaration = relation_mapping_declaration()
  let limits = relation_document_test_limits()
  assert_true(
    relation_document_mapping_construction_inventory(limits) is Some(_),
  )
  let original = relation_document_projection_contract(
    declaration, "records", "id", limits,
  ).unwrap()
  let (_, expected) = mapping_original_relation(declaration, "records", "id", {
    max_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_views: limits.max_nodes,
    max_fields: limits.max_nodes,
  }).unwrap()
  assert_true(@contract.type_equal(original, expected, limits.max_nodes))
  assert_true(
    relation_document_projection_contract(
      declaration, "missing-resource", "id", limits,
    )
    is Err(_),
  )
  assert_true(
    relation_document_projection_contract(
      declaration, "records", "missing-identity", limits,
    )
    is Err(_),
  )
  assert_true(
    relation_document_projection_contract(declaration, "records", "id", {
      ..limits,
      max_nodes: 0,
    })
    is Err(InvalidSpecification),
  )
}
