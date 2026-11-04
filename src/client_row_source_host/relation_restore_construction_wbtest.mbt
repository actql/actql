///|
fn relation_restore_test_inventory(
  schemas : Array[String],
  requests? : Array[String?] = [],
  facts? : Array[String?] = [],
  acquisitions? : Array[String?] = [],
  identities? : Array[String?] = [],
) -> @execution.PreparationRepresentationUnits? {
  let count = schemas.length()
  let empty : Array[String?] = Array::make(count, None)
  relation_restore_construction_inventory(
    "restored",
    "fixture",
    "fixture/0.1",
    "{\"views\":[]}",
    Array::make(count, "records"),
    Array::make(count, "relation"),
    schemas,
    if requests.is_empty() {
      empty
    } else {
      requests
    },
    if facts.is_empty() {
      empty
    } else {
      facts
    },
    if acquisitions.is_empty() {
      empty
    } else {
      acquisitions
    },
    if identities.is_empty() {
      empty
    } else {
      identities
    },
  )
}

///|
test "full Relation restore inventory sums actual simultaneous views and exports" {
  let schema = saved_relation_view().schema_wire
  let one = relation_restore_test_inventory([schema]).unwrap()
  let two = relation_restore_test_inventory([schema, schema]).unwrap()
  assert_true(two.record_headers > one.record_headers)
  assert_true(two.reference_slots > one.reference_slots)
  assert_true(two.owned_utf16_units > one.owned_utf16_units)
  assert_true(two.owned_wire_bytes > one.owned_wire_bytes)
  // Independent initial/final/physical calls remain co-held, not one maximum.
  let retained = @execution.compose_preparation_representation([one, two, one]).unwrap()
  assert_eq(
    retained.record_headers,
    2L * one.record_headers + two.record_headers,
  )
  assert_eq(
    retained.owned_utf16_units,
    2L * one.owned_utf16_units + two.owned_utf16_units,
  )
}

///|
test "full Relation restore inventories nested request acquisition identity and facts separately" {
  let schema = saved_relation_view().schema_wire
  let one = relation_restore_test_inventory([schema]).unwrap()
  for
    richer in [
      relation_restore_test_inventory([schema], requests=[
        Some(
          "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"ids\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}}}",
        ),
      ]),
      relation_restore_test_inventory([schema], facts=[
        Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
      ]),
      relation_restore_test_inventory([schema], acquisitions=[
        Some(
          "{\"kind\":\"lookup\",\"authority\":\"read_content\",\"correlation\":{\"mode\":\"keyed\"}}",
        ),
      ]),
      relation_restore_test_inventory([schema], identities=[
        Some(
          "{\"resource_kind\":\"file\",\"provider_id_field\":\"id\",\"output_field\":\"resource\"}",
        ),
      ]),
    ] {
    let richer = richer.unwrap()
    assert_true(richer.record_headers > one.record_headers)
    assert_true(richer.reference_slots > one.reference_slots)
    assert_true(richer.owned_utf16_units > one.owned_utf16_units)
  }
}

///|
test "restore quote scans original UTF8 and syntax without parsing or admitting" {
  let unicode = relation_restore_wire_geometry("{\"text\":\"雪😀\"}").unwrap()
  assert_true(unicode.bytes > unicode.units)
  assert_true(unicode.nodes >= 2)
  assert_eq(unicode.depth, 1)
  // Invalid syntax still has a finite failure-prefix inventory. It cannot
  // become an admitted schema, Catalog or Source merely by being quoted.
  let invalid = "{\"unfinished\":["
  assert_true(relation_restore_test_inventory([invalid]) is Some(_))
  assert_true(
    restore_relation_row_declaration(
      "restored",
      "fixture",
      "fixture/0.1",
      invalid,
      None,
    )
    is Err(_),
  )
  assert_true(
    relation_restore_wire_geometry("x".repeat(declaration_limits.max_bytes + 1))
    is None,
  )
}

///|
test "full restore quote rejects inconsistent arrays and empty view descriptions" {
  let schema = saved_relation_view().schema_wire
  assert_true(relation_restore_test_inventory([]) is None)
  assert_true(
    relation_restore_test_inventory([schema], facts=[None, None]) is None,
  )
  assert_true(
    relation_restore_construction_inventory(
      "restored",
      "fixture",
      "fixture/0.1",
      "{\"views\":[]}",
      ["records"],
      [],
      [schema],
      [None],
      [None],
      [None],
      [None],
    )
    is None,
  )
  assert_true(
    relation_restore_construction_inventory(
      "restored",
      "fixture",
      "fixture/0.1",
      "{\"views\":[]}",
      ["x".repeat(256)],
      ["relation"],
      [schema],
      [None],
      [None],
      [None],
      [None],
    )
    is None,
  )
}

