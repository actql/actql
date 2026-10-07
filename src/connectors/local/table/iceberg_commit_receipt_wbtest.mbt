///|
fn iceberg_test_reseal(wire : String) -> String {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 8,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 8, 8192) catch {
    _ => abort("fixture")
  }
  let body = @json.object_without_field(value, "receipt_cid").unwrap()
  let cid = @json.cid_value(body, 8192, 256, 8) catch { _ => abort("fixture") }
  let envelope = @json.object_with_string_field(body, "receipt_cid", cid).unwrap()
  @json.stringify_value(envelope, 8192, 256, 8) catch {
    _ => abort("fixture")
  }
}

///|
test "Local physical receipts project independently sealed logical facts without replacing evidence" {
  assert_true(
    iceberg_vector_empty_physical().contains(
      "sha256:149de5e72a2606adbd663368827a94e5a297aa5105577c8984ed1e97d488290b",
    ),
  )
  for
    (request, physical, logical, count) in [
      (
        iceberg_vector_empty_request(),
        iceberg_vector_empty_physical(),
        iceberg_vector_empty_logical(),
        0L,
      ),
      (
        iceberg_vector_replacement_request(),
        iceberg_vector_replacement_physical(),
        iceberg_vector_replacement_logical(),
        3L,
      ),
    ] {
    let operation = @effect.admit_table_operation(request, 8192, 256, 8).unwrap()
    let original = "{\"ok\":true,\"result\":" + physical + "}"
    let projected = project_iceberg_commit_response(original, 200, 8192, 256, 8).unwrap()
    assert_eq(projected, "{\"ok\":true,\"result\":" + logical + "}")
    assert_eq(
      @effect.project_table_commit_outcome(
        operation, projected, 200, count, 8192, 256, 8,
      ).unwrap(),
      "{\"result\":" + logical + ",\"state\":\"applied\"}",
    )
    assert_false(projected.contains("metadata_location"))
    assert_false(projected.contains("snapshot_id"))
    assert_true(
      @effect.admit_table_receipt(operation, physical, 8192, 256, 8)
      is Err(@effect.InvalidShape),
    )
    // The common result itself cannot be passed off as Local physical proof.
    assert_true(
      project_iceberg_commit_response(projected, 200, 8192, 256, 8) is Err(_),
    )
  }
}

///|
test "Local receipt validation rejects invalid physical facts before common settlement" {
  let physical = iceberg_vector_replacement_physical()
  for
    changed in [
      physical.replace(old="9223372036854775807", new="9223372036854775808"),
      physical.replace(
        old="\"snapshot_id\":\"9223372036854775807\"",
        new="\"snapshot_id\":null",
      ),
      physical.replace(
        old="\"snapshot_id\":\"9223372036854775807\"",
        new="\"snapshot_id\":\"01\"",
      ),
      physical.replace(
        old="\"metadata_location\":\"file:///warehouse/tickets/metadata/00001.json\"",
        new="\"metadata_location\":\"\"",
      ),
    ] {
    let original = "{\"ok\":true,\"result\":" +
      iceberg_test_reseal(changed) +
      "}"
    assert_true(
      project_iceberg_commit_response(original, 200, 8192, 256, 8)
      is Err(@effect.Receipt(@effect.InvalidShape)),
    )
  }
  let stale = "{\"ok\":true,\"result\":" +
    physical.replace(old="\"row_count\":3", new="\"row_count\":4") +
    "}"
  assert_true(
    project_iceberg_commit_response(stale, 200, 8192, 256, 8)
    is Err(@effect.Receipt(@effect.InvalidIdentity)),
  )
  for wire in ["{}", "{\"accepted\":true}", "{\"ok\":true,\"result\":null}"] {
    assert_true(
      project_iceberg_commit_response(wire, 200, 8192, 256, 8) is Err(_),
    )
  }
  let original = "{\"ok\":true,\"result\":" + physical + "}"
  assert_true(
    project_iceberg_commit_response(original, 202, 8192, 256, 8)
    is Err(@effect.Unconfirmed),
  )
  assert_true(
    project_iceberg_commit_response(original, 200, 8192, 0, 8)
    is Err(@effect.InvalidLimits),
  )
}
