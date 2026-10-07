///|
// Resealing negative inputs exercises semantic admission, not stale self-CIDs.
// Fixed positive expectations come from the independent Node corpus.
fn table_test_reseal(wire : String, field : String) -> String {
  let source = @source.parse_json(wire, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 8,
  }).unwrap()
  let value = @json.from_source(source, 256, 8, 8192) catch {
    _ => abort("invalid test JSON")
  }
  let body = @json.object_without_field(value, field).unwrap()
  let cid = @json.cid_value(body, 8192, 256, 8) catch {
    _ => abort("invalid test preimage")
  }
  let envelope = @json.object_with_string_field(body, field, cid).unwrap()
  @json.stringify_value(envelope, 8192, 256, 8) catch {
    _ => abort("invalid test wire")
  }
}

///|
test "bulk Table operation admits independent create and replace identities" {
  let create = admit_table_operation(table_vector_create(), 8192, 256, 8).unwrap()
  let replace = admit_table_operation(table_vector_replace(), 8192, 256, 8).unwrap()
  assert_eq(create.cid, table_vector_create_cid())
  assert_eq(replace.cid, table_vector_replace_cid())
  assert_false(create.replace)
  assert_true(replace.replace)
  assert_eq(create.expected_uuid, None)
  assert_eq(replace.expected_generation_cid, Some("sha256:" + "9".repeat(64)))
  assert_eq(create.input_relation_cid, "sha256:" + "5".repeat(64))
  assert_eq(create.mapping_cid, "sha256:" + "7".repeat(64))
  assert_true(create.cid != replace.cid)
}

///|
test "bulk Table operation rejects changed material and mixed action guards" {
  let wire = table_vector_create()
  assert_true(
    admit_table_operation(wire + " ", 8192, 256, 8) is Err(InvalidWire),
  )
  assert_true(admit_table_operation(wire, 8, 256, 8) is Err(InvalidWire))
  assert_true(admit_table_operation(wire, 8192, 0, 8) is Err(InvalidLimits))
  let changed = wire.replace(
    old="\"input_relation_cid\":\"sha256:" + "5".repeat(64),
    new="\"input_relation_cid\":\"sha256:" + "f".repeat(64),
  )
  assert_true(
    admit_table_operation(changed, 8192, 256, 8) is Err(InvalidIdentity),
  )
  let unguarded = table_test_reseal(
    wire.replace(old="\"action\":\"create\"", new="\"action\":\"replace\""),
    "request_cid",
  )
  assert_true(
    admit_table_operation(unguarded, 8192, 256, 8) is Err(InvalidShape),
  )
  let extra = table_test_reseal(
    wire.replace(
      old="\"namespace\":[\"analytics\"]",
      new="\"item_key\":\"invented\",\"namespace\":[\"analytics\"]",
    ),
    "request_cid",
  )
  assert_true(admit_table_operation(extra, 8192, 256, 8) is Err(InvalidShape))
  let empty_namespace = table_test_reseal(
    wire.replace(old="\"namespace\":[\"analytics\"]", new="\"namespace\":[]"),
    "request_cid",
  )
  assert_true(
    admit_table_operation(empty_namespace, 8192, 256, 8) is Err(InvalidShape),
  )
}

///|
test "bulk Table receipt supports typed empty commit and exact long snapshot IDs" {
  let create = admit_table_operation(table_vector_create(), 8192, 256, 8).unwrap()
  let empty = admit_table_receipt(
    create,
    table_vector_empty_receipt(),
    8192,
    256,
    8,
  ).unwrap()
  assert_eq(empty.cid, table_vector_empty_receipt_cid())
  assert_eq(empty.snapshot_id, None)
  assert_eq(empty.row_count, 0L)
  let replace = admit_table_operation(table_vector_replace(), 8192, 256, 8).unwrap()
  let receipt = admit_table_receipt(
    replace,
    table_vector_replacement_receipt(),
    8192,
    256,
    8,
  ).unwrap()
  assert_eq(receipt.cid, table_vector_replacement_receipt_cid())
  assert_eq(receipt.snapshot_id, Some("9223372036854775807"))
  assert_eq(receipt.row_count, 3L)
}