///|
test "full Relation quote accompanies actual multiple-view restore without replacing declarations" {
  let view = saved_relation_view()
  let views : Json = {
    "views": [
      {
        "resource": "first",
        "resource_kind": "relation",
        "schema_wire": view.schema_wire,
        "schema_cid": view.schema_cid,
      },
      {
        "resource": "second",
        "resource_kind": "relation",
        "schema_wire": view.schema_wire,
        "schema_cid": view.schema_cid,
        "facts_wire": "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
      },
    ],
  }
  let wire = views.stringify()
  let inventory = relation_restore_construction_inventory(
    "restored",
    "fixture",
    "fixture/0.1",
    wire,
    ["first", "second"],
    ["relation", "relation"],
    [view.schema_wire, view.schema_wire],
    [None, None],
    [None, Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}")],
    [None, None],
    [None, None],
  ).unwrap()
  let declaration = restore_relation_row_declaration(
    "restored",
    "fixture",
    "fixture/0.1",
    wire,
    None,
  ).unwrap()
  assert_eq(declaration.views.length(), 2)
  assert_eq(declaration.contracts.length(), 10)
  assert_true(
    inventory.owned_utf16_units > declaration.catalog.length().to_int64(),
  )
  assert_true(
    @execution.preparation_representation_cost(inventory).unwrap() >
    inventory.owned_wire_bytes,
  )
}

///|
test "oversized schema field admission is funded before the output field limit refuses" {
  let entries : Array[(String, Json)] = []
  for index in 0..<1025 {
    entries.push(
      ("f" + index.to_string(), { "nullable": false, "type": "string" }),
    )
  }
  let schema = object(entries).stringify()
  let geometry = relation_restore_wire_geometry(schema).unwrap()
  assert_true(geometry.nodes > 1024)
  let inventory = relation_restore_test_inventory([schema]).unwrap()
  let smaller = relation_restore_test_inventory([
    saved_relation_view().schema_wire,
  ]).unwrap()
  assert_true(inventory.record_headers > smaller.record_headers)
  assert_true(inventory.reference_slots > smaller.reference_slots)
  // Fixed independent SHA-256 of sorted f0..f1024 field-map JSON, not derived
  // from the production constructor whose rejection this regression checks.
  let wire = (
    {
      "views": [
        {
          "resource": "records",
          "resource_kind": "relation",
          "schema_wire": schema,
          "schema_cid": "sha256:9619d0e732c9c43d1658c98d4240f0144632aa4440504d902f4348bb23fe7cb4",
        },
      ],
    } : Json).stringify()
  assert_true(
    restore_relation_row_declaration(
      "restored",
      "fixture",
      "fixture/0.1",
      wire,
      None,
    )
    is Err(InvalidSpecification),
  )
  assert_true(relation_restore_scale(inventory, -1L) is None)
  assert_true(relation_restore_scale(inventory, 9223372036854775807L) is None)
}

///|
test "restore quantity scaling preserves zero components and checked overflow" {
  let value : @execution.PreparationRepresentationUnits = {
    record_headers: 3L,
    reference_slots: 0L,
    scalar_words: 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let scaled = relation_restore_scale(value, 2L).unwrap()
  assert_eq(scaled.record_headers, 6L)
  assert_eq(scaled.reference_slots, 0L)
  assert_eq(scaled.scalar_words, 4L)
  assert_eq(scaled.owned_utf16_units, 0L)
  assert_eq(scaled.owned_wire_bytes, 0L)
  assert_true(
    relation_restore_scale(value, 0L).unwrap() ==
    @execution.compose_preparation_representation([]).unwrap(),
  )
  assert_true(relation_restore_scale(value, -1L) is None)
  assert_true(relation_restore_scale(value, 9223372036854775807L) is None)
}

///|
test "restore validators add one whole generated rule per acquisition and optional identity" {
  let geometry = relation_restore_wire_geometry("{\"kind\":\"scan\"}").unwrap()
  let validator = relation_restore_shape_validator(geometry).unwrap()
  let original = @environment.source_view_shape_validation_construction_extent(
    geometry.nodes,
    geometry.nodes,
    geometry.nodes,
    geometry.depth,
  ).unwrap()
  assert_true(validator == relation_construction_collection_units(original))
  assert_true(validator.record_headers >= 530L)
  let schema = saved_relation_view().schema_wire
  let one = relation_restore_test_inventory([schema]).unwrap()
  let with_identity = relation_restore_test_inventory([schema], identities=[
    Some(
      "{\"resource_kind\":\"file\",\"provider_id_field\":\"id\",\"output_field\":\"resource\"}",
    ),
  ]).unwrap()
  assert_true(with_identity.record_headers >= one.record_headers + 530L)
  assert_true(with_identity.reference_slots >= one.reference_slots + 2095L)
  assert_true(with_identity.scalar_words >= one.scalar_words + 476L)
}
