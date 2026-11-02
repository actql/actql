///|
test "GCS declaration construction quote funds actual extension and original collection mapping" {
  let limits = upload_limits()
  let original = upload_empty_catalog_fixture()
  let capacity = object_upload_catalog_construction_capacity(
    original, 7, limits,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  assert_true(retained < peak)
  // Preserve the prior complete prefix; the escaped graph is additional.
  let old_peak = upload_peak_capacity(
    upload_catalog_peak_inventory(original, 7, limits).unwrap(),
  ).unwrap()
  assert_true(peak >= @execution.execution_capacity_execution_bytes(old_peak))
  assert_true(peak >= 2107777L)
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 2,
    transfer_bytes: 0L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let first = @resources.reserve_capacity(ledger, peak, peak).unwrap()
  let declared_wire = object_upload_catalog_json(original, "exports", limits).unwrap()
  let mapping_capacity = object_collection_mapping_construction_capacity(
    declared_wire,
    7,
    6,
    8,
    "connector://exports/objects".length(),
    7,
    limits,
  ).unwrap()
  let mapping_peak = @execution.execution_capacity_execution_bytes(
    mapping_capacity,
  )
  let mapping_retained = @execution.execution_capacity_retained_bytes(
    mapping_capacity,
  )
  assert_true(mapping_retained < mapping_peak)
  assert_true(mapping_peak >= 18822064L)
  println(
    "GCS constructor input_units=\{original.length()} extension_bytes=\{peak} mapping_input_units=\{declared_wire.length()} mapping_bytes=\{mapping_peak} extension_retained=\{retained} mapping_retained=\{mapping_retained}",
  )
  assert_true(peak + mapping_peak < 536870912L)
  let second = @resources.reserve_capacity(ledger, mapping_peak, mapping_peak).unwrap()
  guard @json.parse(declared_wire) is Object(declared) &&
    declared["catalog_cid"] is String(catalog_cid) else {
    abort("GCS declaration fixture")
  }
  let binding = prepare_object_collection_binding(
    "project",
    "bucket",
    "exports/",
    "connector://exports/objects",
    "file_collection",
    catalog_cid,
    "sha256:" + "b".repeat(64),
    {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    },
  ).unwrap()
  let mapping = object_upload_mapping_json(
    binding, declared_wire, "exports", limits,
  ).unwrap()
  assert_true(mapping.contains("actql.mapping_contract/0.1"))
  let (_, _, output, output_nodes, _, _, _) = upload_catalog_bounds(
    original, 7, limits,
  ).unwrap()
  assert_true(declared_wire.length() <= output)
  assert_true(construction_actual_nodes(declared_wire) <= output_nodes)
  assert_true(retained >= 2L * declared_wire.length().to_int64())
  let escaped_text = object_collection_identity_json(binding).length() +
    object_collection_identity_cid(binding).length() +
    object_collection_resource_json(binding).length() +
    mapping.length()
  assert_true(mapping_retained >= 2L * escaped_text.to_int64())
  assert_eq(
    object_upload_catalog_json(declared_wire, "exports", limits).unwrap(),
    declared_wire,
  )
  @resources.settle_capacity(ledger, second).unwrap()
  @resources.settle_capacity(ledger, first).unwrap()
  assert_false(
    @resources.ledger_usage_has_pending_resources(
      @resources.ledger_usage(ledger),
    ),
  )
}

///|
test "GCS fixed declaration producer geometry matches its construction template" {
  let limits = upload_limits()
  let wire = object_upload_command_json("exports", limits).unwrap()
  let parsed = @source.parse_json(wire, {
    max_input_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_bytes,
    max_total_string_bytes: limits.max_bytes,
  }).unwrap()
  assert_eq(@decode.admission_usage(cursor).nodes, 83)
  assert_eq(@utf8.encode(wire).length(), 1508 + 6 * 7 + 5 * 71)
  assert_true(@utf8.encode(wire).length().to_int64() <= upload_bundle_bytes(7))
  let (binding, declared_wire) = upload_mapping_fixture()
  let mapping = object_upload_mapping_json(
    binding, declared_wire, "exports", limits,
  ).unwrap()
  let mapped = @source.parse_json(mapping, {
    max_input_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }).unwrap()
  let mapped_cursor = @decode.admit(mapped, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_bytes,
    max_total_string_bytes: limits.max_bytes,
  }).unwrap()
  assert_eq(@decode.admission_usage(mapped_cursor).nodes, 103)
  assert_eq(
    @utf8.encode(mapping).length(),
    1885 + 2 * 7 + "connector://exports/objects".length() + 6 * 71,
  )
}

