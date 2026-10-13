///|
// Fixed intervals are independent of the installed consumer's generated policy.
fn interval_projection_retention() -> PublicationContract {
  interval_projection_retention_at("2026-10-13T08:00:00.000Z")
}

///|
fn interval_projection_retention_at(
  available_until : String,
) -> PublicationContract {
  seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    delivery_test_cid("a") +
    "\",\"effective_data_policy_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"available_until\":\"" +
    available_until +
    "\"," +
    "\"delete_by\":\"2026-10-14T08:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-10-14T08:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"metadata_delete_by\":\"2026-10-19T08:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    delivery_test_cid("d") +
    "\"}",
    32768,
    256,
    16,
  ).unwrap()
}

///|
test "Local retention preparation admits an available original policy" {
  let retention = interval_projection_retention()
  assert_true(result_retention_intervals_valid(retention))
  assert_eq(
    result_retention_interval_state(retention, "2026-10-12T08:00:00.000Z"),
    Ok("available"),
  )
  // The old getter still requires a real Manifest and a Result name.
  assert_eq(
    result_read_retention_policy_cid(retention, "2026-10-12T08:00:00.000Z"),
    Err(DeliveryIssuanceWrongContract("result_manifest")),
  )
}

///|
test "Local retention interval projection preserves exact expiry boundaries" {
  let retention = interval_projection_retention()
  let original_wire = publication_contract_json(retention)
  assert_eq(
    result_retention_interval_state(retention, "2026-10-13T08:00:00.000Z"),
    Ok("available"),
  )
  assert_eq(
    result_retention_interval_state(retention, "2026-10-13T08:00:00.001Z"),
    Ok("retention_expired"),
  )
  assert_eq(
    result_retention_interval_state(retention, "2026-10-14T08:00:00.000Z"),
    Ok("delete_due"),
  )
  // Metadata retention does not extend payload availability.
  assert_eq(
    result_metadata_retention_state(retention, "2026-10-14T08:00:00.000Z"),
    Ok("retained"),
  )
  assert_eq(publication_contract_json(retention), original_wire)
}

///|
test "Local retention interval projection refuses absent or malformed time" {
  let retention = interval_projection_retention()
  for time in ["", "not-a-time", "2026-10-12", "2026-10-12T08:00:00Z"] {
    assert_eq(
      result_retention_interval_state(retention, time),
      Err(DeliveryIssuanceReferenceMismatch("retention_interval")),
    )
  }
}

///|
test "Local retention interval projection preserves invalid interval refusal" {
  let invalid = interval_projection_retention_at("2026-10-15T08:00:00.000Z")
  assert_false(result_retention_intervals_valid(invalid))
  assert_eq(
    result_retention_interval_state(invalid, "2026-10-12T08:00:00.000Z"),
    Err(DeliveryIssuanceReferenceMismatch("retention_interval")),
  )
  assert_true(
    admit_publication_contract("result_retention_policy", "", 32768, 256, 16)
    is Err(_),
  )
}

///|
test "Local retention interval projection does not authorize a foreign Result" {
  let retention = interval_projection_retention()
  let (_, manifest, _) = delivery_test_root()
  assert_eq(
    result_retention_interval_state(manifest, "2026-10-12T08:00:00.000Z"),
    Err(DeliveryIssuanceReferenceMismatch("retention_interval")),
  )
  assert_eq(
    result_retention_interval_state(retention, "2026-10-12T08:00:00.000Z"),
    Ok("available"),
  )
  assert_eq(
    result_read_availability(
      manifest, "answer", retention, "2026-10-12T08:00:00.000Z",
    ),
    Err(DeliveryIssuanceReferenceMismatch("effective_retention_policy_cid")),
  )
}

///|
test "finite Run expiry projection preserves saved availability without renewal or grant" {
  let retention = interval_projection_retention()
  let original = publication_contract_json(retention)
  assert_eq(
    result_retention_available_until(retention),
    Ok("2026-10-13T08:00:00.000Z"),
  )
  assert_eq(publication_contract_json(retention), original)
  assert_eq(
    result_retention_available_until(
      interval_projection_retention_at("2026-10-15T08:00:00.000Z"),
    ),
    Err(DeliveryIssuanceReferenceMismatch("retention_interval")),
  )
  let (_, manifest, _) = delivery_test_root()
  assert_eq(
    result_retention_available_until(manifest),
    Err(DeliveryIssuanceWrongContract("result_retention_policy")),
  )
}
