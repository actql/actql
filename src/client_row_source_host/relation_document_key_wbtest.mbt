///|
fn ordered_file_target_fixture(reverse? : Bool = false) -> RowDeclaration {
  let fields = if reverse { ["serial", "site"] } else { ["site", "serial"] }
  restore_relation_row_declaration(
    "ordered",
    "fixture",
    "fixture/0.1",
    project_relation_declaration_input(
      {
        "views": [
          {
            "resource": "records",
            "resource_kind": "record",
            "schema": {
              "site": { "type": "string", "nullable": false },
              "serial": { "type": "int64", "nullable": false },
              "label": { "type": "string", "nullable": true },
            },
            "facts": {
              "relation_keys": { "candidate_keys": [fields.to_json()] },
            },
          },
        ],
      },
      65536,
      8192,
      32,
    ).unwrap(),
    None,
  ).unwrap()
}

///|
fn ordered_file_target_wire_key(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(wire, {
      max_input_bytes: 256,
      max_nodes: 8,
      max_depth: 2,
    }).unwrap(),
    {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: 256,
      max_total_string_bytes: 256,
    },
  ).unwrap()
}

///|
test "ordered File key preparation uses only the original fact and schema quote" {
  let limits = relation_document_test_limits()
  let original = ordered_file_target_fixture()
  let selected = relation_document_key_metadata_capacity(
    original, "records", limits, 2,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(selected)
  let e = @execution.execution_capacity_execution_bytes(selected)
  assert_true(r > 0L && e > r)
  let unrelated_export = { ..original, catalog: "x".repeat(100000), }
  let same = relation_document_key_metadata_capacity(
    unrelated_export, "records", limits, 2,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(same), r)
  assert_eq(@execution.execution_capacity_execution_bytes(same), e)
  assert_true(
    relation_document_key_metadata_capacity(original, "foreign", limits, 2)
    is None,
  )
  assert_true(
    relation_document_key_metadata_capacity(original, "records", limits, 1)
    is None,
  )
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: r,
    execution_bytes: e,
  }).unwrap()
  let reservation = @resources.reserve_capacity(ledger, r, e).unwrap()
  let key = prepare_relation_document_key_contract(
    original,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  assert_eq(key.positions.length(), 2)
  @resources.shrink_capacity_reservation(ledger, reservation, r, r).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
  @resources.settle_capacity(ledger, reservation).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "ordered File probe prices both typed fields in either declared order" {
  let limits = relation_document_test_limits()
  let text_first = prepare_relation_document_key_contract(
    ordered_file_target_fixture(),
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let int64_first = prepare_relation_document_key_contract(
    ordered_file_target_fixture(reverse=true),
    "records",
    ["serial", "site"],
    limits,
  ).unwrap()
  let first = relation_target_key_wire_workspace_inventory(text_first, 100).unwrap()
  let second = relation_target_key_wire_workspace_inventory(int64_first, 100).unwrap()
  assert_eq(
    @execution.preparation_representation_cost(first),
    @execution.preparation_representation_cost(second),
  )
}

///|
test "catalog-key File projection retains both adjacent Int64 row values" {
  let limits = relation_document_test_limits()
  let declaration = ordered_file_target_fixture()
  let input =
    #|{"keys":["site","serial"],"records":[{"site":"west","serial":9007199254740992,"label":"first"},{"site":"west","serial":9007199254740993,"label":"second"}]}
  let backing = admit_relation_document(@utf8.encode(input), limits, 1000000).unwrap()
  let prepared = prepare_relation_document_key_contract(
    declaration,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let document = project_relation_target_document_from_catalog_key(
    backing,
    declaration,
    "records",
    ["records"],
    Some(["keys"]),
    None,
    Some(prepared),
    [],
  ).unwrap()
  assert_eq(relation_target_row_count(document), Some(2))
  assert_eq(
    relation_target_before(relation_target_observation(document, 0).unwrap()),
    Some(
      "{\"label\":\"first\",\"serial\":\"9007199254740992\",\"site\":\"west\"}",
    ),
  )
  assert_eq(
    relation_target_before(relation_target_observation(document, 1).unwrap()),
    Some(
      "{\"label\":\"second\",\"serial\":\"9007199254740993\",\"site\":\"west\"}",
    ),
  )
  assert_eq(relation_target_row_identity(document, 0), None)
  let first = observe_relation_target_from_catalog_key(
    document, declaration, "[\"west\",\"9007199254740992\"]",
  ).unwrap()
  let second = observe_relation_target_from_catalog_key(
    document, declaration, "[\"west\",\"9007199254740993\"]",
  ).unwrap()
  assert_eq(
    relation_target_before(first),
    Some(
      "{\"label\":\"first\",\"serial\":\"9007199254740992\",\"site\":\"west\"}",
    ),
  )
  assert_eq(
    relation_target_before(second),
    Some(
      "{\"label\":\"second\",\"serial\":\"9007199254740993\",\"site\":\"west\"}",
    ),
  )
  assert_true(
    observe_relation_target_from_catalog_key(document, declaration, "west")
    is Err(InvalidPage),
  )
  assert_true(
    observe_relation_target_from_catalog_key(
      document, declaration, "[\"west\",9007199254740993]",
    )
    is Err(_),
  )
  assert_true(
    observe_relation_target_from_catalog_key(
      document, declaration, "[\"west\", \"9007199254740993\"]",
    )
    is Err(InvalidPage),
  )
  assert_true(
    observe_relation_target_from_catalog_key(
      document,
      ordered_file_target_fixture(),
      "[\"west\",\"9007199254740993\"]",
    )
    is Err(ForeignSource),
  )
  assert_true(
    observe_relation_target_from_catalog_key(
      document, declaration, "[\"west\",\"9007199254740994\"]",
    )
    is Err(InvalidPage),
  )
  let before = relation_document_usage(backing).unwrap()
  assert_true(
    prepare_relation_document_key_contract(
      declaration,
      "records",
      ["serial", "site"],
      limits,
    )
    is Err(_),
  )
  assert_true(
    project_relation_target_document_from_catalog_key(
      backing,
      ordered_file_target_fixture(),
      "records",
      ["records"],
      Some(["keys"]),
      None,
      Some(prepared),
      [],
    )
    is Err(ForeignSource),
  )
  let after = relation_document_usage(backing).unwrap()
  assert_eq(after.projection_attempts, before.projection_attempts + 1)
  assert_eq(after.projections, before.projections)
  assert_true(after.remaining_work < before.remaining_work)
  assert_true(discard_relation_target_document_original(document))
  assert_true(
    observe_relation_target_from_catalog_key(
      document, declaration, "[\"west\",\"9007199254740993\"]",
    )
    is Err(ForeignSource),
  )
  assert_true(discard_relation_document_original(backing))
}

///|
test "ordered file target matches the exact typed tuple and updates only its original row" {
  let limits = relation_document_test_limits()
  let declaration = ordered_file_target_fixture()
  let prepared = prepare_relation_document_key_contract(
    declaration,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let input =
    #|{"keys":["site","serial"],"records":[{"site":"west|a","serial":9007199254740992,"label":"keep"},{"site":"west|a","serial":9007199254740993,"label":"change"},{"site":"east","serial":9007199254740993,"label":null}],"control":[{"label":"change"}]}
  let backing = admit_relation_document(@utf8.encode(input), limits, 1000000).unwrap()
  let ordered = project_relation_target_document_with_key(
    backing,
    declaration,
    "records",
    ["records"],
    Some(["keys"]),
    ["label"],
    prepared,
  ).unwrap()
  let key_wire = "[\"west|a\",\"9007199254740993\"]"
  let key = ordered_file_target_wire_key(key_wire)
  let captured = admit_relation_target_key(ordered, key).unwrap()
  let writer = @encode.writer(key_wire.length(), 3, 2)
  emit_relation_target_key(captured, writer)
  assert_eq(@encode.finish(writer), key_wire)
  let row = observe_relation_target_with_key(ordered, declaration, key).unwrap()
  assert_eq(
    relation_target_before(row),
    Some(
      "{\"label\":\"change\",\"serial\":\"9007199254740993\",\"site\":\"west|a\"}",
    ),
  )
  let document = relation_ordered_target_document(ordered)
  let original_version = relation_target_version(row).unwrap()
  let output = prepare_relation_target_update(
    document, row, original_version, "{\"label\":\"\"}", 1000000,
  ).unwrap()
  let expected =
    #|{"keys":["site","serial"],"records":[{"site":"west|a","serial":9007199254740992,"label":"keep"},{"site":"west|a","serial":9007199254740993,"label":""},{"site":"east","serial":9007199254740993,"label":null}],"control":[{"label":"change"}]}
  assert_eq(@utf8.decode(output), expected)
  let reopened_backing = admit_relation_document(output, limits, 1000000).unwrap()
  let reopened = project_relation_target_document_with_key(
    reopened_backing,
    declaration,
    "records",
    ["records"],
    Some(["keys"]),
    ["label"],
    prepared,
  ).unwrap()
  let changed = find_relation_target_with_key(reopened, declaration, captured)
    .unwrap()
    .unwrap()
  assert_eq(relation_target_text(changed, "label"), Some(""))
  let reopened_document = relation_ordered_target_document(reopened)
  assert_true(
    prepare_relation_target_delete(
      reopened_document, changed, original_version, 1000000,
    )
    is Err(ForeignSource),
  )
  let deleted = prepare_relation_target_delete(
    reopened_document,
    changed,
    relation_target_version(changed).unwrap(),
    1000000,
  ).unwrap()
  let expected_deleted =
    #|{"keys":["site","serial"],"records":[{"site":"west|a","serial":9007199254740992,"label":"keep"},{"site":"east","serial":9007199254740993,"label":null}],"control":[{"label":"change"}]}
  assert_eq(@utf8.decode(deleted), expected_deleted)
  assert_true(discard_relation_target_row_original(changed))
  let missing = admit_relation_target_key(
    reopened,
    ordered_file_target_wire_key("[\"west|a\",\"9007199254740994\"]"),
  ).unwrap()
  assert_true(
    find_relation_target_with_key(reopened, declaration, missing) is Ok(None),
  )
  let other_layout = prepare_relation_document_key_contract(
    declaration,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let other = project_relation_target_document_with_key(
    reopened_backing,
    declaration,
    "records",
    ["records"],
    Some(["keys"]),
    ["label"],
    other_layout,
  ).unwrap()
  assert_true(
    find_relation_target_with_key(other, declaration, captured)
    is Err(ForeignSource),
  )
  reopened_backing.work.val = 0
  assert_true(
    find_relation_target_with_key(reopened, declaration, missing)
    is Err(InvalidPage),
  )
  assert_true(
    discard_relation_target_document_original(
      relation_ordered_target_document(other),
    ),
  )
  assert_true(
    discard_relation_target_document_original(
      relation_ordered_target_document(reopened),
    ),
  )
  assert_true(discard_relation_document_original(reopened_backing))
  assert_true(
    observe_relation_target(document, declaration, "west|a")
    is Err(InvalidInputSchema),
  )
  assert_true(
    observe_relation_target_with_key(
      ordered,
      declaration,
      ordered_file_target_wire_key("[\"west|a\",9007199254740993]"),
    )
    is Err(Value("serial")),
  )
  assert_true(
    observe_relation_target_with_key(
      ordered,
      declaration,
      ordered_file_target_wire_key("[\"west|a\",null]"),
    )
    is Err(Value("serial")),
  )
  assert_true(
    observe_relation_target_with_key(
      ordered,
      ordered_file_target_fixture(),
      key,
    )
    is Err(ForeignSource),
  )
  assert_true(discard_relation_target_row_original(row))
  assert_true(discard_relation_target_document_original(document))
  assert_true(
    observe_relation_target_with_key(ordered, declaration, key)
    is Err(ForeignSource),
  )
  assert_true(discard_relation_document_original(backing))
}

///|
test "ordered file target refuses reversed declarations, mutable key fields, and duplicate tuples" {
  let limits = relation_document_test_limits()
  let original = relation_document_mapping_construction_inventory(limits).unwrap()
  let pair = relation_document_key_metadata_construction_inventory(limits, 2).unwrap()
  let triple = relation_document_key_metadata_construction_inventory(limits, 3).unwrap()
  assert_true(pair.record_headers > original.record_headers)
  assert_true(pair.owned_utf16_units > original.owned_utf16_units)
  assert_eq(triple.record_headers, pair.record_headers)
  assert_eq(triple.reference_slots, pair.reference_slots)
  assert_eq(triple.scalar_words, pair.scalar_words + 3L)
  assert_true(
    relation_document_key_metadata_construction_inventory(limits, 1) is None,
  )
  assert_true(
    relation_document_key_metadata_construction_inventory(
      limits,
      limits.max_nodes + 1,
    )
    is None,
  )
  let declaration = ordered_file_target_fixture()
  assert_true(
    prepare_relation_document_key_contract(
      declaration,
      "records",
      ["serial", "site"],
      limits,
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_relation_document_key_contract(
      declaration,
      "records",
      ["site", "site"],
      limits,
    )
    is Err(InvalidSpecification),
  )
  let prepared = prepare_relation_document_key_contract(
    declaration,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let input =
    #|{"reversed":["serial","site"],"records":[{"site":"west","serial":9223372036854775807,"label":"a"},{"site":"west","serial":"9223372036854775807","label":"b"}]}
  let backing = admit_relation_document(@utf8.encode(input), limits, 1000000).unwrap()
  assert_true(
    project_relation_target_document_with_key(
      backing,
      declaration,
      "records",
      ["records"],
      Some(["reversed"]),
      ["label"],
      prepared,
    )
    is Err(InvalidInputSchema),
  )
  assert_true(
    project_relation_target_document_with_key(
      backing,
      declaration,
      "records",
      ["records"],
      None,
      ["serial"],
      prepared,
    )
    is Err(InvalidInputSchema),
  )
  assert_true(
    project_relation_target_document_with_key(
      backing,
      declaration,
      "records",
      ["records"],
      None,
      ["label"],
      prepared,
    )
    is Err(InvalidPage),
  )
  assert_true(discard_relation_document_original(backing))
}

///|
test "ordered file insert requires complete absence and uses the exact tuple" {
  let limits = relation_document_test_limits()
  let declaration = ordered_file_target_fixture()
  let prepared = prepare_relation_document_key_contract(
    declaration,
    "records",
    ["site", "serial"],
    limits,
  ).unwrap()
  let input =
    #|{"keys":["site","serial"],"records":[{"site":"west","serial":9223372036854775806,"label":"keep"},{"site":"east","serial":9223372036854775807,"label":null}  ],"control":["untouched"]}
  let key = "[\"west\",\"9223372036854775807\"]"
  let mapped = "{\"label\":\"new\"}"
  let work = 1000000
  let backing = admit_relation_document(@utf8.encode(input), limits, work).unwrap()
  let inserted = prepare_relation_target_insert_with_key(
    backing,
    prepared,
    ["records"],
    Some(["keys"]),
    key,
    mapped,
  ).unwrap()
  let expected =
    #|{"keys":["site","serial"],"records":[{"site":"west","serial":9223372036854775806,"label":"keep"},{"site":"east","serial":9223372036854775807,"label":null},{"label":"new","serial":9223372036854775807,"site":"west"}  ],"control":["untouched"]}
  assert_eq(@utf8.decode(inserted), expected)
  let exact_work = work - backing.work.val
  assert_true(discard_relation_document_original(backing))

  let exact = admit_relation_document(@utf8.encode(input), limits, exact_work).unwrap()
  assert_eq(
    prepare_relation_target_insert_with_key(
      exact,
      prepared,
      ["records"],
      Some(["keys"]),
      key,
      mapped,
    ).unwrap(),
    inserted,
  )
  assert_true(discard_relation_document_original(exact))
  let short = admit_relation_document(
    @utf8.encode(input),
    limits,
    exact_work - 1,
  ).unwrap()
  assert_true(
    prepare_relation_target_insert_with_key(
      short,
      prepared,
      ["records"],
      Some(["keys"]),
      key,
      mapped,
    )
    is Err(InvalidPage),
  )
  assert_true(discard_relation_document_original(short))
  let reopened = admit_relation_document(inserted, limits, work).unwrap()
  assert_true(
    prepare_relation_target_insert_with_key(
      reopened,
      prepared,
      ["records"],
      Some(["keys"]),
      key,
      mapped,
    )
    is Err(InvalidPage),
  )
  assert_true(discard_relation_document_original(reopened))

  let original = admit_relation_document(@utf8.encode(input), limits, work).unwrap()
  assert_true(
    prepare_relation_target_insert_with_key(
      original,
      prepared,
      ["records"],
      Some(["keys"]),
      key,
      "{\"label\":\"new\",\"serial\":\"1\"}",
    )
    is Err(ForeignSource),
  )
  assert_true(
    prepare_relation_target_insert_with_key(
      original,
      prepared,
      ["records"],
      Some(["keys"]),
      "[\"west\",\"9223372036854775808\"]",
      mapped,
    )
    is Err(Value("serial")),
  )
  assert_true(
    prepare_relation_target_insert_with_key(
      original,
      prepared,
      ["records"],
      Some(["keys"]),
      "[\"west\", \"9223372036854775807\"]",
      mapped,
    )
    is Err(InvalidPage),
  )
  assert_true(discard_relation_document_original(original))
}
