///|
test "portable bootstrap supplies the same original metadata and engine bodies" {
  let packet = client_local_product_bootstrap_originals(
    "/Users/operator/.actql-local", "2026-10-12T00:00:00.000Z",
  ).unwrap()
  let original = client_local_product_common_originals(
    "/Users/operator/.actql-local",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
  ).unwrap()
  assert_eq(packet.common.account, original.account)
  assert_eq(packet.common.store, original.store)
  assert_eq(packet.common.retention_policy, original.retention_policy)
  assert_eq(
    packet.common.retention_dependencies,
    original.retention_dependencies,
  )
  assert_eq(packet.common.result_policy, original.result_policy)
  assert_eq(
    product_cid(product_common_test_bytes(packet.common.result_policy)),
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  assert_eq(packet.environment, product_test_environment_wire())
  let compute = product_asset_value(packet.compute).unwrap()
  for
    (field, expected) in [
      ("registry", compiler_registered_body_wire()),
      ("values", compiler_registered_values_wire()),
      ("fragment", product_test_fragment_wire()),
      ("ordered", compiler_registered_ordered_wire()),
    ] {
    assert_eq(product_test_text(product_test_field(compute, [field])), expected)
  }
}

///|
test "portable bootstrap rejects invalid location and clock without refreshing originals" {
  assert_true(
    client_local_product_bootstrap_originals(
      "relative", "2026-10-12T00:00:00.000Z",
    )
    is Err(InvalidLocation),
  )
  assert_true(
    client_local_product_bootstrap_originals(
      "/Users/operator/.actql-local", "not-a-clock",
    )
    is Err(InvalidObservationTime),
  )
}
