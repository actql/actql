///|
fn product_expiry_original_retention(
  originals : Array[(String, Bytes)],
) -> @publication.PublicationContract {
  let run = product_asset_value(product_test_original(originals, "run.json")).unwrap()
  let wire = product_test_text(
    product_test_field(run, ["native", "run", "retention_policy_wire"]),
  )
  @publication.admit_publication_contract(
    "result_retention_policy", wire, 8192, 512, 8,
  ).unwrap()
}

///|
test "adoption-time product policy is finite and availability is separate from deletion" {
  let originals = product_test_originals()
  let retention = product_expiry_original_retention(originals)
  assert_true(@publication.result_retention_intervals_valid(retention))
  for
    (time, expected) in [
      ("2026-10-12T00:00:00.000Z", "available"),
      ("2026-10-12T23:59:59.999Z", "available"),
      ("2026-10-13T00:00:00.000Z", "available"),
      ("2026-10-13T00:00:00.001Z", "retention_expired"),
      ("2026-10-13T23:59:59.999Z", "retention_expired"),
      ("2026-10-14T00:00:00.000Z", "delete_due"),
    ] {
    assert_eq(
      @publication.result_retention_interval_state(retention, time),
      Ok(expected),
    )
  }
  assert_true(
    @publication.result_retention_interval_state(retention, "invalid") is Err(_),
  )
  let read = product_asset_value(product_test_original(originals, "read.json")).unwrap()
  assert_eq(
    product_test_text(
      product_test_field(read, ["native", "result_read", "expires_at"]),
    ),
    "2026-10-13T00:00:00.000Z",
  )
  // This checks the source-selected deadline, not Native's physical read
  // binding. Native's observed >= expires rule still needs its own acceptance.
}

///|
test "copying retained adoption originals never renews their policy or identity" {
  let originals = product_test_originals()
  let original = product_expiry_original_retention(originals)
  let retained = originals.copy()
  let restored = product_expiry_original_retention(retained)
  assert_eq(
    @publication.publication_contract_json(original),
    @publication.publication_contract_json(restored),
  )
  assert_eq(
    @publication.publication_contract_identity(original),
    @publication.publication_contract_identity(restored),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      restored, "2026-10-13T00:00:00.001Z",
    ),
    Ok("retention_expired"),
  )
  assert_eq(
    product_test_original(retained, "read.json"),
    product_test_original(originals, "read.json"),
  )
  // A bytes copy is not a real restart or re-adoption receipt. It fixes the
  // no-refresh invariant while the physical process cases remain unexecuted.
}