///|
test "GCS declaration quote rejects impossible geometry and Ledger refuses before producer entry" {
  let limits = upload_limits()
  assert_true(
    object_upload_catalog_construction_capacity("", 7, {
      ..limits,
      max_bytes: 0,
    })
    is None,
  )
  assert_true(
    object_upload_catalog_construction_capacity("0", 2147483647, limits) is None,
  )
  assert_true(
    object_collection_mapping_construction_capacity("0", -1, 1, 1, 1, 1, limits)
    is None,
  )
  let original = upload_empty_catalog_fixture()
  let quote = object_upload_catalog_construction_capacity(original, 7, limits).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(quote)
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: peak - 1L,
    execution_bytes: peak,
  }).unwrap()
  assert_true(@resources.reserve_capacity(ledger, peak, peak) is Err(_))
  assert_false(
    @resources.ledger_usage_has_pending_resources(
      @resources.ledger_usage(ledger),
    ),
  )
}

///|
fn construction_actual_nodes(wire : String) -> Int {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 1048576,
    max_nodes: 100000,
    max_depth: 128,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 100000,
    max_depth: 128,
    max_string_bytes: 1048576,
    max_total_string_bytes: 1048576,
  }).unwrap()
  @decode.admission_usage(cursor).nodes
}

///|
test "GCS nonallocating wire scan bounds real parser geometry and escaped detached originals" {
  let samples = [
    "null", "true", "0", "-12.5e3", "\"\"", "[]", "{}", "[null,false,0,{},[]]", "{\"a\":[1,{\"b\":[2,3]}],\"c\":null}",
    "{\"日本語😀\":\"\\\"\\\\{},:[]\",\"x\":\"\\u005b\\u007b\\u003a\\u002c\"}",
  ]
  for wire in samples {
    assert_true(
      upload_structural_node_bound(wire) >=
      construction_actual_nodes(wire).to_int64(),
    )
  }
  // Embedded syntax is represented both literally and via Unicode escapes;
  // no parsed tree is used by the quantity producer itself.
  let literal = "{\"catalog\":\"[null,{\\\"x\\\":[1,2]}]\"}"
  let escaped = "{\"catalog\":\"\\u005bnull\\u002c\\u007b\\u0022x\\u0022\\u003a\\u005b1\\u002c2\\u005d\\u007d\\u005d\"}"
  for wire in [literal, escaped] {
    guard @json.parse(wire) is Object(fields) &&
      fields["catalog"] is String(inner) else {
      abort("embedded fixture")
    }
    assert_true(
      upload_structural_node_bound(wire) >=
      construction_actual_nodes(wire).to_int64(),
    )
    assert_true(
      upload_structural_node_bound(wire) >=
      construction_actual_nodes(inner).to_int64(),
    )
  }
  let registry = "{\"contracts\":{\"a\":\"null\",\"b\":\"[]\",\"c\":\"[0,0]\"}}"
  assert_true(
    upload_structural_node_bound(registry) >=
    (construction_actual_nodes("null") +
    construction_actual_nodes("[]") +
    construction_actual_nodes("[0,0]")).to_int64(),
  )
  // A malformed suffix does not add allocated values before their lexical
  // introducer. The parser rejects these prefixes under the SAME ceilings;
  // the quote remains available for cleanup of construction failure.
  for wire in ["[", "{\"a\":", "[null,", "{\"a\":[0,", "\"\\u005"] {
    assert_true(
      @source.parse_json(wire, {
        max_input_bytes: 1048576,
        max_nodes: 100000,
        max_depth: 128,
      })
      is Err(_),
    )
    assert_true(
      object_upload_catalog_construction_capacity(wire, 7, upload_limits())
      is Some(_),
    )
  }
}