///|
test "bulk Table receipt cannot settle another operation or reuse expected head" {
  let create = admit_table_operation(table_vector_create(), 8192, 256, 8).unwrap()
  let replace = admit_table_operation(table_vector_replace(), 8192, 256, 8).unwrap()
  assert_true(
    admit_table_receipt(
      create,
      table_vector_replacement_receipt(),
      8192,
      256,
      8,
    )
    is Err(ForeignOperation),
  )
  let wire = table_vector_replacement_receipt()
  let same_head = table_test_reseal(
    wire.replace(
      old="\"generation_cid\":\"sha256:" + "b".repeat(64),
      new="\"generation_cid\":\"sha256:" + "9".repeat(64),
    ),
    "receipt_cid",
  )
  assert_true(
    admit_table_receipt(replace, same_head, 8192, 256, 8)
    is Err(ForeignOperation),
  )
  let foreign = table_test_reseal(
    wire.replace(
      old="01234567-89ab-cdef-0123-456789abcdef",
      new="fedcba98-7654-3210-fedc-ba9876543210",
    ),
    "receipt_cid",
  )
  assert_true(
    admit_table_receipt(replace, foreign, 8192, 256, 8) is Err(ForeignOperation),
  )
  let overflow = table_test_reseal(
    wire.replace(old="9223372036854775807", new="9223372036854775808"),
    "receipt_cid",
  )
  assert_true(
    admit_table_receipt(replace, overflow, 8192, 256, 8) is Err(InvalidShape),
  )
}

///|
test "Table commit projection admits only the original receipt and exact row count" {
  let operation = admit_table_operation(table_vector_create(), 8192, 256, 8).unwrap()
  let response = "{\"ok\":true,\"result\":" + table_vector_empty_receipt() + "}"
  let outcome = project_table_commit_outcome(operation, response, 200, 0L, 8192, 256, 8).unwrap()
  assert_eq(outcome, "{\"result\":" + table_vector_empty_receipt() + ",\"state\":\"applied\"}")
  assert_true(@publication.parse_effect_outcome_shape(outcome, 8192, 256, 8) is Ok(_))
  assert_true(project_table_commit_outcome(operation, response, 200, 1L, 8192, 256, 8) is Err(ForeignRowCount))
  let foreign = "{\"ok\":true,\"result\":" + table_vector_replacement_receipt() + "}"
  assert_true(project_table_commit_outcome(operation, foreign, 200, 0L, 8192, 256, 8) is Err(Receipt(ForeignOperation)))
}

///|
test "Table commit projection never infers commit or noncommit from an HTTP status" {
  let operation = admit_table_operation(table_vector_create(), 8192, 256, 8).unwrap()
  for wire in ["{}", "{\"accepted\":true}", "{\"ok\":true,\"result\":null}", "{\"ok\":false,\"code\":\"conflict\"}", "{\"ok\":true,\"result\":{},\"extra\":true}"] {
    assert_true(project_table_commit_outcome(operation, wire, 200, 0L, 8192, 256, 8) is Err(_))
  }
  let response = "{\"ok\":true,\"result\":" + table_vector_empty_receipt() + "}"
  for status in [202, 409, 500] {
    assert_true(project_table_commit_outcome(operation, response, status, 0L, 8192, 256, 8) is Err(Unconfirmed))
  }
  assert_true(project_table_commit_outcome(operation, response, 200, 0L, 8, 256, 8) is Err(InvalidResponse))
  assert_true(project_table_commit_outcome(operation, response, 200, 0L, 8192, 0, 8) is Err(InvalidLimits))
}
